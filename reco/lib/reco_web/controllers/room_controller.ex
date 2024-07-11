defmodule RecoWeb.RoomController do
  use RecoWeb, :controller

  def room(conn, _params) do
    render(conn, :room)
  end
end
