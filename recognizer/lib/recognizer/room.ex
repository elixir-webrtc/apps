defmodule Recognizer.Room do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias ExWebRTC.{ICECandidate, PeerConnection, RTPCodecParameters, SessionDescription}
  alias ExWebRTC.RTP.{Depayloader, JitterBuffer}

  @max_session_time_s Application.compile_env!(:recognizer, :max_session_time_s)
  @session_time_timer_interval_ms 1_000
  @jitter_buffer_latency_ms 50

  @video_codecs [
    %RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }
  ]

  defp id(room_id), do: {:via, Registry, {Recognizer.RoomRegistry, room_id}}

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: id(room_id))
  end

  def connect(room_id, channel_pid) do
    GenServer.call(id(room_id), {:connect, channel_pid})
  end

  def receive_signaling_msg(room_id, msg) do
    GenServer.cast(id(room_id), {:receive_signaling_msg, msg})
  end

  def stop(room_id) do
    GenServer.stop(id(room_id), :shutdown)
  end

  @impl true
  def init(room_id) do
    Logger.info("Starting room: #{room_id}")
    Process.send_after(self(), :session_time, @session_time_timer_interval_ms)

    {:ok, video_depayloader} = @video_codecs |> hd() |> Depayloader.new()

    {:ok,
     %{
       id: room_id,
       pc: nil,
       channel: nil,
       task: nil,
       video_track: nil,
       video_depayloader: video_depayloader,
       video_decoder: Xav.Decoder.new(:vp8),
       video_buffer: JitterBuffer.new(latency: @jitter_buffer_latency_ms),
       audio_track: nil,
       session_start_time: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_call({:connect, channel_pid}, _from, %{channel: nil} = state) do
    Process.monitor(channel_pid)

    ice_port_range = Application.fetch_env!(:recognizer, :ice_port_range)

    {:ok, pc} =
      PeerConnection.start_link(
        video_codecs: @video_codecs,
        ice_port_range: ice_port_range
      )

    state =
      state
      |> Map.put(:channel, channel_pid)
      |> Map.put(:pc, pc)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:connect, _channel_pid}, _from, state) do
    {:reply, {:error, :already_connected}, state}
  end

  @impl true
  def handle_cast({:receive_signaling_msg, msg}, state) do
    case Jason.decode!(msg) do
      %{"type" => "offer"} = offer ->
        desc = SessionDescription.from_json(offer)
        :ok = PeerConnection.set_remote_description(state.pc, desc)
        {:ok, answer} = PeerConnection.create_answer(state.pc)
        :ok = PeerConnection.set_local_description(state.pc, answer)
        msg = %{"type" => "answer", "sdp" => answer.sdp}
        send(state.channel, {:signaling, msg})

      %{"type" => "ice", "data" => data} when data != nil ->
        candidate = ICECandidate.from_json(data)
        :ok = PeerConnection.add_ice_candidate(state.pc, candidate)

      _ ->
        Logger.warning("Unexpected msg: #{inspect(msg)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    candidate = ICECandidate.to_json(candidate)
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
  def handle_info(
        {:ex_webrtc, _pc, {:rtp, track_id, nil, packet}},
        %{video_track: %{id: track_id}} = state
      ) do
    state.video_buffer
    |> JitterBuffer.insert(packet)
    |> handle_jitter_buffer_result(state)
  end

  @impl true
  def handle_info(
        {:ex_webrtc, _pc, {:rtp, track_id, nil, _packet}},
        %{audio_track: %{id: track_id}} = state
      ) do
    # Do something fun with the audio!
    {:noreply, state}
  end

  @impl true
  def handle_info(:jitter_buffer_timer, state) do
    state.video_buffer
    |> JitterBuffer.handle_timeout()
    |> handle_jitter_buffer_result(state)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    if pid != state.channel do
      {:noreply, state}
    else
      Logger.info("Shutting down room as peer left")
      {:stop, :shutdown, state}
    end
  end

  @impl true
  def handle_info(:session_time, state) do
    Process.send_after(self(), :session_time, @session_time_timer_interval_ms)
    now = System.monotonic_time(:millisecond)
    duration = floor((now - state.session_start_time) / 1000)

    rem_time = max(0, @max_session_time_s - duration)

    if state.channel != nil do
      send(state.channel, {:session_time, rem_time})
    end

    if duration >= @max_session_time_s do
      if state.channel != nil do
        send(state.channel, :session_expired)
      end

      Logger.info("Session expired. Shutting down the room.")
      {:stop, {:shutdown, :session_expired}, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({_ref, predicitons}, state) do
    send(state.channel, {:img_reco, predicitons})
    state = %{state | task: nil}
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp handle_jitter_buffer_result({packets, timer, buffer}, state) do
    unless is_nil(timer), do: Process.send_after(self(), :jitter_buffer_timer, timer)

    state = Enum.reduce(packets, state, fn packet, state -> handle_packet(packet, state) end)

    {:noreply, %{state | video_buffer: buffer}}
  end

  defp handle_packet(packet, state) do
    {frame, depayloader} = Depayloader.depayload(state.video_depayloader, packet)
    state = %{state | video_depayloader: depayloader}

    with false <- is_nil(frame),
         # decoder needs to decode every frame, no matter we are going to process it or not
         {:ok, frame} <- Xav.Decoder.decode(state.video_decoder, frame),
         true <- is_nil(state.task) do
      tensor = Xav.Frame.to_nx(frame)
      task = Task.async(fn -> Nx.Serving.batched_run(Recognizer.VideoServing, tensor) end)
      %{state | task: task}
    else
      other when other in [:ok, true, false] ->
        state

      {:error, :no_keyframe} ->
        Logger.warning("Couldn't decode video frame - missing keyframe!")
        state
    end
  end
end
