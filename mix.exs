defmodule Xuong.MixProject do
  use Mix.Project

  def project do
    [
      app: :xuong,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      # The core of Wings 3D (wings/, scripts/wings.sh). The parse
      # transform of its texts (intl_tools) compiles first.
      erlc_paths: ["wings/intl_tools", "wings/e3d", "wings/src"],
      erlc_include_path: "wings/src",
      erlc_options: [{:i, ~c"wings/src"}, {:i, ~c"wings/e3d"}, {:i, ~c"wings/intl_tools"}, :nowarn_export_all],
      deps: deps(),
      # The release for the Worker (scripts/edge.sh): the WebAssembly
      # runtime of beam.com has its own ERTS.
      releases: [xuong: [include_erts: System.get_env("RELEASE_ERTS") != "false"]],
      aliases: aliases(),
      test_coverage: [
        summary: [threshold: 100],
        # The copy of Wings 3D has its own tests upstream.
        ignore_modules: [~r/^:?(wings_|e3d|tools$|trace_2d$)/, Xuong.GLBHelper]
      ]
    ]
  end

  def cli, do: [preferred_envs: [precommit: :test]]

  def application, do: [mod: {Xuong.Application, []}, extra_applications: [:logger, :crypto]]

  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [precommit: ["compile --warnings-as-errors", "format", "test --cover"]]
  end
end
