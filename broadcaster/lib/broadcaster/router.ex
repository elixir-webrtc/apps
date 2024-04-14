defmodule Broadcaster.Router do
  use Plug.Router

  alias ExWebRTC.PeerConnection
  alias Broadcaster.{Forwarder, PeerSupervisor}

  @viewers_count_update_interval 5000

  plug(Corsica, origins: "*")
  plug(Plug.Logger)
  plug(Plug.Static, at: "/", from: :broadcaster)
  plug(:match)
  plug(:dispatch)

  get "/" do
    send_file(conn, 200, Application.app_dir(:broadcaster, "priv/static/index.html"))
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
      |> put_resp_header(
        "link",
        """
        <#{host}/api/resource/#{pc_id}/sse>;\
        rel=\"urn:ietf:params:whep:ext:core:server-sent-events\";\
        events=\"viewercount\"\
        """
      )
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      {:error, _res} -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  post "/api/resource/:resource_id/sse" do
    if PeerSupervisor.pc_exists?(resource_id) do
      host = Application.fetch_env!(:broadcaster, :host)

      conn
      |> put_resp_header("location", "#{host}/api/resource/#{resource_id}/sse/event-stream")
      |> resp(201, "")
    else
      resp(conn, 404, "Resource not found")
    end
    |> send_resp()
  end

  get "/api/resource/:resource_id/sse/event-stream" do
    if PeerSupervisor.pc_exists?(resource_id) do
      Process.flag(:trap_exit, true)

      viewers = PeerConnection.get_all_running() |> length()

      {:ok, conn} =
        conn
        |> put_resp_header("content-type", "text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> send_chunked(200)
        |> chunk("data: {\"viewerscount\": #{viewers}}\n\n")

      update_viewers_count(conn, resource_id)
    else
      resp(conn, 404, "Resource not found")
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

  defp update_viewers_count(conn, pc_id) do
    viewers = PeerConnection.get_all_running() |> length()
    Process.send_after(self(), :update_viewerscount, @viewers_count_update_interval)

    receive do
      :update_viewerscount ->
        {:ok, conn} = chunk(conn, "data: {\"viewerscount\": #{viewers}}\n\n")
        update_viewers_count(conn, pc_id)

      {:EXIT, _from, _reason} ->
        :ok = PeerConnection.close(PeerSupervisor.pc_name(pc_id))
        Process.exit(self(), :normal)
    end
  end
end
