defmodule Recognizer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias Recognizer.Lobby

  use Application

  @max_rooms Application.compile_env!(:recognizer, :max_rooms)

  @version Mix.Project.config()[:version]

  @spec version() :: String.t()
  def version() do
    "v#{@version} #{commit()}"
  end

  defp commit() do
    case System.cmd("git", ["rev-parse", "--short", "HEAD"]) do
      {hash, 0} -> "(#{String.trim(hash)})"
      _ -> ""
    end
  end

  @impl true
  def start(_type, _args) do
    children = [
      RecognizerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:recognizer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Recognizer.PubSub},
      # Start a worker by calling: Recognizer.Worker.start_link(arg)
      # {Recognizer.Worker, arg},
      # Start to serve requests, typically the last entry
      RecognizerWeb.Endpoint,
      {Registry, keys: :unique, name: Recognizer.RoomRegistry},
      {DynamicSupervisor, name: Recognizer.RoomSupervisor, strategy: :one_for_one},
      {Nx.Serving,
       serving: create_video_serving(),
       name: Recognizer.VideoServing,
       batch_size: 4,
       batch_timeout: 100},
      {Lobby, @max_rooms}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Recognizer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RecognizerWeb.Endpoint.config_change(changed, removed)
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
