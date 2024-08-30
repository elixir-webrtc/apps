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
      mime_type: "video/H264",
      clock_rate: 90_000
    }
  ]

  @opts [
    ice_servers: [%{urls: "stun:stun.l.google.com:19302"}],
    audio_codecs: @audio_codecs,
    video_codecs: @video_codecs
  ]

  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec start_whip(String.t()) :: {:ok, pid(), String.t(), String.t()} | {:error, term()}
  def start_whip(offer_sdp), do: start_pc(offer_sdp, :recvonly)

  @spec start_whep(String.t(), String.t()) ::
          {:ok, pid(), String.t(), String.t()} | {:error, term()}
  def start_whep(offer_sdp, stream_id), do: start_pc(offer_sdp, :sendonly, stream_id <> "-")

  @spec fetch_pid(String.t()) :: {:ok, pid()} | :error
  def fetch_pid(id) do
    case Registry.lookup(Broadcaster.PeerRegistry, id) do
      [] -> :error
      [{pid, _val}] -> {:ok, pid}
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

  defp start_pc(offer_sdp, direction, pc_id_base \\ "") do
    offer = %SessionDescription{type: :offer, sdp: offer_sdp}
    pc_id = pc_id_base <> generate_pc_id()
    {:ok, pc} = spawn_peer_connection(pc_id)

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

  defp spawn_peer_connection(id) do
    ice_port_range = Application.fetch_env!(:broadcaster, :ice_port_range)
    gen_server_opts = [name: {:via, Registry, {Broadcaster.PeerRegistry, id}}]
    pc_opts = @opts ++ [controlling_process: self(), ice_port_range: ice_port_range]

    child_spec = %{
      id: PeerConnection,
      start: {PeerConnection, :start_link, [pc_opts, gen_server_opts]},
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
