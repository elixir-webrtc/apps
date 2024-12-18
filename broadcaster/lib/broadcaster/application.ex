defmodule Broadcaster.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @version Mix.Project.config()[:version]

  @spec version() :: String.t()
  def version(), do: @version

  @impl true
  def start(_type, _args) do
    dist_config =
      case Application.fetch_env!(:broadcaster, :dist_config) do
        nil ->
          []

        config ->
          [{Cluster.Supervisor, [[cluster: config], [name: Broadcaster.ClusterSupervisor]]}]
      end

    {recordings_enabled?, recordings_config} =
      case Application.fetch_env!(:broadcaster, :recordings_config) do
        nil ->
          {false, []}

        config ->
          config = Keyword.put(config, :on_start, &Broadcaster.Forwarder.on_recorder_start/0)
          {true, [{ExWebRTC.Recorder, [config, [name: Broadcaster.Recorder]]}]}
      end

    # Start dist_config before starting Forwarder,
    # as Forwarder asks other nodes for their inputs.
    children =
      [
        BroadcasterWeb.Telemetry,
        {Phoenix.PubSub, name: Broadcaster.PubSub},
        BroadcasterWeb.Endpoint,
        BroadcasterWeb.Presence
      ] ++
        dist_config ++
        [
          Broadcaster.PeerSupervisor,
          {Broadcaster.Forwarder, [recordings_enabled?: recordings_enabled?]},
          Broadcaster.ChatHistory,
          {Registry, name: Broadcaster.ChatNicknamesRegistry, keys: :unique}
        ] ++ recordings_config

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
