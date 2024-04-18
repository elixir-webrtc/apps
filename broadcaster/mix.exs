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
      {:ex_webrtc, github: "elixir-webrtc/ex_webrtc", branch: "outbound-rtx"},
      {:plug, "~> 1.15.0"},
      {:bandit, "~> 1.4.0"}
    ]
  end
end
