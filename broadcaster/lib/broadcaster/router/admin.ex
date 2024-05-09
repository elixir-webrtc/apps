defmodule Broadcaster.Router.Admin do
  use Plug.Router

  @admin_assets "priv/static/admin"

  plug(:authorize)
  plug(Plug.Static, at: "/", from: {:broadcaster, @admin_assets})
  plug(:match)
  plug(:dispatch)

  def authorize(conn, _opts) do
    username = Application.fetch_env!(:broadcaster, :admin_username)
    password = Application.fetch_env!(:broadcaster, :admin_password)
    creds = "#{username}:#{password}"

    with ["Basic " <> token] <- get_req_header(conn, "authorization"),
         true <- Base.decode64!(token) == creds do
      conn
    else
      _other ->
        conn
        |> put_resp_header("www-authenticate", ~S(Basic realm="insert realm"))
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end

  get "/stream" do
    path = String.trim_trailing(conn.request_path, "/") <> "/stream.html"

    conn
    |> put_resp_header("location", path)
    |> send_resp(302, "")
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
