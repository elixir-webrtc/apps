defmodule Reco.Room do
  use GenServer, restart: :temporary

  require Logger

  defp id(room_id), do: {:via, Registry, {Reco.RoomRegistry, room_id}}

  def start_link([room_id] = opts) do
    GenServer.start_link(__MODULE__, opts, name: id(room_id))
  end

  def stop(room_id) do
    GenServer.stop(id(room_id))
  end

  @impl true
  def init([room_id] = opts) do
    Logger.info("Starting room: #{room_id}")
    {:ok, %{}}
  end
end
