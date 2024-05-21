defmodule BroadcasterWeb.Router do
  use BroadcasterWeb, :router

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

    get "/player", PageController, :player
  end

  # Other scopes may use custom stacks.
  scope "/api", BroadcasterWeb do
    post "/whip", MediaController, :whip
    post "/whep", MediaController, :whep
    patch "/resource/:resource_id", MediaController, :ice_candidate
    delete "/resource/:resource_id", MediaController, :remove_pc
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:broadcaster, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BroadcasterWeb.Telemetry
    end
  end

  defp admin_auth(conn, _opts) do
    username = Application.fetch_env!(:broadcaster, :admin_username)
    password = Application.fetch_env!(:broadcaster, :admin_password)
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
