defmodule Broadcaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :broadcaster,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Broadcaster, []}
    ]
  end

  defp deps do
    [
      {:ex_webrtc, github: "elixir-webrtc/ex_webrtc"},
      {:plug, "~> 1.15.0"},
      {:plug_cowboy, "~> 2.0"},
      {:corsica, "~> 2.0.0"},
      {:observer_cli, "~> 1.7.0"}
    ]
  end
end
