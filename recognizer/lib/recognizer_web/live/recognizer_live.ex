defmodule RecognizerWeb.RecognizerLive do
  use Phoenix.LiveView,
    container: {:div, class: "contents"},
    layout: {RecognizerWeb.Layouts, :app}

  def render(assigns) do
    ~H"""
    <button
      id="button"
      phx-click="start"
      class="mt-4 py-2 h-12 w-full text-xl rounded-xl text-gray-200 bg-brand/90 hover:bg-brand/100 focus:bg-violet-700"
    >
      Start
    </button>
    """
  end

  def mount(_params, _session, socket) do
    socket = assign(socket, :page_title, "Home")
    {:ok, socket}
  end

  def handle_event("start", _params, socket) do
    {:noreply, push_navigate(socket, to: "/lobby")}
  end
end
