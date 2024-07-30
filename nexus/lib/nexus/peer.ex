defmodule Nexus.Peer do
  @moduledoc false

  use GenServer

  require Logger

  alias ExWebRTC.{
    ICECandidate,
    MediaStreamTrack,
    PeerConnection,
    RTPCodecParameters,
    SessionDescription
  }

  alias Phoenix.PubSub

  alias Nexus.Room
  alias NexusWeb.PeerChannel

  @type id :: String.t()

  @type stream_spec :: %{
          :stream => String.t(),
          :video => String.t() | nil,
          :audio => String.t() | nil,
          :transceivers => %{video: String.t() | nil, audio: String.t() | nil},
          optional(:pc) => pid()
        }

  @type state :: %{
          id: id(),
          channel: pid(),
          pc: pid(),
          # Tracks streamed from the browser to the peer
          inbound_tracks: %{video: String.t() | nil, audio: String.t() | nil},
          # Tracks streamed from the peer to the browser
          outbound_tracks: %{(id :: String.t()) => stream_spec()},
          # Tracks of other peers which are subscribed to us
          # We forward the media received on `inbound_tracks` to these tracks
          peer_tracks: %{(id :: String.t()) => stream_spec()},
          # Received room notifications that will be handled after the current renegotiation completes
          pending_notifications: [{:peer_added | :peer_removed, id()}],
          # Subscription requests that will be sent after the current renegotiation completes
          scheduled_subscriptions: [{id(), stream_spec()}]
        }

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

  @opts [
    ice_servers: [%{urls: "stun:stun.l.google.com:19302"}],
    audio_codecs: @audio_codecs,
    video_codecs: @video_codecs
  ]

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

  @spec peer_added(id()) :: :ok
  def peer_added(id) do
    PubSub.broadcast(Nexus.PubSub, "room", {:peer_added, id})
  end

  @spec peer_removed(id()) :: :ok
  def peer_removed(id) do
    PubSub.broadcast(Nexus.PubSub, "room", {:peer_removed, id})
  end

  @spec add_subscriber(id(), id(), stream_spec()) :: :ok
  def add_subscriber(id, peer, stream_spec) do
    GenServer.cast(registry_id(id), {:add_subscriber, peer, stream_spec})
  end

  @spec request_keyframe(id()) :: :ok
  def request_keyframe(id) do
    GenServer.cast(registry_id(id), :request_keyframe)
  end

  @spec registry_id(id()) :: term()
  def registry_id(id), do: {:via, Registry, {Nexus.PeerRegistry, id}}

  @impl true
  def init([id, channel, peer_ids]) do
    Logger.debug("Starting new peer #{id}")
    ice_port_range = Application.fetch_env!(:nexus, :ice_port_range)
    pc_opts = @opts ++ [ice_port_range: ice_port_range]
    {:ok, pc} = PeerConnection.start_link(pc_opts)
    Process.monitor(pc)
    Logger.debug("Starting peer connection #{inspect(pc)}")

    Process.link(channel)

    state = %{
      id: id,
      channel: channel,
      pc: pc,
      inbound_tracks: %{video: nil, audio: nil},
      outbound_tracks: %{},
      peer_tracks: %{},
      pending_notifications: [],
      scheduled_subscriptions: []
    }

    {:ok, state, {:continue, {:initial_offer, peer_ids}}}
  end

  @impl true
  def handle_continue({:initial_offer, peer_ids}, %{pc: pc} = state) do
    Logger.debug("Creating initial SDP offer for #{state.id}")

    outbound_tracks = setup_transceivers(pc, peer_ids)

    state = send_offer(state)

    {:noreply, %{state | outbound_tracks: outbound_tracks}}
  end

  @impl true
  def handle_call({:apply_sdp_answer, answer_sdp}, _from, %{pc: pc} = state) do
    answer = %SessionDescription{type: :answer, sdp: answer_sdp}
    Logger.debug("Applying SDP answer for #{state.id}:\n#{answer.sdp}")

    state =
      case PeerConnection.set_remote_description(pc, answer) do
        :ok ->
          state
          |> send_subscriptions()
          |> handle_pending_notifications()

        {:error, reason} ->
          Logger.warning("Unable to apply SDP answer for #{state.id}: #{inspect(reason)}")
          state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:add_ice_candidate, body}, _from, %{pc: pc} = state) do
    candidate =
      body
      |> Jason.decode!()
      |> ICECandidate.from_json()

    :ok = PeerConnection.add_ice_candidate(pc, candidate)

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(:request_keyframe, %{pc: pc} = state) do
    inbound_video_track_id = state.inbound_tracks.video

    unless is_nil(inbound_video_track_id) do
      :ok = PeerConnection.send_pli(pc, inbound_video_track_id)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:add_subscriber, peer, tracks}, state) do
    Logger.debug("Peer #{state.id} received subscribe request from peer #{peer}")

    {:noreply, put_in(state.peer_tracks[peer], tracks)}
  end

  @impl true
  def handle_info({:peer_added, peer}, %{pc: pc} = state) do
    if PeerConnection.get_signaling_state(pc) == :have_local_offer do
      Logger.debug("Peer #{state.id} scheduled adding of #{peer} after receiving SDP answer")
      {:noreply, add_pending_notification(state, {:peer_added, peer})}
    else
      {:noreply, state |> add_peer(peer) |> send_offer()}
    end
  end

  @impl true
  def handle_info({:peer_removed, peer}, %{pc: pc} = state) do
    if PeerConnection.get_signaling_state(pc) == :have_local_offer do
      Logger.debug("Peer #{state.id} scheduled removal of #{peer} after receiving SDP answer")
      {:noreply, add_pending_notification(state, {:peer_removed, peer})}
    else
      {:noreply, state |> remove_peer(peer) |> send_offer()}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_candidate, candidate}}, %{pc: pc} = state) do
    body =
      candidate
      |> ICECandidate.to_json()
      |> Jason.encode!()

    :ok = PeerChannel.send_candidate(state.channel, body)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :connected}}, %{pc: pc} = state) do
    Logger.debug("Peer #{state.id} connected")

    known_peer_ids = Map.keys(state.outbound_tracks)

    case Room.mark_ready(state.id, known_peer_ids) do
      :ok ->
        :ok = PubSub.subscribe(Nexus.PubSub, "room")

        Enum.each(state.outbound_tracks, fn {peer, track_specs} ->
          add_subscriber(peer, state.id, Map.put(track_specs, :pc, pc))
        end)

        {:noreply, handle_pending_notifications(state)}

      {:peer_mismatch, _peer_ids} ->
        Logger.warning("Stopping peer #{state.id} because of room state mismatch")
        {:stop, {:shutdown, :peer_mismatch}, state}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:connection_state_change, :failed}}, %{pc: pc} = state) do
    Logger.warning("Stopping peer #{state.id} because ICE connection changed state to `failed`")
    {:stop, {:shutdown, :ice_connection_failed}, state}
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
      {track_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} ->
        {peer_id, _} =
          Enum.find(state.outbound_tracks, {nil, nil}, fn {_, spec} -> spec.video == track_id end)

        unless is_nil(peer_id), do: request_keyframe(peer_id)

      _other ->
        :noop
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, pc, {:track, track}}, %{pc: pc} = state) do
    Logger.debug("Peer #{state.id} added remote #{track.kind} track #{track.id}")

    state = put_in(state.inbound_tracks[track.kind], track.id)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pc, reason}, %{pc: pc} = state) do
    Logger.warning(
      "Peer #{state.id} shutting down: peer connection process #{inspect(pc)} terminated with reason #{inspect(reason)}"
    )

    {:stop, {:shutdown, :peer_connection_closed}, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Ignoring unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp setup_transceivers(pc, peer_ids) do
    # Inbound tracks
    {:ok, _tr} = PeerConnection.add_transceiver(pc, :video, direction: :recvonly)
    {:ok, _tr} = PeerConnection.add_transceiver(pc, :audio, direction: :recvonly)

    # Outbound tracks
    Map.new(peer_ids, fn id ->
      {id, add_outbound_track_pair(pc)}
    end)
  end

  defp add_outbound_track_pair(pc) do
    stream_id = MediaStreamTrack.generate_stream_id()
    vt = MediaStreamTrack.new(:video, [stream_id])
    at = MediaStreamTrack.new(:audio, [stream_id])

    {:ok, video_tr} = PeerConnection.add_transceiver(pc, :video, direction: :sendonly)
    :ok = PeerConnection.replace_track(pc, video_tr.sender.id, vt)

    {:ok, audio_tr} = PeerConnection.add_transceiver(pc, :audio, direction: :sendonly)
    :ok = PeerConnection.replace_track(pc, audio_tr.sender.id, at)

    transceivers = %{video: video_tr.id, audio: audio_tr.id}

    %{stream: stream_id, video: vt.id, audio: at.id, transceivers: transceivers}
  end

  defp add_peer(state, peer) do
    Logger.debug("Peer #{state.id} preparing to receive media from #{peer}")

    tracks = add_outbound_track_pair(state.pc)

    state =
      schedule_subscription(state, peer, Map.put(tracks, :pc, state.pc))

    put_in(state.outbound_tracks[peer], tracks)
  end

  defp remove_peer(state, peer) do
    Logger.debug("Peer #{state.id} removing outbound tracks corresponding to peer #{peer}")

    {_, state} = pop_in(state.peer_tracks[peer])
    {spec, state} = pop_in(state.outbound_tracks[peer])

    :ok = PeerConnection.stop_transceiver(state.pc, spec.transceivers.video)
    :ok = PeerConnection.stop_transceiver(state.pc, spec.transceivers.audio)

    state
  end

  defp add_pending_notification(state, notification) do
    Map.update!(state, :pending_notifications, &[notification | &1])
  end

  defp handle_pending_notifications(%{pending_notifications: []} = state) do
    state
  end

  defp handle_pending_notifications(state) do
    state.pending_notifications
    |> Enum.reverse()
    |> Enum.reduce(state, fn
      {:peer_added, peer}, state -> add_peer(state, peer)
      {:peer_removed, peer}, state -> remove_peer(state, peer)
    end)
    |> send_offer()
    |> Map.put(:pending_notifications, [])
  end

  defp schedule_subscription(state, peer, stream_spec) do
    Map.update!(state, :scheduled_subscriptions, &[{peer, stream_spec} | &1])
  end

  defp send_subscriptions(state) do
    state.scheduled_subscriptions
    |> Enum.reverse()
    |> Enum.each(fn {dest, tracks} -> add_subscriber(dest, state.id, tracks) end)

    %{state | scheduled_subscriptions: []}
  end

  defp send_offer(%{pc: pc} = state) do
    {:ok, offer} = PeerConnection.create_offer(pc)
    Logger.debug("Sending SDP offer for #{state.id}:\n#{offer.sdp}")

    :ok = PeerConnection.set_local_description(pc, offer)
    :ok = PeerChannel.send_offer(state.channel, offer.sdp)

    state
  end

  defp broadcast_packet(peer_tracks, track_kind, packet) do
    Enum.each(peer_tracks, fn {_peer, tracks} ->
      track_id = Map.get(tracks, track_kind)

      unless is_nil(track_id), do: PeerConnection.send_rtp(tracks.pc, track_id, packet)
    end)

    :ok
  end
end
