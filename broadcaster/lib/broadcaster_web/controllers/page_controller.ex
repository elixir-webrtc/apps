defmodule BroadcasterWeb.PageController do
  use BroadcasterWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      page_title: "Home",
      title: Application.get_env(:broadcaster, :title, ""),
      description: Application.get_env(:broadcaster, :description, "")
    )
  end

  def panel(conn, _params) do
    render(conn, :panel, page_title: "Panel")
  end

  def delete_chat_message(conn, %{"id" => id}) do
    BroadcasterWeb.Endpoint.broadcast!("stream:chat", "delete_chat_msg", %{id: id})
    send_resp(conn, 200, "")
  end

  def config_stream(conn, _params) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"title" => title, "description" => description} = Jason.decode!(body)
    Application.put_env(:broadcaster, :title, title)
    Application.put_env(:broadcaster, :description, description)
    send_resp(conn, 200, "")
  end
end
