defmodule Broadcaster do
  use Application

  alias __MODULE__.{Forwarder, PeerSupervisor, Router}

  @impl true
  def start(_type, _args) do
    ip = Application.fetch_env!(:broadcaster, :ip)
    port = Application.fetch_env!(:broadcaster, :port)

    children = [
      {Bandit, plug: Router, scheme: :http, ip: ip, port: port},
      PeerSupervisor,
      Forwarder,
      {Registry, name: __MODULE__.PeerRegistry, keys: :unique}
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: __MODULE__.Supervisor)
  end
end
