Mix.install([{:jason, "~> 1.2"}, {:ex_webrtc, "~> 0.2.0"}])

defmodule Converter do
  alias ExWebRTC.RTP.VP8Depayloader
  alias ExWebRTC.Media.IVF

  def process(_track_id, track, socket) do
    dbg(track)
    <<fourcc::little-32>> = "VP80"

    file = File.open!(track["path"])
    depayloader = VP8Depayloader.new()

    ivf_writer =
      IVF.Writer.open("./out.ivf",
        fourcc: fourcc,
        height: 640,
        width: 480,
        num_frames: 900,
        timebase_denum: 15,
        timebase_num: 1
      )

    read_and_save(file, depayloader, ivf_writer, 0, socket)
  end

  def read_and_save(file, depayloader, ivf_writer, frames_cnt, socket) do
    case IO.binread(file, 4) do
      {:error, reason} ->
        raise "#{reason}"

      :eof ->
        :ok

      <<packet_size::32>> ->
        packet = IO.binread(file, packet_size)
        :ok = :gen_udp.send(socket, {{127, 0, 0, 1}, 5556}, packet)

        case ExRTP.Packet.decode(packet) do
          {:ok, packet} ->
            dbg(packet)

            case VP8Depayloader.write(depayloader, packet) do
              {:ok, depayloader} ->
                read_and_save(file, depayloader, ivf_writer, frames_cnt, socket)

              {:ok, frame, depayloader} ->
                frame = %IVF.Frame{timestamp: frames_cnt, data: frame}
                {:ok, ivf_writer} = IVF.Writer.write_frame(ivf_writer, frame)
                read_and_save(file, depayloader, ivf_writer, frames_cnt + 1, socket)
            end

          _ ->
            read_and_save(file, depayloader, ivf_writer, frames_cnt, socket)
        end
    end
  end
end

{:ok, socket} = :gen_udp.open(0)

"./recordings/576460735120/report.json"
|> Path.expand()
|> File.read!()
|> Jason.decode!()
|> Enum.each(fn {id, track} ->
  if track["kind"] == "video" do
    Converter.process(id, track, socket)
  end
end)
