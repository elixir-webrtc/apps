defmodule Broadcaster.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BroadcasterWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:broadcaster, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Broadcaster.PubSub},
      # Start a worker by calling: Broadcaster.Worker.start_link(arg)
      # {Broadcaster.Worker, arg},
      # Start to serve requests, typically the last entry
      BroadcasterWeb.Endpoint,
      BroadcasterWeb.Presence,
      Broadcaster.PeerSupervisor,
      Broadcaster.Forwarder,
      {Registry, name: Broadcaster.PeerRegistry, keys: :unique}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Broadcaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BroadcasterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
