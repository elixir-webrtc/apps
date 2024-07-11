defmodule Nexus.Peer.State do
  @moduledoc false

  use Bunch.Access

  require Logger

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Nexus.Peer
  alias NexusWeb.PeerChannel

  @type stream_spec :: %{stream: String.t(), video: String.t() | nil, audio: String.t() | nil}

  @type t :: %__MODULE__{
          id: String.t(),
          channel: pid(),
          pc: pid(),
          inbound_tracks: %{video: String.t() | nil, audio: String.t() | nil},
          outbound_tracks: %{(id :: String.t()) => stream_spec()},
          peer_tracks: %{(id :: String.t()) => stream_spec()},
          candidates: [ICECandidate.t()] | :flushed,
          notification_queue: [term()],
          offer_pending?: boolean()
        }

  @enforce_keys [:id, :channel, :pc]

  defstruct @enforce_keys ++
              [
                inbound_tracks: %{video: nil, audio: nil},
                outbound_tracks: %{},
                peer_tracks: %{},
                candidates: [],
                notification_queue: [],
                offer_pending?: false
              ]

  @spec add_candidate(t(), ICECandidate.t()) :: t()
  def add_candidate(state, candidate) do
    if state.candidates == :flushed do
      :ok = PeerConnection.add_ice_candidate(state.pc, candidate)
      state
    else
      %{state | candidates: [candidate | state.candidates]}
    end
  end

  @spec flush_candidates(t()) :: t()
  def flush_candidates(state) do
    if is_list(state.candidates) do
      for candidate <- state.candidates do
        :ok = PeerConnection.add_ice_candidate(state.pc, candidate)
      end
    end

    %{state | candidates: :flushed}
  end

  @spec enqueue_notification(t(), Process.dest(), term()) :: t()
  def enqueue_notification(state, dest, notification) do
    Map.update!(state, :notification_queue, &[{dest, notification} | &1])
  end

  @spec send_notifications(t()) :: t()
  def send_notifications(state) do
    state.notification_queue
    |> Enum.reverse()
    |> Enum.each(fn {dest, notification} ->
      Peer.notify(dest, notification)
    end)

    %{state | notification_queue: []}
  end

  @spec send_offer(t()) :: t()
  def send_offer(%{pc: pc} = state) do
    {:ok, offer} = PeerConnection.create_offer(pc)
    Logger.debug("Sending SDP offer for #{state.id}:\n#{offer.sdp}")

    :ok = PeerConnection.set_local_description(pc, offer)

    PeerChannel.send_offer(state.channel, offer.sdp)

    %{state | offer_pending?: true}
  end

  @spec apply_answer(t(), String.t()) :: t()
  def apply_answer(state, answer_sdp) do
    answer = %SessionDescription{type: :answer, sdp: answer_sdp}
    Logger.debug("Applying SDP answer for #{state.id}:\n#{answer.sdp}")

    :ok = PeerConnection.set_remote_description(state.pc, answer)

    %{state | offer_pending?: false}
  end

  @spec offer_pending?(t()) :: boolean()
  def offer_pending?(state), do: state.offer_pending?
end
