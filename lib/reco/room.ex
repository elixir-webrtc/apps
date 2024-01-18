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
       audio_track: nil,
       video_track: nil,
       video_depayloader: VP8Depayloader.new()
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
        {:noreply, state}

      state.video_track.id == track_id ->
        case VP8Depayloader.write(state.video_depayloader, packet) do
          {:ok, d} ->
            state = %{state | video_depayloader: d}
            {:noreply, state}

          {:ok, frame, d} ->
            Logger.info("Got full frame!")
            state = %{state | video_depayloader: d}
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected msg: #{inspect(msg)}")
    {:noreply, state}
  end
end
