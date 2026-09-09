defmodule SymphonyElixir.Workspace do
  @moduledoc "Task workspace boundary used by Runtime execution."

  alias SymphonyElixir.{Config, PathSafety}
  @task_identifier ~r/^T-[0-9]{6}$/

  @spec path_for_task(String.t()) :: Path.t()
  def path_for_task(identifier) when is_binary(identifier) do
    Path.join(Config.local_workspace_root(), workspace_key(identifier))
  end

  @spec workspace_key(String.t()) :: String.t()
  def workspace_key(identifier) when is_binary(identifier) do
    if Regex.match?(@task_identifier, identifier) do
      identifier
    else
      raise ArgumentError, "invalid Pilot task identifier"
    end
  end

  @spec validate(Path.t(), String.t()) :: {:ok, Path.t()} | {:error, term()}
  def validate(workspace, identifier) when is_binary(workspace) and is_binary(identifier) do
    expanded = Path.expand(workspace)
    root = Path.expand(Config.local_workspace_root())
    prefix = root <> "/"

    with :ok <- validate_identifier(identifier),
         {:ok, canonical_workspace} <- PathSafety.canonicalize(expanded),
         {:ok, canonical_root} <- PathSafety.canonicalize(root) do
      expected = path_for_task(identifier) |> Path.expand()
      cond do
        canonical_workspace == canonical_root -> {:error, :workspace_root_not_task_workspace}
        not String.starts_with?(canonical_workspace <> "/", canonical_root <> "/") -> {:error, :workspace_outside_runtime_root}
        not String.starts_with?(expanded <> "/", prefix) -> {:error, :workspace_path_escape}
        canonical_workspace != expected -> {:error, :workspace_identity_mismatch}
        true -> {:ok, canonical_workspace}
      end
    end
  end

  @spec ensure_task_workspace(map()) :: {:ok, Path.t()} | {:error, term()}
  def ensure_task_workspace(%{identifier: identifier} = task) when is_binary(identifier) do
    with :ok <- validate_identifier(identifier) do
      workspace = path_for_task(identifier)
      with :ok <- materialize_if_absent(workspace),
           {:ok, canonical} <- validate(workspace, identifier),
           :ok <- verify_repository(canonical),
           :ok <- verify_starting_state(canonical, task) do
        {:ok, canonical}
      end
    end
  end
  def ensure_task_workspace(_), do: {:error, :task_identity_missing}

  @doc false
  def verify_starting_state_for_test(workspace, task), do: verify_starting_state(workspace, task)

  defp materialize_if_absent(workspace) do
    if File.dir?(workspace) do
      :ok
    else
      File.mkdir_p!(workspace)
      case Config.settings!().workspace.materialize_command do
        [executable | arguments] ->
          case System.cmd(executable, arguments, cd: workspace, stderr_to_stdout: true) do
            {_output, 0} -> :ok
            {_output, status} -> {:error, {:workspace_materialization_failed, status}}
          end
        _ -> {:error, :workspace_materialization_not_authorized}
      end
    end
  end

  defp verify_repository(workspace) do
    expected = Config.settings!().workspace.repository_remote
    case System.cmd("git", ["remote", "get-url", "origin"], cd: workspace, stderr_to_stdout: true) do
      {remote, 0} -> if String.trim(remote) == expected, do: :ok, else: {:error, :workspace_repository_identity_mismatch}
      {_output, _status} -> {:error, :workspace_repository_identity_mismatch}
    end
  end

  defp verify_starting_state(workspace, %{expected_starting_head: expected}) when is_binary(expected) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: workspace, stderr_to_stdout: true) do
      {head, 0} ->
        if String.trim(head) != expected do
          {:error, :workspace_starting_head_mismatch}
        else
          case System.cmd("git", ["status", "--porcelain=v1", "-z", "--untracked-files=all"], cd: workspace, stderr_to_stdout: true) do
            {"", 0} -> :ok
            {_status, 0} -> {:error, :workspace_dirty}
            {_output, _status} -> {:error, :workspace_starting_state_unverifiable}
          end
        end
      {_output, _status} -> {:error, :workspace_starting_state_unverifiable}
    end
  end

  defp verify_starting_state(_workspace, _task), do: {:error, :dispatch_starting_head_missing}

  defp validate_identifier(identifier) do
    if Regex.match?(@task_identifier, identifier), do: :ok, else: {:error, :invalid_task_identifier}
  end
end
