defmodule Broadcaster.Recorder do
  use GenServer, restart: :temporary

  alias ExWebRTC.MediaStreamTrack

  require Logger

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def add_tracks(tracks) do
    GenServer.call(__MODULE__, {:add_tracks, tracks})
  end

  @spec record(MediaStreamTrack.id(), ExRTP.Packet.t()) :: :ok
  def record(track_id, %ExRTP.Packet{} = packet) do
    GenServer.cast(__MODULE__, {:record, track_id, packet})
  end

  @impl true
  def init(_) do
    Logger.info("Starting recorder")
    now = System.monotonic_time(:millisecond)
    now = if now < 0, do: now * -1, else: now
    base_dir = Application.get_env(:broadcaster, :recordings_base_dir, "./recordings")
    base_dir = Path.join(base_dir, "#{now}") |> Path.expand()
    :ok = File.mkdir_p!(base_dir)
    Logger.info("Recordings will be saved under: #{base_dir}")
    {:ok, %{base_dir: base_dir, tracks: %{}}}
  end

  @impl true
  def handle_call({:add_tracks, tracks}, _from, state) do
    tracks =
      Map.new(tracks, fn track ->
        path = Path.join(state.base_dir, "#{track.id}.br")
        file = File.open!(path, [:write])

        {track.id, %{kind: track.kind, path: path, file: file}}
      end)

    report_path = Path.join(state.base_dir, "report.json")

    report =
      Map.new(tracks, fn {id, track} ->
        track = Map.delete(track, :file)
        {id, track}
      end)

    :ok = File.write!(report_path, Jason.encode!(report))

    state = %{state | tracks: tracks}
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:record, track_id, packet}, state) when is_map_key(state.tracks, track_id) do
    packet = ExRTP.Packet.encode(packet) |> :erlang.term_to_binary()
    packet_size = byte_size(packet)

    packet = <<packet_size::32, packet::binary>>

    :ok = IO.binwrite(state.tracks[track_id].file, packet)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:record, track_id, _packet}, state) do
    Logger.warning("""
    Tried to saved packet for unknown track id. Ignoring. Track id: #{inspect(track_id)}.\
    """)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    dbg(msg)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("Terminating recorder with reason: #{inspect(reason)}")
    :ok
  end
end
