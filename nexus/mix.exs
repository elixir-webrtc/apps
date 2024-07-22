defmodule Nexus.MixProject do
  use Mix.Project

  def project do
    [
      app: :nexus,
      version: "0.1.0-dev",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # dialyzer
      dialyzer: [
        plt_local_path: "_dialyzer",
        plt_core_path: "_dialyzer"
      ]
    ]
  end

  def application do
    [
      mod: {Nexus.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      {:bunch, "~> 1.6"},
      # {:ex_webrtc, "~> 0.3.0"},
      # {:ex_webrtc_dashboard, "~> 0.3.0"},
      {:ex_webrtc, github: "elixir-webrtc/ex_webrtc"},
      {:ex_webrtc_dashboard, github: "elixir-webrtc/ex_webrtc_dashboard"},

      # Dialyzer and credo
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind nexus", "esbuild nexus"],
      "assets.deploy": [
        "tailwind nexus --minify",
        "esbuild nexus --minify",
        "phx.digest"
      ],
      "assets.format": &lint_and_format_assets/1
    ]
  end

  defp lint_and_format_assets(_args) do
    with {_, 0} <- execute_npm_command(["ci"]),
         {_, 0} <- execute_npm_command(["run", "lint"]),
         {_, 0} <- execute_npm_command(["run", "format"]) do
      :ok
    else
      {cmd, rc} ->
        Mix.shell().error("npm command `#{Enum.join(cmd, " ")}` failed with code #{rc}")
        exit({:shutdown, rc})
    end
  end

  defp execute_npm_command(command) do
    {_stream, rc} = System.cmd("npm", ["--prefix=assets"] ++ command, into: IO.stream())
    {command, rc}
  end
end
