defmodule NexusWeb.UserSocket do
  use Phoenix.Socket

  channel "stream:*", NexusWeb.StreamChannel
  channel "peer:*", NexusWeb.PeerChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, assign(socket, :user_id, generate_id())}
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  defp generate_id do
    10
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64()
  end
end
