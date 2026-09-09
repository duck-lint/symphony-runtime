defmodule SymphonyElixir.CLI do
  @moduledoc "Escript entry point for a Runtime WORKFLOW projection."

  alias SymphonyElixir.LogFile
  @acknowledgement_switch :i_understand_that_this_will_be_running_without_the_usual_guardrails
  @switches [{@acknowledgement_switch, :boolean}, logs_root: :string, port: :integer, version: :boolean]
  @version Mix.Project.config()[:version]

  def main(args), do: main(args, fn -> Application.ensure_all_started(:symphony_elixir) end)

  @doc false
  def main(args, ensure_started) do
    case evaluate(args, ensure_started: ensure_started) do
      :ok -> wait_for_shutdown()
      {:version, version} -> IO.puts(version); System.halt(0)
      {:error, message} -> IO.puts(:stderr, message); System.halt(1)
    end
  end

  @doc false
  def evaluate(args, opts \\ []) do
    case OptionParser.parse(args, strict: @switches) do
      {parsed, [], []} -> evaluate_options(parsed, opts)
      {parsed, [workflow_path], []} -> with :ok <- require_ack(parsed), :ok <- set_options(parsed), do: run(workflow_path, opts)
      _ -> {:error, usage_message()}
    end
  end

  defp evaluate_options(opts, deps) do
    cond do
      Keyword.get(opts, :version, false) -> {:version, @version}
      true -> with :ok <- require_ack(opts), :ok <- set_options(opts), do: run(Path.expand("WORKFLOW.md"), deps)
    end
  end

  defp run(path, opts) do
    if File.regular?(Path.expand(path)) do
      :ok = SymphonyElixir.Workflow.set_workflow_file_path(Path.expand(path))
      case Keyword.get(opts, :ensure_started, fn -> Application.ensure_all_started(:symphony_elixir) end).() do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, "Failed to start Runtime: #{inspect(reason)}"}
      end
    else
      {:error, "Workflow file not found: #{Path.expand(path)}"}
    end
  end

  defp set_options(opts) do
    case Keyword.get(opts, :logs_root) do
      nil -> :ok
      value -> Application.put_env(:symphony_elixir, :log_file, LogFile.default_log_file(Path.expand(value)))
    end
    case Keyword.get(opts, :port) do
      nil -> :ok
      port when is_integer(port) and port >= 0 -> Application.put_env(:symphony_elixir, :server_port_override, port)
      _ -> {:error, usage_message()}
    end
    :ok
  end

  defp require_ack(opts) do
    if Keyword.get(opts, @acknowledgement_switch, false), do: :ok, else: {:error, "Runtime requires --#{@acknowledgement_switch}"}
  end
  defp usage_message, do: "Usage: symphony [--logs-root <path>] [--port <port>] [path-to-WORKFLOW.md]"

  defp wait_for_shutdown do
    case Process.whereis(SymphonyElixir.Supervisor) do
      nil -> System.halt(1)
      pid -> ref = Process.monitor(pid); receive do {:DOWN, ^ref, :process, ^pid, reason} -> System.halt(if reason == :normal, do: 0, else: 1) end
    end
  end
end
