defmodule Broadcaster.Forwarder do
  @moduledoc false

  use GenServer

  require Logger

  alias ExWebRTC.PeerConnection
  alias ExWebRTC.RTP.H264
  alias ExWebRTC.RTP.Munger

  alias Broadcaster.PeerSupervisor
  alias BroadcasterWeb.StreamChannel

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @spec set_layer(pid(), String.t()) :: :ok | :error
  def set_layer(pc, layer) do
    GenServer.call(__MODULE__, {:set_layer, pc, layer})
  end

  @spec get_layers(pid()) :: {:ok, [String.t()] | nil} | :error
  def get_layers(pc) do
    GenServer.call(__MODULE__, {:get_layers, pc})
  end

  @spec connect_input(pid(), String.t()) :: :ok
  def connect_input(pc, id) do
    GenServer.call(__MODULE__, {:connect_input, id, pc})
  end

  @spec connect_output(pid(), String.t()) :: :ok
  def connect_output(pc, stream_id) do
    GenServer.call(__MODULE__, {:connect_output, stream_id, pc})
  end

  @spec streams() :: [String.t()]
  def streams() do
    GenServer.call(__MODULE__, :streams)
  end

  @impl true
  def init(_arg) do
    state = %{
      inputs: %{},
      pending_outputs: %{},
      outputs: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:streams, _from, state) do
    {:reply, Enum.map(state.inputs, fn {_pc, input} -> input.id end), state}
  end

  @impl true
  def handle_call({:set_layer, pc, layer}, _from, state) do
    with {:ok, %{input_id: input_id} = output} <- Map.fetch(state.outputs, pc),
         {:ok, input_pc, input} <- find_input(input_id, state),
         true <- input.available_layers != nil,
         true <- layer in input.available_layers do
      output = %{output | pending_layer: layer}
      state = %{state | outputs: Map.put(state.outputs, pc, output)}

      :ok = PeerConnection.send_pli(input_pc, input.video, layer)

      {:reply, :ok, state}
    else
      _other -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:get_layers, pc}, _from, state) do
    with {:ok, %{input_id: input_id}} <- Map.fetch(state.outputs, pc),
         {:ok, _pc, input} <- find_input(input_id, state) do
      {:reply, {:ok, input.available_layers}, state}
    else
      _other -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:connect_input, id, pc}, _from, state) do
    Process.monitor(pc)

    PeerConnection.controlling_process(pc, self())
    {audio_track, video_track} = get_tracks(pc, :receiver)

    Logger.info("Added new input #{id} (#{inspect(pc)})")

    input = %{
      id: id,
      video: video_track.id,
      audio: audio_track.id,
      available_layers: video_track.rids
    }

    state = put_in(state, [:inputs, pc], input)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:connect_output, id, pc}, _from, state) do
    Process.monitor(pc)

    PeerConnection.controlling_process(pc, self())
    pending_outputs = Map.put(state.pending_outputs, pc, id)

    Logger.info("Added new output #{inspect(pc)} for input #{inspect(id)}")

    {:reply, :ok, %{state | pending_outputs: pending_outputs}}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state)
      when is_map_key(state.inputs, pc) do
    id = get_in(state, [:inputs, pc, :id])
    Logger.info("Input #{id} (#{inspect(pc)}) has successfully connected")

    StreamChannel.stream_added(id)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state)
      when is_map_key(state.pending_outputs, pc) do
    {input_id, state} = pop_in(state, [:pending_outputs, pc])

    # Fill default ID
    input_id = input_id || state.inputs |> Map.values() |> List.first() |> then(& &1[:id])

    state =
      case find_input(input_id, state) do
        {:ok, _input_pc, input} ->
          do_connect_output(pc, input, state)

        {:error, :not_found} ->
          Logger.info(
            "Terminating output #{inspect(pc)} because input #{inspect(input_id)} doesn't exist"
          )

          PeerSupervisor.terminate_pc(pc)

          put_in(state, [:pending_outputs, pc], input_id)
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, input_pc, {:rtp, input_track, rid, packet}}, state)
      when is_map_key(state.inputs, input_pc) do
    input = Map.get(state.inputs, input_pc)

    state =
      cond do
        input_track == input.audio and rid == nil ->
          for {pc, output} <- state.outputs do
            if output.input_id == input.id, do: PeerConnection.send_rtp(pc, output.audio, packet)
          end

          state

        input_track == input.video ->
          forward_video_packet(packet, input.id, rid, state)

        true ->
          Logger.warning("Received an RTP packet corresponding to unknown track. Ignoring")
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:rtcp, packets}}, state) do
    with {:ok, %{input_id: input_id, layer: layer}} <- Map.fetch(state.outputs, pc),
         {:ok, input_pc, input} <- find_input(input_id, state) do
      for packet <- packets do
        case packet do
          {_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} ->
            :ok = PeerConnection.send_pli(input_pc, input.video, layer)

          _other ->
            :ok
        end
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state)
      when is_map_key(state.inputs, pid) do
    {input, state} = pop_in(state, [:inputs, pid])

    Logger.info(
      "Input #{input.id}: process #{inspect(pid)} exited with reason: #{inspect(reason)}"
    )

    for {pc, %{input_id: input_id}} <- state.outputs do
      if input_id == input.id, do: PeerSupervisor.terminate_pc(pc)
    end

    StreamChannel.stream_removed(input.id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      Map.has_key?(state.outputs, pid) ->
        {output, state} = pop_in(state, [:outputs, pid])

        Logger.info("""
        Output process #{inspect(pid)} (input #{output.input_id}) \
        exited with reason #{inspect(reason)} \
        """)

        {:noreply, state}

      Map.has_key?(state.pending_outputs, pid) ->
        {input_id, state} = pop_in(state, [:pending_outputs, pid])

        Logger.info("""
        Pending output process #{inspect(pid)} (input #{input_id}) \
        exited with reason #{inspect(reason)} \
        """)

        {:noreply, state}

      true ->
        Logger.warning("Unknown process #{inspect(pid)} died with reason #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp do_connect_output(pc, input, state) do
    layer = default_layer(input)

    {audio_track, video_track} = get_tracks(pc, :sender)
    munger = Munger.new(90_000)

    output = %{
      audio: audio_track.id,
      video: video_track.id,
      input_id: input.id,
      munger: munger,
      layer: layer,
      pending_layer: layer
    }

    Logger.info("Output #{inspect(pc)} has successfully connected to input #{input.id}")

    # We don't send a PLI on behalf of the newly connected output.
    # Once the output sends a PLI to us, we'll forward it.

    put_in(state, [:outputs, pc], output)
  end

  defp forward_video_packet(packet, input_id, rid, state) do
    outputs =
      Map.new(state.outputs, fn
        {pc, %{input_id: ^input_id, layer: layer, pending_layer: p_layer} = output} ->
          output =
            if p_layer == rid and p_layer != layer and H264.keyframe?(packet) do
              munger = Munger.update(output.munger)
              %{output | layer: p_layer, munger: munger}
            else
              output
            end

          output =
            if rid == output.layer do
              {packet, munger} = Munger.munge(output.munger, packet)
              PeerConnection.send_rtp(pc, output.video, packet)
              %{output | munger: munger}
            else
              output
            end

          {pc, output}

        {pc, output} ->
          {pc, output}
      end)

    %{state | outputs: outputs}
  end

  defp get_tracks(pc, type) do
    transceivers = PeerConnection.get_transceivers(pc)
    audio_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :audio end)
    video_transceiver = Enum.find(transceivers, fn tr -> tr.kind == :video end)

    audio_track = Map.fetch!(audio_transceiver, type).track
    video_track = Map.fetch!(video_transceiver, type).track

    {audio_track, video_track}
  end

  defp default_layer(%{available_layers: nil}), do: nil
  defp default_layer(%{available_layers: [first | _]}), do: first

  defp find_input(id, %{inputs: inputs}) do
    case Enum.find(inputs, fn {_pc, input} -> input.id == id end) do
      {input_pc, input} -> {:ok, input_pc, input}
      nil -> {:error, :not_found}
    end
  end
end
