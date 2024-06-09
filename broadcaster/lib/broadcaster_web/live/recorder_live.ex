defmodule BroadcasterWeb.RecorderLive do
  use BroadcasterWeb, :live_view

  alias Broadcaster.{Forwarder, RecorderSupervisor}

  def render(assigns) do
    ~H"""
    <button
      phx-click="toggle_rec"
      class="rounded-lg font-semibold text-brand/80 bg-brand/10 px-2 py-1 hover:bg-brand/20"
    >
      <%= button_name(@rec_status) %>
    </button>
    """
  end

  def mount(_params, _session, socket) do
    rec_status = RecorderSupervisor.recorder_alive?()
    socket = assign(socket, :rec_status, rec_status)
    {:ok, socket}
  end

  def handle_event("toggle_rec", _params, %{assigns: %{rec_status: false}} = socket) do
    socket = assign(socket, :rec_status, true)
    {:ok, _pid} = RecorderSupervisor.start_recorder()
    :ok = Forwarder.connect_recorder()
    {:noreply, socket}
  end

  def handle_event("toggle_rec", _params, %{assigns: %{rec_status: true}} = socket) do
    socket = assign(socket, :rec_status, false)
    :ok = RecorderSupervisor.terminate_recorder({:shutdown, :client_request})
    false = RecorderSupervisor.recorder_alive?()
    :ok = Forwarder.disconnect_recorder()
    {:noreply, socket}
  end

  # TODO is this ok to call a function inside heex?
  defp button_name(false), do: "Start recording"
  defp button_name(true), do: "Stop recording"
end
