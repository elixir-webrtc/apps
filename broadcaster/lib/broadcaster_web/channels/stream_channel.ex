defmodule BroadcasterWeb.StreamChannel do
  @moduledoc false

  use BroadcasterWeb, :channel

  alias BroadcasterWeb.Presence

  @impl true
  def join("stream:chat", _, socket) do
    send(self(), :after_join)
    {:ok, assign(socket, :nickname, nil)}
  end

  @impl true
  def join("stream:chat-admin", _, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("chat_msg", _, %{assigns: %{nickname: nil}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_in("chat_msg", %{"body" => body}, socket) do
    msg = %{
      body: body,
      nickname: socket.assigns.nickname,
      id: "#{socket.assigns.user_id}:#{socket.assigns.msg_count}"
    }

    broadcast!(socket, "chat_msg", msg)

    {:noreply, assign(socket, :msg_count, socket.assigns.msg_count + 1)}
  end

  @impl true
  def handle_in("join_chat", %{"nickname" => nickname}, socket) do
    case register(nickname) do
      :ok ->
        socket =
          socket
          |> assign(:nickname, nickname)
          |> assign(:msg_count, 0)

        :ok = push(socket, "join_chat_resp", %{"result" => "success"})
        {:noreply, socket}

      :error ->
        :ok = push(socket, "join_chat_resp", %{"result" => "error"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  defp register(nickname), do: do_register(String.trim(nickname))

  defp do_register(""), do: :error

  defp do_register(nickname) do
    case Registry.register(Broadcaster.ChatNicknamesRegistry, nickname, nil) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
