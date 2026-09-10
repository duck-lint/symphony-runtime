defmodule SymphonyElixir.Config do
  @moduledoc "Runtime mechanics configuration; Pilot state remains authoritative."

  alias SymphonyElixir.{Workflow, WorkflowStore}

  @default_prompt """
  Execute the assigned role against the task-scoped project context. Treat the
  Pilot dispatch and capability grant as authoritative. Return one
  symphony-pilot-execution-result/v2 packet at the supplied result path.
  """

  @spec settings() :: {:ok, SymphonyElixir.Config.Schema.t()} | {:error, term()}
  def settings, do: WorkflowStore.settings()

  @spec settings!() :: SymphonyElixir.Config.Schema.t()
  def settings! do
    case settings() do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid Runtime configuration: #{inspect(reason)}"
    end
  end

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case Workflow.current() do
      {:ok, %{prompt_template: prompt}} when is_binary(prompt) and byte_size(prompt) > 0 -> prompt
      _ -> @default_prompt
    end
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    case Application.get_env(:symphony_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 -> port
      _ -> settings!().server.port
    end
  end

  @spec local_workspace_root() :: Path.t()
  def local_workspace_root do
    workflow_dir = Workflow.workflow_file_path() |> Path.expand() |> Path.dirname()
    Path.expand(settings!().workspace.root, workflow_dir)
  end

  @spec codex_runtime_settings(term(), keyword()) :: {:ok, map()}
  def codex_runtime_settings(_workspace \\ nil, _opts \\ []) do
    settings = settings!()

    {:ok,
     %{
       approval_policy: settings.codex.approval_policy,
       thread_sandbox: settings.codex.thread_sandbox,
       turn_sandbox_policy: settings.codex.turn_sandbox_policy,
       permissions_profile: nil,
       config_overrides: nil
     }}
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate!, do: WorkflowStore.force_reload()
end
