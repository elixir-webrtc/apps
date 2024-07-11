defmodule RecognizerWeb.RoomSocket do
  use Phoenix.Socket

  channel "room:*", RecognizerWeb.RoomChannel

  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  def id(_socket), do: nil
end
