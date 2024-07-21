defmodule RecognizerWeb.Router do
  use RecognizerWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RecognizerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth do
    plug :admin_auth
  end

  scope "/", RecognizerWeb do
    pipe_through :browser

    live "/", RecognizerLive
    live "/lobby", LobbyLive
    get "/room/:room_id", RoomController, :room
  end

  scope "/admin", RecognizerWeb do
    pipe_through :auth
    pipe_through :browser

    live_dashboard "/dashboard",
      metrics: RecognizerWeb.Telemetry,
      additional_pages: [exwebrtc: ExWebRTCDashboard]
  end

  defp admin_auth(conn, _opts) do
    username = Application.fetch_env!(:recognizer, :admin_username)
    password = Application.fetch_env!(:recognizer, :admin_password)
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
