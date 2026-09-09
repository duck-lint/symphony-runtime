defmodule SymphonyElixir.Config do
  @moduledoc "Runtime mechanics configuration; Pilot state remains authoritative."

  alias SymphonyElixir.{Workflow, WorkflowStore}

  @default_prompt """
  Execute the assigned role against the task-scoped project context. Treat the
  Pilot dispatch and capability grant as authoritative. Return one
  symphony-pilot-execution-result/v2 packet at the supplied result path.
  """

  def settings, do: WorkflowStore.settings()
  def settings! do
    case settings() do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid Runtime configuration: #{inspect(reason)}"
    end
  end

  def workflow_prompt do
    case Workflow.current() do
      {:ok, %{prompt_template: prompt}} when is_binary(prompt) and byte_size(prompt) > 0 -> prompt
      _ -> @default_prompt
    end
  end

  def server_port do
    case Application.get_env(:symphony_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 -> port
      _ -> settings!().server.port
    end
  end

  def local_workspace_root do
    workflow_dir = Workflow.workflow_file_path() |> Path.expand() |> Path.dirname()
    Path.expand(settings!().workspace.root, workflow_dir)
  end

  def codex_runtime_settings(_workspace \\ nil, _opts \\ []) do
    settings = settings!()
    {:ok, %{approval_policy: settings.codex.approval_policy, thread_sandbox: settings.codex.thread_sandbox,
      turn_sandbox_policy: settings.codex.turn_sandbox_policy, permissions_profile: nil, config_overrides: nil}}
  end

  def validate!, do: WorkflowStore.force_reload()

end
