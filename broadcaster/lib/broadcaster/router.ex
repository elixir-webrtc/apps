defmodule Broadcaster.Router do
  use Plug.Router

  @public_assets "priv/static/public"

  plug(Plug.Logger)
  plug(Corsica, origins: "*")
  plug(Plug.Static, at: "/", from: {:broadcaster, @public_assets})
  plug(:match)
  plug(:dispatch)

  get "/" do
    redirect(conn, "index.html")
  end

  forward("/api", to: __MODULE__.Api)
  forward("/admin", to: __MODULE__.Admin)

  def redirect(conn, to) do
    host = Application.fetch_env!(:broadcaster, :host)
    path = host <> String.trim_trailing(conn.request_path, "/") <> "/" <> to

    conn
    |> put_resp_header("location", path)
    |> send_resp(302, "")
  end
end
