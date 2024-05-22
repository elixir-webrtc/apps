defmodule BroadcasterWeb.ViewerCountChannelTest do
  use BroadcasterWeb.ChannelCase

  setup do
    {:ok, _, socket} =
      BroadcasterWeb.UserSocket
      |> socket("user_id", %{some: :assign})
      |> subscribe_and_join(BroadcasterWeb.StreamChannel, "viewer_count:lobby")

    %{socket: socket}
  end
end
