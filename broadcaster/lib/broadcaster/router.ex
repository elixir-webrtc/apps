defmodule Broadcaster.Router do
  use Plug.Router

  alias ExWebRTC.PeerConnection
  alias Broadcaster.{Forwarder, PeerSupervisor}

  plug(Corsica, origins: "*")
  plug(Plug.Logger)
  plug(Plug.Static, at: "/", from: :broadcaster)
  plug(Plug.Static, at: "/admin", from: :broadcaster)
  plug(:match)
  plug(:dispatch)

  get "/" do
    send_file(conn, 200, Application.app_dir(:broadcaster, "priv/static/index.html"))
  end

  get "/admin/stream" do
    case get_req_header(conn, "authorization") do
      [] ->
        conn
        |> put_resp_header("www-authenticate", "Basic realm=\"insert realm\"")
        |> resp(401, "Unauthorized")
        |> send_resp()

      ["Basic " <> token] ->
        username = Application.fetch_env!(:broadcaster, :admin_username)
        password = Application.fetch_env!(:broadcaster, :admin_password)
        # in basic auth, username and password are joined with ":"
        creds = username <> ":" <> password

        if creds == Base.decode64!(token) do
          send_file(
            conn,
            200,
            Application.app_dir(:broadcaster, "priv/static/stream/stream.html")
          )
        else
          conn
          |> resp(401, "Unauthorized")
          |> send_resp()
        end
    end
  end

  # TODO: not all of RFC's endpoints are implemented

  post "/api/whip" do
    with :ok <- authenticate(conn),
         {:ok, offer_sdp, conn} <- get_body(conn, "application/sdp"),
         {:ok, pc, pc_id, answer_sdp} <- PeerSupervisor.start_whip(offer_sdp),
         :ok <- Forwarder.connect_input(pc) do
      # TODO: use proper statuses in case of error
      conn
      |> put_resp_header("location", "/api/resource/#{pc_id}")
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      {:error, _res} -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  post "/api/whep" do
    with {:ok, offer_sdp, conn} <- get_body(conn, "application/sdp"),
         {:ok, pc, pc_id, answer_sdp} <- PeerSupervisor.start_whep(offer_sdp),
         :ok <- Forwarder.connect_output(pc) do
      host = Application.fetch_env!(:broadcaster, :host)

      conn
      |> put_resp_header("location", "#{host}/api/resource/#{pc_id}")
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      {:error, _res} -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  patch "/api/resource/:resource_id" do
    name = PeerSupervisor.pc_name(resource_id)

    case get_body(conn, "application/trickle-ice-sdpfrag") do
      {:ok, body, conn} ->
        # TODO: this is not implementaed as the RFC requires
        candidate =
          body
          |> Jason.decode!()
          |> ExWebRTC.ICECandidate.from_json()

        :ok = PeerConnection.add_ice_candidate(name, candidate)
        resp(conn, 204, "")

      {:error, _res} ->
        resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp authenticate(conn) do
    valid_token = Application.fetch_env!(:broadcaster, :token)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- token == valid_token do
      :ok
    else
      _other -> {:error, :unauthorized}
    end
  end

  defp get_body(conn, content_type) do
    with [^content_type] <- get_req_header(conn, "content-type"),
         {:ok, body, conn} <- read_body(conn) do
      {:ok, body, conn}
    else
      _other -> {:error, :bad_request}
    end
  end
end
