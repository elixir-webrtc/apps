defmodule Broadcaster.Router do
  use Plug.Router

  alias Broadcaster.{Forwarder, PeerSupervisor}

  plug(Plug.Logger)
  plug(Plug.Static, at: "/", from: :broadcaster)
  plug(:match)
  plug(:dispatch)

  get "/" do
    send_file(conn, 200, Application.app_dir(:broadcaster, "priv/static/index.html"))
  end

  post "/api/whip" do
    with :ok <- authenticate(conn),
         {:ok, offer_sdp, conn} <- get_sdp_from_body(conn),
         {:ok, pc, answer_sdp} <- PeerSupervisor.start_whip(offer_sdp),
         :ok <- Forwarder.connect_input(pc) do
      # TODO: handle location header and subsequent requests
      # TODO: use proper statuses in case of error
      conn
      |> put_resp_header("location", "/api/nothing")
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      {:error, _res} -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  post "/api/whep" do
    with {:ok, offer_sdp, conn} <- get_sdp_from_body(conn),
         {:ok, pc, answer_sdp} <- PeerSupervisor.start_whep(offer_sdp),
         :ok <- Forwarder.connect_output(pc) do
      conn
      |> put_resp_header("location", "/api/nothing")
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      {:error, _res} -> resp(conn, 400, "Bad request")
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

  defp get_sdp_from_body(conn) do
    with ["application/sdp"] <- get_req_header(conn, "content-type"),
         {:ok, offer_sdp, conn} <- read_body(conn) do
      {:ok, offer_sdp, conn}
    else
      _other -> {:error, :bad_request}
    end
  end
end
