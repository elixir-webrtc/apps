defmodule Reco.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias Reco.Lobby

  use Application

  @max_rooms Application.compile_env!(:reco, :max_rooms)

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
      {DynamicSupervisor, name: Reco.RoomSupervisor, strategy: :one_for_one},
      {Nx.Serving,
       serving: create_video_serving(), name: Reco.VideoServing, batch_size: 4, batch_timeout: 100},
      {Lobby, @max_rooms}
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

  defp create_video_serving() do
    {:ok, model} = Bumblebee.load_model({:hf, "microsoft/resnet-50"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})

    Bumblebee.Vision.image_classification(model, featurizer,
      top_k: 1,
      compile: [batch_size: 4],
      defn_options: [compiler: EXLA]
    )
  end
end
