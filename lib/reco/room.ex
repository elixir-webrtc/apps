defmodule Reco.Room do
  use GenServer, restart: :temporary

  require Logger

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias ExWebRTC.RTP.{OpusDepayloader, VP8Depayloader}

  defp id(room_id), do: {:via, Registry, {Reco.RoomRegistry, room_id}}

  def start_link([room_id, _channel] = opts) do
    GenServer.start_link(__MODULE__, opts, name: id(room_id))
  end

  def receive_signaling_msg(room_id, msg) do
    GenServer.cast(id(room_id), {:receive_signaling_msg, msg})
  end

  def stop(room_id) do
    GenServer.stop(id(room_id))
  end

  @impl true
  def init([room_id, channel]) do
    Logger.info("Starting room: #{room_id}")
    {:ok, pc} = PeerConnection.start_link()

    {:ok,
     %{
       pc: pc,
       channel: channel,
       video_track: nil,
       video_depayloader: VP8Depayloader.new(),
       video_decoder: Xav.Decoder.new(:vp8),
       video_serving: create_video_serving(),
       audio_track: nil,
       audio_decoder: Xav.Decoder.new(:opus),
       audio_serving: create_audio_serving(),
       audio_frames: []
     }}
  end

  @impl true
  def handle_cast({:receive_signaling_msg, msg}, state) do
    case Jason.decode!(msg) do
      %{"type" => "offer"} = offer ->
        {:ok, desc} = SessionDescription.from_json(offer)
        :ok = PeerConnection.set_remote_description(state.pc, desc)
        {:ok, answer} = PeerConnection.create_answer(state.pc)
        :ok = PeerConnection.set_local_description(state.pc, answer)
        msg = %{"type" => "answer", "sdp" => answer.sdp}
        send(state.channel, {:signaling, msg})

      %{"type" => "ice", "data" => data} ->
        candidate = %ICECandidate{
          candidate: data["candidate"],
          sdp_mid: data["sdpMid"],
          sdp_m_line_index: data["sdpMLineIndex"],
          username_fragment: data["usernameFragment"]
        }

        :ok = PeerConnection.add_ice_candidate(state.pc, candidate)

      _ ->
        Logger.warning("Unexpected msg: #{inspect(msg)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    candidate = %{
      "candidate" => candidate.candidate,
      "sdpMid" => candidate.sdp_mid,
      "sdpMLineIndex" => candidate.sdp_m_line_index,
      "usernameFragment" => candidate.username_fragment
    }

    send(state.channel, {:signaling, %{"type" => "ice", "data" => candidate}})
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:connection_state_change, :connected}}, state) do
    Logger.info("Connection state changed - connected!")
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:track, %{kind: :audio} = track}}, state) do
    {:noreply, %{state | audio_track: track}}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:track, %{kind: :video} = track}}, state) do
    {:noreply, %{state | video_track: track}}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:rtp, track_id, packet}}, state) do
    cond do
      state.audio_track.id == track_id ->
        audio = OpusDepayloader.depayload(packet)
        {:ok, frame} = Xav.Decoder.decode(state.audio_decoder, audio)
        state = %{state | audio_frames: [frame | state.audio_frames]}

        if Enum.count(state.audio_frames) == 100 do
          audio_frames = Enum.reverse(state.audio_frames)
          state = %{state | audio_frames: []}

          frames = Enum.map(audio_frames, &Xav.Frame.to_nx(&1))

          batch = Nx.Batch.concatenate(frames)
          batch = Nx.Defn.jit_apply(&Function.identity/1, [batch])
          Nx.Serving.run(state.audio_serving, batch) |> dbg()
          {:noreply, state}
        else
          {:noreply, state}
        end

      state.video_track.id == track_id ->
        case VP8Depayloader.write(state.video_depayloader, packet) do
          {:ok, d} ->
            state = %{state | video_depayloader: d}
            {:noreply, state}

          {:ok, frame, d} ->
            state = %{state | video_depayloader: d}

            case Xav.Decoder.decode(state.video_decoder, frame) do
              {:ok, frame} ->
                tensor = Xav.Frame.to_nx(frame)
                res = Nx.Serving.run(state.video_serving, tensor)
                send(state.channel, {:img_reco, res})
                {:noreply, state}

              {:error, :no_keyframe} ->
                Logger.warning("Couldn't decode video frame - missing keyframe!")
                {:noreply, state}
            end
        end
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp create_audio_serving() do
    {:ok, whisper} = Bumblebee.load_model({:hf, "openai/whisper-tiny"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "openai/whisper-tiny"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai/whisper-tiny"})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, "openai/whisper-tiny"})

    Bumblebee.Audio.speech_to_text_whisper(whisper, featurizer, tokenizer, generation_config,
      defn_options: [compiler: EXLA]
    )
  end

  defp create_video_serving() do
    {:ok, model} = Bumblebee.load_model({:hf, "microsoft/resnet-50"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})

    Bumblebee.Vision.image_classification(model, featurizer,
      top_k: 1,
      compile: [batch_size: 1],
      defn_options: [compiler: EXLA]
    )
  end
end
