defmodule Reco.Lobby do
  use GenServer

  require Logger

  alias Reco.Room

  def start_link(max_rooms) do
    GenServer.start_link(__MODULE__, max_rooms, name: __MODULE__)
  end

  def get_room() do
    GenServer.call(__MODULE__, :get_room)
  end

  @impl true
  def init(max_rooms) do
    {:ok, %{queue: :queue.new(), rooms: MapSet.new(), max_rooms: max_rooms}}
  end

  @impl true
  def handle_call(:get_room, {from, _tag}, state) do
    _ref = Process.monitor(from)

    if MapSet.size(state.rooms) >= state.max_rooms do
      queue = :queue.in(from, state.queue)
      state = %{state | queue: queue}
      position = :queue.len(queue)
      {:reply, {:error, :max_rooms, position}, state}
    else
      {id, state} = create_room(state)
      {:reply, {:ok, id}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    cond do
      MapSet.member?(state.rooms, pid) ->
        rooms = MapSet.delete(state.rooms, pid)
        state = %{state | rooms: rooms}

        case :queue.out(state.queue) do
          {{:value, pid}, queue} ->
            state = %{state | queue: queue}
            {id, state} = create_room(state)
            send(pid, {:room, id})
            send_positions(state)
            {:noreply, state}

          {:empty, queue} ->
            state = %{state | queue: queue}
            {:noreply, state}
        end

      :queue.member(pid, state.queue) == true ->
        queue = :queue.delete(pid, state.queue)
        state = %{state | queue: queue}
        send_positions(state)
        {:noreply, state}

      true ->
        Logger.warning("Unexpected DOWN message from pid: #{inspect(pid)}")
        {:noreply, state}
    end
  end

  defp create_room(state) do
    Logger.info("Creating a new room")
    <<id::12*8>> = :crypto.strong_rand_bytes(12)
    {:ok, pid} = DynamicSupervisor.start_child(Reco.RoomSupervisor, {Room, id})
    Process.monitor(pid)
    rooms = MapSet.put(state.rooms, pid)
    state = %{state | rooms: rooms}
    {id, state}
  end

  defp send_positions(state) do
    :queue.to_list(state.queue)
    |> Stream.with_index()
    |> Enum.each(fn {pid, idx} -> send(pid, {:position, idx + 1}) end)
  end
end
