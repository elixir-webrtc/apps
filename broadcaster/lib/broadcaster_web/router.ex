defmodule BroadcasterWeb.Router do
  use BroadcasterWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BroadcasterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth do
    plug :admin_auth
  end

  scope "/", BroadcasterWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/admin", BroadcasterWeb do
    pipe_through :auth
    pipe_through :browser

    get "/panel", PageController, :panel

    live_dashboard "/dashboard",
      metrics: BroadcasterWeb.Telemetry,
      additional_pages: [exwebrtc: ExWebRTCDashboard]
  end

  scope "/api", BroadcasterWeb do
    post "/whip", MediaController, :whip
    post "/whep", MediaController, :whep

    scope "/resource/:resource_id" do
      patch "/", MediaController, :ice_candidate
      delete "/", MediaController, :remove_pc
      get "/sse/event-stream", MediaController, :event_stream
      post "/sse", MediaController, :sse
      post "/layer", MediaController, :layer
    end

    scope "/admin" do
      pipe_through :auth

      delete "/chat/:id", PageController, :delete_chat_message
    end
  end

  defp admin_auth(conn, _opts) do
    username = Application.fetch_env!(:broadcaster, :admin_username)
    password = Application.fetch_env!(:broadcaster, :admin_password)
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
