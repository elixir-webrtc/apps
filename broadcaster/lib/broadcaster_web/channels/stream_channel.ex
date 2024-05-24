defmodule BroadcasterWeb.StreamChannel do
  use BroadcasterWeb, :channel

  alias BroadcasterWeb.Presence

  @impl true
  def join("stream:chat", %{"name" => name}, socket) do
    send(self(), :after_join)
    {:ok, assign(socket, :name, name)}
  end

  @impl true
  def handle_in("chat_msg", %{"body" => body}, socket) do
    broadcast!(socket, "chat_msg", %{body: body, name: socket.assigns.name})
    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end
end
