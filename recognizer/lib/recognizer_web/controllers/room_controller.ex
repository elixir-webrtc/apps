defmodule RecognizerWeb.RoomController do
  use RecognizerWeb, :controller

  def room(conn, _params) do
    render(conn, :room)
  end
end
