defmodule NexusWeb.PeerChannel do
  @moduledoc false

  use NexusWeb, :channel

  require Logger

  alias Nexus.{Peer, Room}
  alias NexusWeb.Presence

  @spec send_offer(GenServer.server(), String.t()) :: :ok
  def send_offer(channel, offer) do
    GenServer.cast(channel, {:offer, offer})
  end

  @spec send_candidate(GenServer.server(), String.t()) :: :ok
  def send_candidate(channel, candidate) do
    GenServer.cast(channel, {:candidate, candidate})
  end

  @spec close(GenServer.server()) :: :ok
  def close(channel) do
    try do
      GenServer.stop(channel, :shutdown)
    catch
      _exit_or_error, _e -> :ok
    end

    :ok
  end

  @impl true
  def join("peer:signalling", _payload, socket) do
    pid = self()
    send(pid, :after_join)

    case Room.add_peer(pid) do
      {:ok, id} -> {:ok, assign(socket, :peer, id)}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def handle_in("sdp_answer", %{"body" => body}, socket) do
    :ok = Peer.apply_sdp_answer(socket.assigns.peer, body)
    {:noreply, socket}
  end

  @impl true
  def handle_in("sdp_offer", %{"body" => _body}, socket) do
    # TODO: renegotiate
    Logger.warning("Ignoring SDP offer sent by peer #{socket.assigns.peer}")
    {:noreply, socket}
  end

  @impl true
  def handle_in("ice_candidate", %{"body" => body}, socket) do
    Peer.add_ice_candidate(socket.assigns.peer, body)
    {:noreply, socket}
  end

  @impl true
  def handle_cast({:offer, sdp_offer}, socket) do
    push(socket, "sdp_offer", %{"body" => sdp_offer})
    {:noreply, socket}
  end

  @impl true
  def handle_cast({:candidate, candidate}, socket) do
    push(socket, "ice_candidate", %{"body" => candidate})
    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} = Presence.track(socket, socket.assigns.peer, %{})
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end
end
