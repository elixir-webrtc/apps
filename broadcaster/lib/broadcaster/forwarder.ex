defmodule Broadcaster.Forwarder do
  @moduledoc false

  use GenServer

  require Logger

  alias Phoenix.PubSub

  alias ExWebRTC.PeerConnection
  alias ExWebRTC.RTP.H264
  alias ExWebRTC.RTP.Munger

  alias Broadcaster.PeerSupervisor
  alias BroadcasterWeb.Channel

  @pubsub Broadcaster.PubSub
  # Timeout for removing inputs/outputs that fail to connect
  @connect_timeout_s 15
  @connect_timeout_ms @connect_timeout_s * 1000

  @type id :: String.t()

  @type input_spec :: %{
          pc: pid(),
          id: id(),
          video: String.t() | nil,
          audio: String.t() | nil,
          available_layers: [String.t()] | nil
        }

  @type output_spec :: %{
          input_id: id(),
          video: String.t() | nil,
          audio: String.t() | nil,
          munger: Munger.t(),
          layer: String.t() | nil,
          pending_layer: String.t() | nil
        }

  @type state :: %{
          # WHIP
          pending_inputs: %{pid() => id()},
          local_inputs: %{pid() => input_spec()},
          remote_inputs: %{pid() => input_spec()},

          # WHEP
          # Each output corresponds to one input with given ID
          pending_outputs: %{pid() => input_id :: id()},
          outputs: %{pid() => output_spec()}
        }

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

  @spec connect_input(pid(), id()) :: :ok
  def connect_input(pc, id) do
    GenServer.call(__MODULE__, {:connect_input, id, pc})
  end

  @spec connect_output(pid(), id()) :: :ok
  def connect_output(pc, input_id) do
    GenServer.call(__MODULE__, {:connect_output, input_id, pc})
  end

  @spec input_ids() :: [id()]
  def input_ids() do
    GenServer.call(__MODULE__, :input_ids)
  end

  @spec local_inputs() :: [input_spec()]
  def local_inputs() do
    GenServer.call(__MODULE__, :local_inputs)
  end

  @impl true
  def init(_arg) do
    state = %{
      pending_inputs: %{},
      local_inputs: %{},
      remote_inputs: %{},
      pending_outputs: %{},
      outputs: %{}
    }

    {:ok, state, {:continue, :after_init}}
  end

  @impl true
  def handle_continue(:after_init, state) do
    # Get remote inputs already present in cluster
    Node.list()
    |> :erpc.multicall(__MODULE__, :local_inputs, [], 5000)
    |> Enum.each(fn
      {:ok, inputs} ->
        Enum.each(inputs, &send(self(), {:input_added, &1}))

      _err ->
        :ok
    end)

    PubSub.subscribe(@pubsub, "inputs")

    {:noreply, state}
  end

  @impl true
  def handle_call(:input_ids, _from, state) do
    local_ids = Enum.map(state.local_inputs, fn {_pc, input} -> input.id end)
    remote_ids = Enum.map(state.remote_inputs, fn {_pc, input} -> input.id end)

    {:reply, local_ids ++ remote_ids, state}
  end

  @impl true
  def handle_call(:local_inputs, _from, state) do
    {:reply, Map.values(state.local_inputs), state}
  end

  @impl true
  def handle_call({:set_layer, pc, layer}, _from, state) do
    with {:ok, %{input_id: input_id} = output} <- Map.fetch(state.outputs, pc),
         {:ok, input} <- find_input(input_id, state),
         true <- input.available_layers != nil,
         true <- layer in input.available_layers do
      output = %{output | pending_layer: layer}
      state = %{state | outputs: Map.put(state.outputs, pc, output)}

      PeerConnection.send_pli(input.pc, input.video, layer)

      {:reply, :ok, state}
    else
      _other -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:get_layers, pc}, _from, state) do
    with {:ok, %{input_id: input_id}} <- Map.fetch(state.outputs, pc),
         {:ok, input} <- find_input(input_id, state) do
      {:reply, {:ok, input.available_layers}, state}
    else
      _other -> {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:connect_input, id, pc}, _from, state) do
    Process.monitor(pc)

    PeerConnection.controlling_process(pc, self())
    pending_inputs = Map.put(state.pending_inputs, pc, id)

    Logger.info("Added new input #{id} (#{inspect(pc)})")
    Process.send_after(self(), {:connect_timeout, pc}, @connect_timeout_ms)

    {:reply, :ok, %{state | pending_inputs: pending_inputs}}
  end

  @impl true
  def handle_call({:connect_output, id, pc}, _from, state) do
    Process.monitor(pc)

    PeerConnection.controlling_process(pc, self())
    pending_outputs = Map.put(state.pending_outputs, pc, id)

    Logger.info("Added new output #{inspect(pc)} for input #{inspect(id)}")
    Process.send_after(self(), {:connect_timeout, pc}, @connect_timeout_ms)

    {:reply, :ok, %{state | pending_outputs: pending_outputs}}
  end

  @impl true
  def handle_info({:connect_timeout, pc}, state) do
    direction =
      cond do
        Map.has_key?(state.pending_inputs, pc) -> :input
        Map.has_key?(state.pending_outputs, pc) -> :output
        true -> nil
      end

    unless is_nil(direction) do
      Logger.warning("""
      Terminating #{direction} #{inspect(pc)} \
      because it didn't connect within #{@connect_timeout_s} seconds \
      """)

      PeerSupervisor.terminate_pc(pc)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state)
      when is_map_key(state.pending_inputs, pc) do
    {id, state} = pop_in(state, [:pending_inputs, pc])

    {audio_track, video_track} = get_tracks(pc, :receiver)

    input = %{
      pc: pc,
      id: id,
      video: video_track.id,
      audio: audio_track.id,
      available_layers: video_track.rids
    }

    state = put_in(state, [:local_inputs, pc], input)

    Logger.info("Input #{id} (#{inspect(pc)}) has successfully connected")
    Channel.input_added(id)

    # ID collisions in the cluster are unlikely and thus will not be checked against
    PubSub.broadcast_from(@pubsub, self(), "inputs", {:input_added, input})

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, state)
      when is_map_key(state.pending_outputs, pc) do
    {input_id, state} = pop_in(state, [:pending_outputs, pc])

    # Fill default ID
    input_id = input_id || state.local_inputs |> Map.values() |> List.first() |> then(& &1[:id])

    state =
      case find_input(input_id, state) do
        {:ok, input} ->
          do_connect_output(pc, input, state)

        {:error, :not_found} ->
          Logger.info(
            "Terminating output #{inspect(pc)} because input #{inspect(input_id)} doesn't exist"
          )

          PeerSupervisor.terminate_pc(pc)

          # Re-add to pending outputs, so that `:DOWN` gets handled properly
          put_in(state, [:pending_outputs, pc], input_id)
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :failed}}, state) do
    Logger.warning("Peer connection #{inspect(pc)} state changed to `failed`. Terminating")
    PeerSupervisor.terminate_pc(pc)
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, input_pc, {:rtp, input_track, rid, packet}}, state)
      when is_map_key(state.local_inputs, input_pc) do
    input = Map.get(state.local_inputs, input_pc)

    state =
      cond do
        input_track == input.audio and rid == nil ->
          PubSub.broadcast(@pubsub, "input:#{input.id}", {:input, input_pc, :audio, nil, packet})
          forward_audio_packet(packet, input.id, state)

        input_track == input.video ->
          PubSub.broadcast(@pubsub, "input:#{input.id}", {:input, input_pc, :video, rid, packet})
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
         {:ok, input} <- find_input(input_id, state) do
      for packet <- packets do
        case packet do
          {_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} ->
            PeerConnection.send_pli(input.pc, input.video, layer)

          _other ->
            :ok
        end
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:input_added, %{pc: pc} = input}, state)
      when not is_map_key(state.remote_inputs, pc) do
    Logger.info("Remote input #{input.id} (#{inspect(pc)}) added")
    PubSub.subscribe(@pubsub, "input:#{input.id}")

    state = put_in(state, [:remote_inputs, pc], input)
    {:noreply, state}
  end

  @impl true
  def handle_info({:input_removed, pc}, state)
      when is_map_key(state.remote_inputs, pc) do
    {input, state} = pop_in(state, [:remote_inputs, pc])
    Logger.info("Remote input #{input.id} (#{inspect(pc)}) removed")
    PubSub.unsubscribe(@pubsub, "input:#{input.id}")

    for {output_pc, %{input_id: input_id}} <- state.outputs do
      if input_id == input.id, do: PeerSupervisor.terminate_pc(output_pc)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({topic, _data} = msg, state) when topic in [:input_added, :input_removed] do
    Logger.warning("""
    Unexpected message: #{inspect(msg)}. \
    Cluster state may be inconsistent. \
    Known remote inputs: #{inspect(state.remote_inputs)}
    """)

    {:noreply, state}
  end

  @impl true
  def handle_info({:input, pc, kind, rid, packet}, state)
      when is_map_key(state.remote_inputs, pc) do
    id = get_in(state.remote_inputs, [pc, :id])

    state =
      cond do
        kind == :audio and rid == nil ->
          forward_audio_packet(packet, id, state)

        kind == :video ->
          forward_video_packet(packet, id, rid, state)

        true ->
          Logger.warning("Received an RTP packet corresponding to unknown remote track. Ignoring")
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state)
      when is_map_key(state.local_inputs, pid) do
    {input, state} = pop_in(state, [:local_inputs, pid])

    Logger.info(
      "Input #{input.id}: process #{inspect(pid)} exited with reason #{inspect(reason)}"
    )

    for {pc, %{input_id: input_id}} <- state.outputs do
      if input_id == input.id, do: PeerSupervisor.terminate_pc(pc)
    end

    Channel.input_removed(input.id)
    PubSub.broadcast_from(@pubsub, self(), "inputs", {:input_removed, pid})

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      Map.has_key?(state.pending_inputs, pid) ->
        {id, state} = pop_in(state, [:pending_inputs, pid])

        Logger.info("""
        Pending input #{id}: process #{inspect(pid)} \
        exited with reason #{inspect(reason)} \
        """)

        {:noreply, state}

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

  defp forward_audio_packet(packet, input_id, state) do
    for {pc, output} <- state.outputs do
      if output.input_id == input_id, do: PeerConnection.send_rtp(pc, output.audio, packet)
    end

    state
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

  defp find_input(id, %{local_inputs: local_inputs, remote_inputs: remote_inputs}) do
    with nil <- Enum.find(local_inputs, fn {_pc, input} -> input.id == id end),
         nil <- Enum.find(remote_inputs, fn {_pc, input} -> input.id == id end) do
      {:error, :not_found}
    else
      {_pc, input} -> {:ok, input}
    end
  end
end
