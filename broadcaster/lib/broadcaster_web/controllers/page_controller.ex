defmodule BroadcasterWeb.PageController do
  use BroadcasterWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Home")
  end

  def panel(conn, _params) do
    render(conn, :panel, page_title: "Panel")
  end

  def delete_chat_message(conn, %{"id" => id}) do
    BroadcasterWeb.Endpoint.broadcast!("stream:chat-admin", "delete_chat_msg", %{id: id})
    BroadcasterWeb.Endpoint.broadcast!("stream:chat", "delete_chat_msg", %{id: id})

    send_resp(conn, 200, "")
  end
end
