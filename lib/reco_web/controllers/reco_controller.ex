defmodule RecoWeb.RecoController do
  use RecoWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
