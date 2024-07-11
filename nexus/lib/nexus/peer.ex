defmodule Nexus.Peer do
  @moduledoc false

  use GenServer

  require Logger

  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, RTPCodecParameters}
  alias Nexus.Chamber
  alias Nexus.Peer.State

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

  @type id :: String.t()

  @spec start_link(term(), term()) :: GenServer.on_start()
  def start_link(args, opts) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @spec apply_sdp_answer(id(), String.t()) :: :ok
  def apply_sdp_answer(id, answer_sdp) do
    GenServer.call(registry_id(id), {:apply_sdp_answer, answer_sdp})
  end

  @spec add_ice_candidate(id(), String.t()) :: :ok
  def add_ice_candidate(id, body) do
    GenServer.call(registry_id(id), {:add_ice_candidate, body})
  end

  @spec send_pli(id()) :: :ok
  def send_pli(id) do
    GenServer.cast(registry_id(id), :send_pli)
  end

  @spec notify(id(), term()) :: :ok
  def notify(id, noti) do
    GenServer.cast(registry_id(id), {:notification, noti})
  end

  @spec registry_id(id()) :: term()
  def registry_id(id), do: {:via, Registry, {Nexus.PeerRegistry, id}}

  @impl true
  def init([id, channel, peer_ids]) do
    Logger.debug("Starting new peer #{id}")
    {:ok, pc} = PeerConnection.start_link(@opts ++ [controlling_process: self()])
    Process.monitor(pc)
    Logger.debug("Starting peer connection #{inspect(pc)}")

    state = %State{
      id: id,
      channel: channel,
      pc: pc
    }

    {:ok, state, {:continue, {:initial_offer, peer_ids}}}
  end

  @impl true
  def handle_continue({:initial_offer, peer_ids}, %{pc: pc} = state) do
    Logger.debug("Creating initial SDP offer for #{state.id}")

    outbound_tracks = setup_transceivers(pc, peer_ids)

    state = State.send_offer(state)

    {:noreply, %{state | outbound_tracks: outbound_tracks}}
  end

  @impl true
  def handle_call({:apply_sdp_answer, answer_sdp}, _from, state) do
    state =
      if State.offer_pending?(state) do
        state
        |> State.apply_answer(answer_sdp)
        |> State.flush_candidates()
        |> State.send_notifications()
      else
        Logger.debug("Ignoring SDP answer for #{state.id}: no pending offer")
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:add_ice_candidate, body}, _from, state) do
    # TODO: this is not implemented as the RFC requires
    candidate =
      body
      |> Jason.decode!()
      |> ICECandidate.from_json()

    state = State.add_candidate(state, candidate)

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:send_pli, %{pc: pc} = state) do
    inbound_video_track_id = state.inbound_tracks.video

    unless is_nil(inbound_video_track_id) do
      :ok = PeerConnection.send_pli(pc, inbound_video_track_id)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:notification, {:forward, peer, obt}}, state) do
    Logger.debug("Peer #{state.id} forwarding tracks to peer #{peer}")

    {:noreply, put_in(state, [:peer_tracks, peer], obt)}
  end

  @impl true
  def handle_cast({:notification, {:peer_added, peer}}, %{pc: pc} = state) do
    Logger.debug("Peer #{state.id} preparing to receive media from #{peer}")

    tracks = add_outbound_track_pair(pc)

    state =
      state
      |> State.send_offer()
      |> State.enqueue_notification(peer, {:forward, state.id, Map.put(tracks, :pc, pc)})
      |> put_in([:outbound_tracks, peer], tracks)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:notification, {:peer_removed, peer}}, %{pc: pc} = state) do
    Logger.debug("Peer #{state.id} removing outbound tracks corresponding to peer #{peer}")
    {_, state} = pop_in(state, [:peer_tracks, peer])
    {spec, state} = pop_in(state, [:outbound_tracks, peer])

    :ok = PeerConnection.stop_transceiver(pc, spec.xcvrs.video)
    :ok = PeerConnection.stop_transceiver(pc, spec.xcvrs.audio)

    state = State.send_offer(state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_candidate, candidate}}, %{pc: pc} = state) do
    body =
      candidate
      |> ICECandidate.to_json()
      |> Jason.encode!()

    :ok = NexusWeb.PeerChannel.send_candidate(state.channel, body)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, %{pc: pc} = state) do
    Logger.debug("Peer #{state.id} connected")

    case Chamber.mark_ready(state.id, pc, state.outbound_tracks) do
      :ok ->
        state = State.send_notifications(state)
        {:noreply, state}

      {:peer_mismatch, _peer_ids} ->
        Logger.warning("Stopping peer #{state.id} because of state mismatch")
        {:stop, {:shutdown, :peer_mismatch}, state}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:rtp, id, _rid, packet}}, %{pc: pc} = state) do
    case state.inbound_tracks do
      %{video: ^id} -> broadcast_packet(state.peer_tracks, :video, packet)
      %{audio: ^id} -> broadcast_packet(state.peer_tracks, :audio, packet)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:rtcp, packets}}, %{pc: pc} = state) do
    Enum.each(packets, fn
      %ExRTCP.Packet.PayloadFeedback.PLI{} -> Chamber.broadcast_pli()
      _other -> :noop
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:track, track}}, %{pc: pc} = state) do
    Logger.debug("Peer #{state.id} added remote #{track.kind} track #{track.id}")

    state = put_in(state, [:inbound_tracks, track.kind], track.id)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pc, reason}, %{pc: pc} = state) do
    Logger.warning(
      "Peer #{state.id} shutting down: peer connection process #{inspect(pc)} terminated with reason #{inspect(reason)}"
    )

    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Ignoring unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp setup_transceivers(pc, peer_ids) do
    # Inbound tracks
    {:ok, _xcvr} = PeerConnection.add_transceiver(pc, :video, direction: :recvonly)
    {:ok, _xcvr} = PeerConnection.add_transceiver(pc, :audio, direction: :recvonly)

    # Outbound tracks
    Map.new(peer_ids, fn id ->
      {id, add_outbound_track_pair(pc)}
    end)
  end

  defp add_outbound_track_pair(pc) do
    stream_id = MediaStreamTrack.generate_stream_id()
    vt = MediaStreamTrack.new(:video, [stream_id])
    at = MediaStreamTrack.new(:audio, [stream_id])

    {:ok, video_xcvr} = PeerConnection.add_transceiver(pc, :video, direction: :sendonly)
    :ok = PeerConnection.replace_track(pc, video_xcvr.sender.id, vt)

    {:ok, audio_xcvr} = PeerConnection.add_transceiver(pc, :audio, direction: :sendonly)
    :ok = PeerConnection.replace_track(pc, audio_xcvr.sender.id, at)

    xcvrs = %{video: video_xcvr.id, audio: audio_xcvr.id}

    %{stream: stream_id, video: vt.id, audio: at.id, xcvrs: xcvrs}
  end

  defp broadcast_packet(peer_tracks, track_kind, packet) do
    Enum.each(peer_tracks, fn {_peer, tracks} ->
      track_id = Map.get(tracks, track_kind)

      unless is_nil(track_id), do: PeerConnection.send_rtp(tracks.pc, track_id, packet)
    end)

    :ok
  end
end
