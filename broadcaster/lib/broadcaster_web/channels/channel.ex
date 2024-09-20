defmodule BroadcasterWeb.Channel do
  @moduledoc false

  use BroadcasterWeb, :channel

  alias BroadcasterWeb.{Endpoint, Presence}

  @spec stream_added(String.t()) :: :ok
  def stream_added(id) do
    Endpoint.broadcast!("broadcaster:signaling", "stream_added", %{id: id})
  end

  @spec stream_removed(String.t()) :: :ok
  def stream_removed(id) do
    Endpoint.broadcast!("broadcaster:signaling", "stream_removed", %{id: id})
  end

  @max_nickname_length 25
  @max_message_length 500

  @impl true
  def join("broadcaster:signaling", _, socket) do
    msg = %{streams: Broadcaster.Forwarder.streams()}
    {:ok, msg, socket}
  end

  @impl true
  def join("broadcaster:chat", _, socket) do
    send(self(), :after_join)
    {:ok, assign(socket, :nickname, nil)}
  end

  @impl true
  def handle_in("chat_msg", _, %{assigns: %{nickname: nil}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_in("chat_msg", %{"body" => body}, socket) do
    body = String.slice(body, 0..(@max_message_length - 1))

    msg = %{
      body: body,
      nickname: socket.assigns.nickname,
      id: "#{socket.assigns.user_id}:#{socket.assigns.msg_count}"
    }

    Broadcaster.ChatHistory.put(msg)
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

    Broadcaster.ChatHistory.get()
    |> Enum.each(fn msg -> :ok = push(socket, "chat_msg", msg) end)

    {:noreply, socket}
  end

  defp register(nickname) do
    if String.length(nickname) <= @max_nickname_length do
      nickname
      |> String.trim()
      |> do_register()
    else
      :error
    end
  end

  defp do_register(""), do: :error

  defp do_register(nickname) do
    case Registry.register(Broadcaster.ChatNicknamesRegistry, nickname, nil) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
