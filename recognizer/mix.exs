defmodule Recognizer.MixProject do
  use Mix.Project

  def project do
    [
      app: :recognizer,
      version: "0.6.0",
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

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Recognizer.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.10"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.1"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:plug_cowboy, "~> 2.5"},
      {:ex_webrtc, "~> 0.14.0"},
      {:ex_webrtc_dashboard, "~> 0.9.0"},
      {:xav, "~> 0.11.0"},
      {:bumblebee, "~> 0.6.2"},
      {:exla, "~> 0.9.2"},

      # Dialyzer and credo
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "deps.patch", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"],
      "assets.format": &lint_and_format_assets/1,
      "assets.check": &check_assets/1,
      "deps.patch": &patch_deps/1
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

  defp check_assets(_args) do
    with {_, 0} <- execute_npm_command(["ci"]),
         {_, 0} <- execute_npm_command(["run", "check"]) do
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

  # HACK: With clang 17.0.0, compilation of `exla==0.9.2` fails because of the `-Wmissing-template-arg-list-after-template-kw` check.
  #       This issue isn't present in `exla==0.10.0`, but `bumblebee==0.6.2` depends on `nx ~> 0.9.0`,
  #       and since `exla==0.10.0` depends on `nx ~> 0.10.0`, we're stuck on `exla==0.9.2` until a new version of `bumblebee` is released.
  #
  #       This patch adds the `-Wno-missing-template-arg-list-after-template-kw` flag in `exla`'s Makefile to suppress the compiler warning.
  defp patch_deps(_args) do
    {_, _} =
      System.cmd("patch", ~w(-p1 -i ./0000-exla-disable-failing-clang-compile-check.patch),
        into: IO.stream()
      )

    :ok
  end
end
