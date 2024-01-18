defmodule Reco.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RecoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:reco, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Reco.PubSub},
      # Start a worker by calling: Reco.Worker.start_link(arg)
      # {Reco.Worker, arg},
      # Start to serve requests, typically the last entry
      RecoWeb.Endpoint,
      {Registry, keys: :unique, name: Reco.RoomRegistry},
      {DynamicSupervisor, name: Reco.RoomSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Reco.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RecoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
