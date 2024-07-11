defmodule RecognizerWeb.RoomChannel do
  @moduledoc false

  use Phoenix.Channel, restart: :temporary

  require Logger

  alias Recognizer.Room

  def join("room:" <> id, _message, socket) do
    id = String.to_integer(id)
    :ok = Room.connect(id, self())
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

  def handle_info({:session_time, session_time}, socket) do
    push(socket, "sessionTime", %{time: session_time})
    {:noreply, socket}
  end

  def handle_info(:session_expired, socket) do
    {:stop, {:shutdown, :session_expired}, socket}
  end

  def terminate(reason, _socket) do
    Logger.info("Stopping Phoenix chnannel, reason: #{inspect(reason)}.")
  end
end
