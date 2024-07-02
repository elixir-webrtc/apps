defmodule Broadcaster.Forwarder do
  use GenServer

  require Logger

  alias Broadcaster.PeerSupervisor
  alias ExWebRTC.PeerConnection

  alias ExWebRTC.RTP.Munger

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec set_layer(pid(), String.t()) :: :ok | :error
  def set_layer(pc, layer) do
    GenServer.call(__MODULE__, {:set_layer, pc, layer})
  end

  @spec connect_input(pid()) :: :ok
  def connect_input(pc) do
    GenServer.call(__MODULE__, {:connect_input, pc})
  end

  @spec connect_output(pid()) :: :ok
  def connect_output(pc) do
    GenServer.call(__MODULE__, {:connect_output, pc})
  end

  @impl true
  def init(_arg) do
    state = %{
      input_pc: nil,
      audio_input: nil,
      video_input: nil,
      pending_outputs: [],
      outputs: %{},
      mungers: %{},
      available_layers: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:set_layer, pc, layer}, _from, state) do
    with true <- layer in state.available_layers,
         {:ok, output} <- Map.fetch(state.outputs, pc) do
      munger = Munger.update(output.munger)
      output = %{output | munger: munger, layer: layer}
      state = %{state | outputs: Map.put(state.outputs, pc, output)}
      if state.input_pc != nil do
        :ok = PeerConnection.send_pli(state.input_pc, state.video_input, layer)
      end

      {:reply, :ok, state}
    else
      _other -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:connect_input, pc}, _from, state) do
    Process.monitor(pc)

    if state.input_pc != nil do
      PeerSupervisor.terminate_pc(state.input_pc)
    end

    PeerConnection.controlling_process(pc, self())
    {audio_track, video_track} = get_tracks(pc, :receiver)

    Logger.info("Successfully added input #{inspect(pc)}")

    state = %{
      state
      | input_pc: pc,
        audio_input: audio_track.id,
        video_input: video_track.id,
        available_layers: video_track.rids
    }

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:connect_output, pc}, _from, state) do
    Process.monitor(pc)

    PeerConnection.controlling_process(pc, self())
    pending_outputs = [pc | state.pending_outputs]

    Logger.info("Added new output #{inspect(pc)}")

    {:reply, :ok, %{state | pending_outputs: pending_outputs}}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, pc, {:connection_state_change, :connected}},
        %{input_pc: pc} = state
      ) do
    Logger.info("Input #{inspect(pc)} has successfully connected")
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state) do
    state =
      if Enum.member?(state.pending_outputs, pc) do
        pending_outputs = List.delete(state.pending_outputs, pc)
        {audio_track, video_track} = get_tracks(pc, :sender)

        munger = Munger.new(90_000)
        output = %{audio: audio_track.id, video: video_track.id, munger: munger, layer: "h"}
        outputs = Map.put(state.outputs, pc, output)

        if state.input_pc != nil do
          :ok = PeerConnection.send_pli(state.input_pc, state.video_input, "h")
        end

        Logger.info("Output #{inspect(pc)} has successfully connected")

        %{state | pending_outputs: pending_outputs, outputs: outputs}
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, input_pc, {:rtp, id, nil, packet}},
        %{input_pc: input_pc, audio_input: id} = state
      ) do
    for {pc, %{audio: track_id}} <- state.outputs do
      PeerConnection.send_rtp(pc, track_id, packet)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, input_pc, {:rtp, id, rid, packet}},
        %{input_pc: input_pc, video_input: id} = state
      ) do
    outputs =
      Map.new(state.outputs, fn
        {pc, output} when output.layer == rid ->
          {packet, munger} = Munger.munge(output.munger, packet)
          PeerConnection.send_rtp(pc, output.video, packet)
          {pc, %{output | munger: munger}}
        {pc, output} -> {pc, output}
      end)

    {:noreply, %{state | outputs: outputs}}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:rtcp, packets}}, state) do
    for packet <- packets do
      case packet do
        %ExRTCP.Packet.PayloadFeedback.PLI{} when state.input_pc != nil ->
          :ok = PeerConnection.send_pli(state.input_pc, state.video_input, "h")

        _other ->
          :ok
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{input_pc: pid} = state) do
    Logger.info("Input process: #{inspect(pid)} exited with reason: #{inspect(reason)}")
    state = %{state | input_pc: nil, audio_input: nil, video_input: nil}
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      Map.has_key?(state.outputs, pid) ->
        Logger.info("Output process: #{inspect(pid)} exited with reason: #{inspect(reason)}")
        {_, state} = pop_in(state, [:outputs, pid])
        {:noreply, state}

      pid in state.pending_outputs ->
        Logger.info("""
        Pending output process: #{inspect(pid)} exited with reason: #{inspect(reason)}\
        """)

        pending_outputs = List.delete(state.pending_outputs, pid)
        {:noreply, %{state | pending_outputs: pending_outputs}}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp get_tracks(pc, type) do
    transceivers = PeerConnection.get_transceivers(pc)
    audio_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :audio end)
    video_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :video end)

    audio_track = Map.fetch!(audio_transceiver, type).track
    video_track = Map.fetch!(video_transceiver, type).track

    {audio_track, video_track}
  end
end
