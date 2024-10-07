defmodule BroadcasterWeb.Channel do
  @moduledoc false

  use BroadcasterWeb, :channel

  alias BroadcasterWeb.{Endpoint, Presence}

  @spec input_added(String.t()) :: :ok
  def input_added(id) do
    Endpoint.broadcast!("broadcaster:signaling", "input_added", %{id: id})
  end

  @spec input_removed(String.t()) :: :ok
  def input_removed(id) do
    Endpoint.broadcast!("broadcaster:signaling", "input_removed", %{id: id})
  end

  @max_nickname_length 25
  @max_message_length 500

  @impl true
  def join("broadcaster:signaling", _, socket) do
    msg = %{inputs: Broadcaster.Forwarder.input_ids()}
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
      id: "#{socket.assigns.user_id}:#{socket.assigns.msg_count}",
      admin: Map.get(socket.assigns, :admin)
    }

    Broadcaster.ChatHistory.put(msg)
    broadcast!(socket, "chat_msg", msg)

    {:noreply, assign(socket, :msg_count, socket.assigns.msg_count + 1)}
  end

  @impl true
  def handle_in("join_chat", payload, socket) do
    token = payload["token"]
    nickname = payload["nickname"]

    with {:token, true} <- {:token, validate_token(token)},
         {:register, true} <- {:register, register(nickname)} do
      socket =
        socket
        |> assign(:nickname, nickname)
        |> assign(:msg_count, 0)

      socket =
        if token != nil do
          assign(socket, :admin, true)
        else
          socket
        end

      :ok = push(socket, "join_chat_resp", %{"result" => "success"})
      {:noreply, socket}
    else
      {:token, false} ->
        :ok = push(socket, "join_chat_resp", %{"result" => "error", "reason" => "unauthorized"})
        {:noreply, socket}

      {:register, false} ->
        :ok = push(socket, "join_chat_resp", %{"result" => "error", "reason" => "name taken"})
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
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp validate_token(nil), do: true

  defp validate_token(token) do
    case Phoenix.Token.verify(BroadcasterWeb.Endpoint, "admin", token, max_age: 86_400) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
