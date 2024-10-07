defmodule BroadcasterWeb.PageController do
  use BroadcasterWeb, :controller

  def home(conn, _params) do
    title = Application.get_env(:broadcaster, :title, "") |> to_html()
    description = Application.get_env(:broadcaster, :description, "") |> to_html()

    render(conn, :home,
      page_title: "Home",
      title: title,
      description: description
    )
  end

  def panel(conn, _params) do
    render(conn, :panel, page_title: "Panel")
  end

  def delete_chat_message(conn, %{"id" => id}) do
    Broadcaster.ChatHistory.delete(id)
    BroadcasterWeb.Endpoint.broadcast!("broadcaster:chat", "delete_chat_msg", %{id: id})
    send_resp(conn, 200, "")
  end

  def config_stream(conn, _params) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"title" => title, "description" => description} = Jason.decode!(body)
    Application.put_env(:broadcaster, :title, title)
    Application.put_env(:broadcaster, :description, description)
    send_resp(conn, 200, "")
  end

  def get_admin_chat_token(conn, _params) do
    token = Phoenix.Token.sign(BroadcasterWeb.Endpoint, "admin", <<>>)
    send_resp(conn, 200, Jason.encode!(%{"token" => token}))
  end

  defp to_html(markdown) do
    markdown
    |> String.trim()
    |> Earmark.as_html!()
  end
end
