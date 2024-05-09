defmodule Broadcaster.Router do
  use Plug.Router

  @public_assets "priv/static/public"

  plug(Plug.Logger)
  plug(Corsica, origins: "*")
  plug(Plug.Static, at: "/", from: {:broadcaster, @public_assets})
  plug(:match)
  plug(:dispatch)

  get "/" do
    path = String.trim_trailing(conn.request_path, "/") <> "/index.html"

    conn
    |> put_resp_header("location", path)
    |> send_resp(302, "")
  end

  forward("/api", to: __MODULE__.Api)
  forward("/admin", to: __MODULE__.Admin)
end
