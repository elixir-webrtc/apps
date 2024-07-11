defmodule NexusWeb.Router do
  use NexusWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NexusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth do
    plug :admin_auth
  end

  scope "/", NexusWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/admin", NexusWeb do
    pipe_through :auth
    pipe_through :browser

    live_dashboard "/dashboard",
      metrics: NexusWeb.Telemetry,
      additional_pages: [exwebrtc: ExWebRTCDashboard]
  end

  defp admin_auth(conn, _opts) do
    username = Application.fetch_env!(:nexus, :admin_username)
    password = Application.fetch_env!(:nexus, :admin_password)
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
