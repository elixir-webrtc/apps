defmodule Broadcaster.PeerSupervisor do
  use DynamicSupervisor

  require Logger

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription, RTPCodecParameters}

  @audio_codec %RTPCodecParameters{
    payload_type: 111,
    mime_type: "audio/opus",
    clock_rate: 48_000,
    channels: 2
  }

  @video_codec %RTPCodecParameters{
    payload_type: 96,
    mime_type: "video/H264",
    clock_rate: 90_000
  }

  @opts [
    ice_servers: [%{urls: "stun:stun.l.google.com:19302"}],
    audio_codecs: [@audio_codec],
    video_codecs: [@video_codec]
  ]

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec start_whip(String.t()) :: {:ok, pid(), String.t()} | {:error, term()}
  def start_whip(offer_sdp), do: start_pc(offer_sdp, :recvonly)

  @spec start_whep(String.t()) :: {:ok, pid(), String.t()} | {:error, term()}
  def start_whep(offer_sdp), do: start_pc(offer_sdp, :sendonly)

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
    {:ok, pc} = spawn_peer_connection()

    Logger.info("Received offer for #{inspect(pc)}, SDP:\n#{offer.sdp}")

    with :ok <- PeerConnection.set_remote_description(pc, offer),
         :ok <- setup_transceivers(pc, direction),
         {:ok, answer} <- PeerConnection.create_answer(pc),
         :ok <- PeerConnection.set_local_description(pc, answer),
         :ok <- gather_candidates(pc),
         answer <- PeerConnection.get_local_description(pc) do
      Logger.info("Sent answer for #{inspect(pc)}, SDP:\n#{answer.sdp}")

      {:ok, pc, answer.sdp}
    else
      {:error, _res} = err ->
        Logger.info("Failed to complete negotiation for #{inspect(pc)}")
        terminate_pc(pc)
        err
    end
  end

  defp setup_transceivers(pc, direction) do
    if direction == :sendonly do
      {:ok, _sender} = PeerConnection.add_track(pc, MediaStreamTrack.new(:audio))
      {:ok, _sender} = PeerConnection.add_track(pc, MediaStreamTrack.new(:video))
    end

    transceivers = PeerConnection.get_transceivers(pc)

    for %{id: id} <- transceivers do
      PeerConnection.set_transceiver_direction(pc, id, direction)
    end

    :ok
  end

  defp spawn_peer_connection() do
    args = Keyword.put(@opts, :controlling_process, self())

    child_spec = %{
      id: PeerConnection,
      start: {PeerConnection, :start_link, [args]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  defp gather_candidates(pc) do
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 -> {:error, :timeout}
    end
  end
end
