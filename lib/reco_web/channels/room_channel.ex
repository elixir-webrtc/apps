defmodule RecoWeb.RoomChannel do
  use Phoenix.Channel

  require Logger

  alias Reco.Room

  def join("room:" <> id, _message, socket) do
    {:ok, _pid} = DynamicSupervisor.start_child(Reco.RoomSupervisor, {Room, [id]})
    {:ok, assign(socket, :room_id, id)}
  end

  def handle_in(x, y, socket) do
    dbg(x)
    dbg(y)
    {:noreply, socket}
  end

  def terminate(reason, socket) do
    Logger.info("Stopping Phoenix chnannel, reason: #{inspect(reason)}.")
    Room.stop(socket.assigns.room_id)
  end
end
