defmodule RecoWeb.LobbyLive do
  use Phoenix.LiveView,
    container: {:div, class: "contents"},
    layout: {RecoWeb.Layouts, :app}

  alias Reco.Lobby

  @session_time 200
  @eta_update_interval_ms 1000

  def render(assigns) do
    ~H"""
    <section>
      <div>
        <p class="text-justify text-xl font-semibold text-black-400">
          Whoops! <br /><br /> Looks like our servers are experiencing pretty high load!
          We put you in the queue and will redirect you once it's your turn. <br /><br />
          You are <%= @position %> in the queue.
          ETA: <%= @eta %> seconds.
        </p>
      </div>
    </section>
    """
  end

  def mount(_params, _session, socket) do
    case Lobby.get_room() do
      {:ok, room_id} ->
        {:ok, push_navigate(socket, to: "/room/#{room_id}")}

      {:error, :max_rooms, position} ->
        Process.send_after(self(), :update_eta, @eta_update_interval_ms)
        socket = assign(socket, position: position)
        socket = assign(socket, eta: position * @session_time)
        socket = assign(socket, last_check: System.monotonic_time(:millisecond))
        {:ok, socket}
    end
  end

  def handle_info({:position, position}, socket) do
    socket = assign(socket, position: position)
    socket = assign(socket, eta: position * @session_time)
    {:noreply, socket}
  end

  def handle_info({:room, room_id}, socket) do
    {:noreply, push_navigate(socket, to: "/room/#{room_id}")}
  end

  def handle_info(:update_eta, socket) do
    Process.send_after(self(), :update_eta, @eta_update_interval_ms)
    now = System.monotonic_time(:millisecond)
    elapsed = floor((now - socket.assigns.last_check) / 1000)
    eta = max(0, socket.assigns.eta - elapsed)
    socket = assign(socket, eta: eta)
    socket = assign(socket, last_check: now)
    {:noreply, socket}
  end
end
