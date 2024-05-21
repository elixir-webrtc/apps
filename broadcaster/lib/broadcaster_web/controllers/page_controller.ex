defmodule BroadcasterWeb.PageController do
  use BroadcasterWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Home")
  end

  def player(conn, _params) do
    render(conn, :player, page_title: "Player")
  end
end
