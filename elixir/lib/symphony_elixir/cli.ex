defmodule SymphonyElixir.CLI do
  @moduledoc """
  Escript entrypoint for running Symphony with an explicit WORKFLOW.md path.
  """

  alias SymphonyElixir.LogFile

  @acknowledgement_switch :i_understand_that_this_will_be_running_without_the_usual_guardrails
  @switches [
    {@acknowledgement_switch, :boolean},
    check_tracker: :string,
    logs_root: :string,
    port: :integer,
    version: :boolean
  ]
  @version Mix.Project.config()[:version]

  @type ensure_started_result :: {:ok, [atom()]} | {:error, term()}
  @type deps :: %{
          file_regular?: (String.t() -> boolean()),
          set_workflow_file_path: (String.t() -> :ok | {:error, term()}),
          set_logs_root: (String.t() -> :ok | {:error, term()}),
          set_server_port_override: (non_neg_integer() | nil -> :ok | {:error, term()}),
          validate_configuration: (-> :ok | {:error, term()}),
          fetch_active_issues: (-> {:ok, [SymphonyElixir.Tracker.Issue.t()]} | {:error, term()}),
          ensure_all_started: (-> ensure_started_result())
        }

  @spec main([String.t()]) :: no_return()
  def main(args) do
    main(args, fn -> Application.ensure_all_started(:symphony_elixir) end)
  end

  @doc false
  @spec main([String.t()], (-> ensure_started_result())) :: no_return()
  def main(args, ensure_all_started) do
    case evaluate(args, runtime_deps(ensure_all_started)) do
      :ok ->
        wait_for_shutdown()

      {:version, version} ->
        IO.puts(version)
        System.halt(0)

      {:tracker_check, lines} ->
        IO.puts(Enum.join(lines, "\n"))
        System.halt(0)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @spec evaluate([String.t()], deps()) ::
          :ok | {:version, String.t()} | {:tracker_check, [String.t()]} | {:error, String.t()}
  def evaluate(args, deps \\ runtime_deps()) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} ->
        evaluate_options(opts, deps)

      {opts, [workflow_path], []} ->
        with :ok <- require_guardrails_acknowledgement(opts),
             :ok <- maybe_set_logs_root(opts, deps),
             :ok <- maybe_set_server_port(opts, deps) do
          run(workflow_path, deps)
        end

      _ ->
        {:error, usage_message()}
    end
  end

  @spec evaluate_options(keyword(), deps()) ::
          :ok | {:version, String.t()} | {:tracker_check, [String.t()]} | {:error, String.t()}
  defp evaluate_options(opts, deps) do
    cond do
      is_binary(Keyword.get(opts, :check_tracker)) ->
        check_tracker(Keyword.fetch!(opts, :check_tracker), deps)

      Keyword.get(opts, :version, false) ->
        {:version, @version}

      true ->
        with :ok <- require_guardrails_acknowledgement(opts),
             :ok <- maybe_set_logs_root(opts, deps),
             :ok <- maybe_set_server_port(opts, deps) do
          run(Path.expand("WORKFLOW.md"), deps)
        end
    end
  end

  @spec check_tracker(String.t(), deps()) ::
          {:tracker_check, [String.t()]} | {:error, String.t()}
  defp check_tracker(workflow_path, deps) do
    expanded_path = Path.expand(workflow_path)

    if deps.file_regular?.(expanded_path) do
      :ok = deps.set_workflow_file_path.(expanded_path)

      with :ok <- deps.validate_configuration.(),
           {:ok, issues} <- deps.fetch_active_issues.() do
        {:tracker_check,
         [
           "tracker check passed",
           "issues=" <> Integer.to_string(length(issues))
           | Enum.map(issues, &format_tracker_check_issue/1)
         ]}
      else
        {:error, reason} ->
          {:error, "Tracker check failed for #{expanded_path}: #{inspect(reason)}"}
      end
    else
      {:error, "Workflow file not found: #{expanded_path}"}
    end
  end

  @spec format_tracker_check_issue(SymphonyElixir.Tracker.Issue.t()) :: String.t()
  defp format_tracker_check_issue(issue) do
    Enum.map_join([issue.id, issue.identifier, issue.title, issue.state], "\t", &to_string/1)
  end

  @spec run(String.t(), deps()) :: :ok | {:error, String.t()}
  def run(workflow_path, deps) do
    expanded_path = Path.expand(workflow_path)

    if deps.file_regular?.(expanded_path) do
      :ok = deps.set_workflow_file_path.(expanded_path)

      case deps.ensure_all_started.() do
        {:ok, _started_apps} ->
          :ok

        {:error, reason} ->
          {:error, "Failed to start Symphony with workflow #{expanded_path}: #{inspect(reason)}"}
      end
    else
      {:error, "Workflow file not found: #{expanded_path}"}
    end
  end

  @spec usage_message() :: String.t()
  defp usage_message do
    "Usage: symphony [--logs-root <path>] [--port <port>] [path-to-WORKFLOW.md] | symphony --check-tracker <path-to-WORKFLOW.md>"
  end

  @spec runtime_deps() :: deps()
  defp runtime_deps(ensure_all_started \\ fn -> Application.ensure_all_started(:symphony_elixir) end) do
    %{
      file_regular?: &File.regular?/1,
      set_workflow_file_path: &SymphonyElixir.Workflow.set_workflow_file_path/1,
      set_logs_root: &set_logs_root/1,
      set_server_port_override: &set_server_port_override/1,
      validate_configuration: &SymphonyElixir.Config.validate!/0,
      fetch_active_issues: &fetch_active_issues/0,
      ensure_all_started: ensure_all_started
    }
  end

  defp fetch_active_issues do
    settings = SymphonyElixir.Config.settings!()
    SymphonyElixir.Tracker.fetch_issues_by_states(settings.tracker.active_states)
  end

  defp maybe_set_logs_root(opts, deps) do
    case Keyword.get_values(opts, :logs_root) do
      [] ->
        :ok

      values ->
        logs_root = values |> List.last() |> String.trim()

        if logs_root == "" do
          {:error, usage_message()}
        else
          :ok = deps.set_logs_root.(Path.expand(logs_root))
        end
    end
  end

  defp require_guardrails_acknowledgement(opts) do
    if Keyword.get(opts, @acknowledgement_switch, false) do
      :ok
    else
      {:error, acknowledgement_banner()}
    end
  end

  @spec acknowledgement_banner() :: String.t()
  defp acknowledgement_banner do
    lines = [
      "This Symphony implementation is a low key engineering preview.",
      "Codex will run without any guardrails.",
      "SymphonyElixir is not a supported product and is presented as-is.",
      "To proceed, start with `--i-understand-that-this-will-be-running-without-the-usual-guardrails` CLI argument"
    ]

    width = Enum.max(Enum.map(lines, &String.length/1))
    border = String.duplicate("─", width + 2)
    top = "╭" <> border <> "╮"
    bottom = "╰" <> border <> "╯"
    spacer = "│ " <> String.duplicate(" ", width) <> " │"

    content =
      [
        top,
        spacer
        | Enum.map(lines, fn line ->
            "│ " <> String.pad_trailing(line, width) <> " │"
          end)
      ] ++ [spacer, bottom]

    [
      IO.ANSI.red(),
      IO.ANSI.bright(),
      Enum.join(content, "\n"),
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp set_logs_root(logs_root) do
    Application.put_env(:symphony_elixir, :log_file, LogFile.default_log_file(logs_root))
    :ok
  end

  defp maybe_set_server_port(opts, deps) do
    case Keyword.get_values(opts, :port) do
      [] ->
        :ok

      values ->
        port = List.last(values)

        if is_integer(port) and port >= 0 do
          :ok = deps.set_server_port_override.(port)
        else
          {:error, usage_message()}
        end
    end
  end

  defp set_server_port_override(port) when is_integer(port) and port >= 0 do
    Application.put_env(:symphony_elixir, :server_port_override, port)
    :ok
  end

  @spec wait_for_shutdown() :: no_return()
  defp wait_for_shutdown do
    case Process.whereis(SymphonyElixir.Supervisor) do
      nil ->
        IO.puts(:stderr, "Symphony supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            case reason do
              :normal -> System.halt(0)
              _ -> System.halt(1)
            end
        end
    end
  end
end
