defmodule RecoWeb.RoomChannel do
  use Phoenix.Channel

  require Logger

  alias Reco.Room

  def join("room:" <> id, _message, socket) do
    {:ok, _pid} = DynamicSupervisor.start_child(Reco.RoomSupervisor, {Room, [id, self()]})
    {:ok, assign(socket, :room_id, id)}
  end

  def handle_in("signaling", msg, socket) do
    :ok = Room.receive_signaling_msg(socket.assigns.room_id, msg)
    {:noreply, socket}
  end

  def handle_info({:signaling, msg}, socket) do
    push(socket, "signaling", msg)
    {:noreply, socket}
  end

  def handle_info({:img_reco, msg}, socket) do
    push(socket, "imgReco", msg)
    {:noreply, socket}
  end

  def terminate(reason, socket) do
    Logger.info("Stopping Phoenix chnannel, reason: #{inspect(reason)}.")
    Room.stop(socket.assigns.room_id)
  end
end
