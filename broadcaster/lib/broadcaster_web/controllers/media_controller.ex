defmodule BroadcasterWeb.MediaController do
  use BroadcasterWeb, :controller

  alias Broadcaster.{Forwarder, PeerSupervisor}
  alias ExWebRTC.PeerConnection

  @sse ~s/rel = "urn:ietf:params:whep:ext:core:server-sent-events"; events="layers"/
  @layer ~s/rel = "urn:ietf:params:whep:ext:core:layer"/

  plug :accepts, ["sdp"] when action in [:whip, :whep]
  plug :accepts, ["trickle-ice-sdpfrag"] when action in [:ice_candidate]

  # TODO: use proper statuses in case of error
  def whip(conn, _params) do
    with :ok <- authenticate(conn),
         {:ok, offer_sdp, conn} <- read_body(conn),
         {:ok, pc, pc_id, answer_sdp} <- PeerSupervisor.start_whip(offer_sdp),
         :ok <- Forwarder.connect_input(pc, pc_id) do
      conn
      |> put_resp_header("location", ~p"/api/resource/#{pc_id}")
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      _other -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  def whep(conn, params) do
    stream_id = params["streamId"] || "default"

    with {:ok, offer_sdp, conn} <- read_body(conn),
         {:ok, pc, pc_id, answer_sdp} <- PeerSupervisor.start_whep(offer_sdp, stream_id),
         :ok <- Forwarder.connect_output(pc, stream_id) do
      uri = ~p"/api/resource/#{pc_id}"

      conn
      |> put_resp_header("location", uri)
      # Plug does not allow adding multiple headers with the same name
      |> put_resp_header("link", "<#{uri}/layer>; " <> @layer)
      |> put_resp_header("link", "<#{uri}/sse>; " <> @sse)
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      _other -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  def ice_candidate(conn, %{"resource_id" => resource_id}) do
    with {:ok, pid} <- PeerSupervisor.fetch_pid(resource_id),
         {:ok, body, conn} <- read_body(conn),
         {:ok, json} <- Jason.decode(body) do
      candidate = ExWebRTC.ICECandidate.from_json(json)
      :ok = PeerConnection.add_ice_candidate(pid, candidate)
      resp(conn, 204, "")
    else
      _other -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  def sse(conn, %{"resource_id" => resource_id}) do
    with {:ok, _pid} <- PeerSupervisor.fetch_pid(resource_id),
         {:ok, events} when is_list(events) <- Map.fetch(conn.body_params, "_json") do
      # for now, we just ignore events
      conn
      |> put_resp_header("location", ~p"/api/resource/#{resource_id}/sse/event-stream")
      |> resp(201, "")
    else
      _other -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  def event_stream(conn, %{"resource_id" => resource_id}) do
    with {:ok, _pid} <- PeerSupervisor.fetch_pid(resource_id),
         [stream_id, _pc_id] <- String.split(resource_id, "-") do
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)
      |> update_layers(stream_id)
    else
      _other ->
        send_resp(conn, 400, "Bad request")
    end
  end

  def layer(conn, %{"resource_id" => resource_id}) do
    with {:ok, pid} <- PeerSupervisor.fetch_pid(resource_id),
         :ok <- Forwarder.set_layer(pid, conn.body_params["encodingId"]) do
      resp(conn, 200, "")
    else
      _other ->
        resp(conn, 400, "Bad reqeust")
    end
    |> send_resp()
  end

  def remove_pc(conn, %{"resource_id" => resource_id}) do
    case PeerSupervisor.fetch_pid(resource_id) do
      {:ok, pid} ->
        PeerSupervisor.terminate_pc(pid)
        resp(conn, 200, "")

      _other ->
        resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  defp authenticate(conn) do
    valid_token = Application.fetch_env!(:broadcaster, :whip_token)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- token == valid_token do
      :ok
    else
      _other -> {:error, :unauthorized}
    end
  end

  defp update_layers(conn, stream_id) do
    case Forwarder.get_layers(stream_id) do
      {:ok, layers} ->
        data = Jason.encode!(%{layers: layers})
        chunk(conn, ~s/data: #{data}\n\n/)

        Process.send_after(self(), :layers, 2000)

        receive do
          :layers -> update_layers(conn, stream_id)
        end

      :error ->
        conn
    end
  end
end
