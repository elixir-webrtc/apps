defmodule Broadcaster.PeerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  require Logger

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription, RTPCodecParameters}

  @audio_codecs [
    %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  ]

  @video_codecs [
    %RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }
  ]

  @spec client_pc_config() :: String.t()
  def client_pc_config() do
    pc_config = Application.fetch_env!(:broadcaster, :pc_config)

    %{
      iceServers: pc_config[:ice_servers],
      iceTransportPolicy: pc_config[:ice_transport_policy]
    }
    |> Jason.encode!()
  end

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(arg) do
    :syn.add_node_to_scopes([Broadcaster.GlobalPeerRegistry])

    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec start_whip(String.t()) :: {:ok, pid(), String.t(), String.t()} | {:error, term()}
  def start_whip(offer_sdp), do: start_pc(offer_sdp, :recvonly)

  @spec start_whep(String.t()) :: {:ok, pid(), String.t(), String.t()} | {:error, term()}
  def start_whep(offer_sdp), do: start_pc(offer_sdp, :sendonly)

  @spec fetch_pid(String.t()) :: {:ok, pid()} | {:error, :peer_not_found}
  def fetch_pid(id) do
    case :syn.lookup(Broadcaster.GlobalPeerRegistry, id) do
      :undefined -> {:error, :peer_not_found}
      {pid, _val} -> {:ok, pid}
    end
  end

  @spec terminate_pc(pid()) :: :ok | {:error, :not_found}
  def terminate_pc(pc) do
    DynamicSupervisor.terminate_child(__MODULE__, pc)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp start_pc(offer_sdp, direction) do
    offer = %SessionDescription{type: :offer, sdp: offer_sdp}
    pc_id = generate_pc_id()
    {:ok, pc} = spawn_peer_connection()
    :syn.register(Broadcaster.GlobalPeerRegistry, pc_id, pc)

    Logger.info("Received offer for #{inspect(pc)}")
    Logger.debug("Offer SDP for #{inspect(pc)}:\n#{offer.sdp}")

    with :ok <- PeerConnection.set_remote_description(pc, offer),
         :ok <- setup_transceivers(pc, direction),
         {:ok, answer} <- PeerConnection.create_answer(pc),
         :ok <- PeerConnection.set_local_description(pc, answer),
         :ok <- gather_candidates(pc),
         answer <- PeerConnection.get_local_description(pc) do
      Logger.info("Sent answer for #{inspect(pc)}")
      Logger.debug("Answer SDP for #{inspect(pc)}:\n#{answer.sdp}")

      {:ok, pc, pc_id, answer.sdp}
    else
      {:error, _res} = err ->
        Logger.info("Failed to complete negotiation for #{inspect(pc)}")
        terminate_pc(pc)
        err
    end
  end

  defp setup_transceivers(pc, direction) do
    if direction == :sendonly do
      stream_id = MediaStreamTrack.generate_stream_id()
      {:ok, _sender} = PeerConnection.add_track(pc, MediaStreamTrack.new(:audio, [stream_id]))
      {:ok, _sender} = PeerConnection.add_track(pc, MediaStreamTrack.new(:video, [stream_id]))
    end

    transceivers = PeerConnection.get_transceivers(pc)

    for %{id: id} <- transceivers do
      PeerConnection.set_transceiver_direction(pc, id, direction)
    end

    :ok
  end

  defp spawn_peer_connection() do
    pc_opts =
      (Application.fetch_env!(:broadcaster, :pc_config) ++
         [
           audio_codecs: @audio_codecs,
           video_codecs: @video_codecs,
           controlling_process: self()
         ])
      |> Keyword.delete(:ice_transport_policy)

    child_spec = %{
      id: PeerConnection,
      start: {PeerConnection, :start_link, [pc_opts, []]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  defp gather_candidates(pc) do
    # we either wait for all of the candidates
    # or whatever we were able to gather in one second
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 -> :ok
    end
  end

  defp generate_pc_id(), do: for(_ <- 1..10, into: "", do: <<Enum.random(~c"0123456789abcdef")>>)
end
