defmodule BroadcasterWeb.MediaController do
  use BroadcasterWeb, :controller

  alias Broadcaster.{Forwarder, PeerSupervisor}
  alias ExWebRTC.PeerConnection

  plug :accepts, ["sdp"] when action in [:whip, :whep]
  plug :accepts, ["trickle-ice-sdpfrag"] when action in [:ice_candidate]

  # TODO: use proper statuses in case of error
  def whip(conn, _params) do
    with :ok <- authenticate(conn),
         {:ok, offer_sdp, conn} <- read_body(conn),
         {:ok, pc, pc_id, answer_sdp} <- PeerSupervisor.start_whip(offer_sdp),
         :ok <- Forwarder.connect_input(pc) do
      conn
      |> put_resp_header("location", ~p"/api/resource/#{pc_id}")
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      _other -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  def whep(conn, _params) do
    with {:ok, offer_sdp, conn} <- read_body(conn),
         {:ok, pc, pc_id, answer_sdp} <- PeerSupervisor.start_whep(offer_sdp),
         :ok <- Forwarder.connect_output(pc) do
      resource_uri = ~p"/api/resource/#{pc_id}"
      conn
      |> put_resp_header("location", resource_uri)
      |> put_resp_header("link", ~s|<#{resource_uri}/layer>; rel="urn:ietf:params:whep:ext:core:layer"|)
      |> put_resp_header("link", ~s|<#{resource_uri}/layer>; rel="urn:ietf:params:whep:ext:core:server-sent-events"; events="layers"|)
      |> put_resp_content_type("application/sdp")
      |> resp(201, answer_sdp)
    else
      _other -> resp(conn, 400, "Bad request")
    end
    |> send_resp()
  end

  def ice_candidate(conn, %{"resource_id" => resource_id}) do
    name = PeerSupervisor.pc_name(resource_id)

    case read_body(conn) do
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

  def layer(conn, %{"resource_id" => resource_id}) do
    with [{pid, _}] <- Registry.lookup(Broadcaster.PeerRegistry, resource_id),
         :ok <- Forwarder.set_layer(pid, conn.body_params["encodingId"]) do
      resp(conn, 200, "")
    else
      other ->
        dbg(other)
        resp(conn, 400, "Bad reqeust")
    end
    |> send_resp()
  end

  def remove_pc(conn, %{"resource_id" => _resource_id}) do
    # TODO
    send_resp(conn, 200, "")
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
end
