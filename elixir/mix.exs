defmodule SymphonyElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :symphony_elixir,
      version: "0.0.2",
      elixir: "~> 1.19",
      # Mix itself owns the default build root so direct invocations cannot
      # accidentally reuse native output produced by another OS in the shared
      # F: checkout. MIX_BUILD_ROOT remains an explicit override for CI and
      # isolated diagnostic runs.
      build_path: build_path(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        summary: [
          threshold: 100
        ],
        ignore_modules: [
          SymphonyElixir.Asana.Client,
          SymphonyElixir.Config,
          SymphonyElixir.GitHub.Client,
          SymphonyElixir.GitLab.Client,
          SymphonyElixir.Jira.Client,
          SymphonyElixir.Linear.Client,
          SymphonyElixir.SpecsCheck,
          SymphonyElixir.Orchestrator,
          SymphonyElixir.Orchestrator.State,
          SymphonyElixir.AgentRunner,
          SymphonyElixir.Application,
          SymphonyElixir.CLI,
          SymphonyElixir.Codex.AppServer,
          SymphonyElixir.Codex.DynamicTool,
          SymphonyElixir.HttpServer,
          SymphonyElixir.StatusDashboard,
          SymphonyElixir.LogFile,
          SymphonyElixir.Workspace,
          SymphonyElixirWeb.DashboardLive,
          SymphonyElixirWeb.Endpoint,
          SymphonyElixirWeb.ErrorHTML,
          SymphonyElixirWeb.ErrorJSON,
          SymphonyElixirWeb.Layouts,
          SymphonyElixirWeb.ObservabilityApiController,
          SymphonyElixirWeb.Presenter,
          SymphonyElixirWeb.StaticAssetController,
          SymphonyElixirWeb.StaticAssets,
          SymphonyElixirWeb.Router,
          SymphonyElixirWeb.Router.Helpers
        ]
      ],
      test_ignore_filters: [
        "test/support/snapshot_support.exs",
        "test/support/test_support.exs"
      ],
      dialyzer: [
        plt_add_apps: [:mix]
      ],
      escript: escript(),
      releases: releases(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {SymphonyElixir.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:req, "~> 0.7.0"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"},
      {:solid, "~> 1.3.0"},
      {:ecto, "~> 3.14.0"},
      # Direct read-only SQLite access for the Step 3 tracker adapter. The
      # adapter does not need Ecto's persistence layer or pilot's migrations.
      {:exqlite, "~> 0.39.0"},
      {:burrito, "~> 1.5", only: :prod, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      build: ["escript.build"],
      lint: ["specs.check", "credo --strict"]
    ]
  end

  defp escript do
    [
      app: nil,
      main_module: SymphonyElixir.CLI,
      name: "symphony-dev",
      path: "bin/symphony-dev"
    ]
  end

  defp build_path do
    System.get_env("MIX_BUILD_ROOT") ||
      Path.join([mix_state_root(), mix_platform(), "_build"])
  end

  defp mix_state_root do
    state_root =
      case :os.type() do
        {:win32, _} ->
          configured_state_root(
            "LOCALAPPDATA",
            Path.join([System.user_home!(), "AppData", "Local"])
          )

        {:unix, _} ->
          configured_state_root(
            "XDG_STATE_HOME",
            Path.join([System.user_home!(), ".local", "state"])
          )
      end

    Path.join(state_root, "symphony-runtime/mix")
  end

  defp configured_state_root(variable, fallback) do
    case System.get_env(variable) do
      value when is_binary(value) and byte_size(value) > 0 -> value
      _ -> fallback
    end
  end

  defp mix_platform do
    case :os.type() do
      {:win32, _} -> "windows"
      {:unix, :darwin} -> "macos"
      {:unix, _} -> "linux"
    end
  end

  defp releases do
    [
      symphony: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_arm64: [os: :darwin, cpu: :aarch64],
            macos_x86_64: [os: :darwin, cpu: :x86_64],
            linux_arm64: [os: :linux, cpu: :aarch64],
            linux_x86_64: [os: :linux, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
