defmodule Nexus.Room do
  @moduledoc false

  use GenServer

  require Logger

  alias Nexus.{Peer, PeerSupervisor}
  alias NexusWeb.PeerChannel

  @peer_ready_timeout_s 10

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec add_peer(pid()) :: {:ok, Peer.id()} | :error
  def add_peer(channel_pid) do
    GenServer.call(__MODULE__, {:add_peer, channel_pid})
  end

  @spec mark_ready(Peer.id(), pid(), map()) :: :ok | {:peer_mismatch, [Peer.id()]}
  def mark_ready(peer, pc, peer_track_specs) do
    GenServer.call(__MODULE__, {:mark_ready, peer, pc, peer_track_specs})
  end

  @spec broadcast_pli() :: :ok
  def broadcast_pli() do
    GenServer.cast(__MODULE__, :broadcast_pli)
  end

  @impl true
  def init(_opts) do
    state = %{
      peers: %{},
      pending_peers: %{},
      peer_pid_to_id: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_peer, channel_pid}, _from, state) do
    id = generate_id()
    Logger.info("New peer #{id} added")
    peer_ids = Map.keys(state.peers)

    {:ok, pid} = PeerSupervisor.add_peer(id, channel_pid, peer_ids)
    Process.monitor(pid)

    peer_data = %{pid: pid, channel: channel_pid}

    state =
      state
      |> put_in([:pending_peers, id], peer_data)
      |> put_in([:peer_pid_to_id, pid], id)

    Process.send_after(self(), {:peer_ready_timeout, id}, @peer_ready_timeout_s * 1000)

    {:reply, {:ok, id}, state}
  end

  @impl true
  def handle_call({:mark_ready, id, pc, peer_track_specs}, _from, state)
      when is_map_key(state.pending_peers, id) do
    # FIXME: this seems like a crude way of alleviating certain RCs
    current_peer_ids = Map.keys(state.peers)

    if current_peer_ids |> Enum.sort() != peer_track_specs |> Map.keys() |> Enum.sort() do
      {:reply, {:peer_mismatch, current_peer_ids}, state}
    else
      Logger.info("Peer #{id} ready")

      peer_track_specs
      |> Enum.each(fn {peer, track_specs} ->
        Peer.notify(peer, {:peer_added, id})
        Peer.notify(peer, {:subscribe, id, Map.put(track_specs, :pc, pc)})
      end)

      {peer_data, state} = pop_in(state, [:pending_peers, id])
      state = put_in(state, [:peers, id], peer_data)

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:mark_ready, peer, _pc, _obts}, _from, state) do
    Logger.debug("Peer #{peer} was already marked as ready, ignoring")

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:broadcast_pli, state) do
    state.peers
    |> Map.keys()
    |> Enum.each(&Peer.send_pli/1)

    {:noreply, state}
  end

  @impl true
  def handle_info({:peer_ready_timeout, peer}, state) do
    if is_map_key(state.pending_peers, peer) do
      Logger.warning(
        "Removing peer #{peer} which failed to mark itself as ready for #{@peer_ready_timeout_s} s"
      )

      :ok = PeerSupervisor.terminate_peer(peer)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    {id, state} = pop_in(state, [:peer_pid_to_id, pid])
    Logger.info("Peer #{id} down with reason #{inspect(reason)}")

    state =
      cond do
        is_map_key(state.pending_peers, id) ->
          {peer_data, state} = pop_in(state, [:pending_peers, id])
          :ok = PeerChannel.close(peer_data.channel)
          state

        is_map_key(state.peers, id) ->
          {peer_data, state} = pop_in(state, [:peers, id])
          :ok = PeerChannel.close(peer_data.channel)

          state.peers
          |> Map.keys()
          |> Enum.each(&Peer.notify(&1, {:peer_removed, id}))

          state
      end

    {:noreply, state}
  end

  defp generate_id, do: 5 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
