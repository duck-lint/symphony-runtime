defmodule SymphonyElixir.Workspace do
  @moduledoc """Task workspace boundary used by Runtime execution."""

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
  def ensure_task_workspace(%{identifier: identifier}) when is_binary(identifier) do
    with :ok <- validate_identifier(identifier) do
      workspace = path_for_task(identifier)
      if File.dir?(workspace), do: validate(workspace, identifier), else: {:error, :task_workspace_missing}
    end
  end
  def ensure_task_workspace(_), do: {:error, :task_identity_missing}

  defp validate_identifier(identifier) do
    if Regex.match?(@task_identifier, identifier), do: :ok, else: {:error, :invalid_task_identifier}
  end
end
