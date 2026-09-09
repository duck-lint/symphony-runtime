defmodule SymphonyElixir.AgentRunner do
  @moduledoc "Runs exactly one Pilot-authorized execution and emits host evidence."

  require Logger
  alias SymphonyElixir.{Codex.AppServer, Config, PilotProjection, PMContinuity, PromptBuilder, Workspace}

  @roles ~w(PROJECT-MANAGER PLANNER IMPLEMENTER REVIEWER ADVERSARY ARCHIVIST)

  @spec run(PilotProjection.t(), pid() | nil, keyword()) :: :ok | {:error, term()}
  def run(%PilotProjection{} = dispatch, update_recipient \\ nil, opts \\ []) do
    task = Map.put(dispatch.task, :expected_starting_head, dispatch.expected_starting_head)

    with {:ok, workspace} <- Workspace.ensure_task_workspace(task),
         {:ok, execution} <- prepare_execution(dispatch, workspace),
         {:ok, session} <-
           AppServer.start_session(workspace,
             execution: execution,
             developer_instructions: Keyword.get(opts, :developer_instructions)
           ) do
      try do
        with :ok <- write_launch_evidence(execution, session, workspace),
             :ok <- reconcile_with_pilot(execution, workspace, "started"),
             :ok <- notify_launch(update_recipient, execution, session),
             result <- run_turn(session, execution, workspace, update_recipient, opts),
             :ok <- finish_execution(session, execution, workspace, result),
             :ok <- reconcile_with_pilot(execution, workspace, "terminated") do
          if execution.role == "PROJECT-MANAGER" and match?({:ok, _}, result) do
            PMContinuity.record(execution.task.id, result)
          end

          :ok
        else
          {:error, reason} ->
            Logger.error("Pilot-authorized execution failed: #{inspect(reason)}")
            {:error, reason}
        end
      after
        AppServer.stop_session(session)
      end
    else
      {:error, reason} ->
        Logger.error("Pilot-authorized execution failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def run(_dispatch, _recipient, _opts), do: {:error, :pilot_dispatch_required}

  @doc false
  @spec parse_porcelain_z_for_test(binary()) :: {:ok, [String.t()]} | {:error, term()}
  def parse_porcelain_z_for_test(raw), do: parse_porcelain_z(raw)

  defp prepare_execution(%PilotProjection{} = dispatch, workspace) do
    if dispatch.role not in @roles do
      {:error, :invalid_pilot_role}
    else
      {:ok, %{dispatch | result_root: dispatch.result_path, write_roots: Enum.map(dispatch.grant.write_scopes, &Path.join(workspace, &1))}}
    end
  end

  defp run_turn(session, execution, workspace, recipient, opts) do
    prompt = PromptBuilder.build(execution) <> PMContinuity.prompt_suffix(execution.task.id, execution.role)

    AppServer.run_turn(session, prompt, execution.task,
      on_message: message_handler(recipient, execution, workspace),
      tool_executor: fn _tool, _arguments ->
        %{"success" => false, "output" => "tool_not_authorized", "contentItems" => []}
      end,
      auto_approve_requests: Keyword.get(opts, :auto_approve_requests, false)
    )
  end

  defp write_launch_evidence(execution, session, workspace) do
    started_at = DateTime.utc_now() |> DateTime.to_iso8601()
    Process.put({__MODULE__, execution.dispatch_id, :started_at}, started_at)

    with {:ok, head} <- git_head(workspace),
         {:ok, paths} <- changed_paths(workspace) do
      evidence = %{
        "phase" => "started",
        "runtime_execution_id" => runtime_execution_id(execution),
        "task_id" => execution.task.id,
        "lifecycle_id" => execution.lifecycle_id,
        "working_round_id" => execution.working_round_id,
        "planning_attempt_id" => execution.planning_attempt_id,
        "dispatch_id" => execution.dispatch_id,
        "observed_role" => execution.role,
        "status" => "running",
        "started_at" => started_at,
        "starting_head" => execution.expected_starting_head,
        "head_sha" => head,
        "changed_paths" => paths,
        "dirty" => paths != [],
        "runtime_process_id" => Map.get(session.metadata, :codex_app_server_pid),
        "app_server_thread_id" => session.thread_id
      }

      write_json(execution.execution_path, evidence)
    end
  end

  defp notify_launch(recipient, execution, session) do
    if is_pid(recipient) do
      send(
        recipient,
        {:runtime_execution_update, execution.dispatch_id,
         %{event: :execution_started, runtime_execution_id: runtime_execution_id(execution), session_id: session.thread_id, codex_app_server_pid: Map.get(session.metadata, :codex_app_server_pid)}}
      )
    end

    :ok
  end

  defp reconcile_with_pilot(execution, workspace, phase) do
    case Config.settings!().pilot.reconcile_command do
      [executable | arguments] ->
        command = arguments ++ ["--workspace", workspace, "--task-id", execution.task.id, "--dispatch-id", execution.dispatch_id, "--phase", phase]

        case System.cmd(executable, command, stderr_to_stdout: true) do
          {output, 0} ->
            case Jason.decode(String.trim(output)) do
              {:ok, %{"acknowledged" => true, "dispatch_id" => dispatch_id, "phase" => ^phase}} ->
                if dispatch_id == execution.dispatch_id, do: :ok, else: {:error, {:pilot_reconciliation_identity_mismatch, phase}}

              _ ->
                {:error, {:pilot_reconciliation_not_acknowledged, phase}}
            end

          {_output, status} ->
            {:error, {:pilot_reconciliation_rejected, phase, status}}
        end

      _ ->
        {:error, :pilot_reconciliation_not_configured}
    end
  end

  defp finish_execution(session, execution, workspace, result) do
    status = if match?({:ok, _}, result), do: "finished", else: "failed"

    try do
      AppServer.stop_session(session)

      with {:ok, head} <- git_head(workspace),
           {:ok, paths} <- changed_paths(workspace) do
        evidence = %{
          "phase" => "terminated",
          "runtime_execution_id" => runtime_execution_id(execution),
          "task_id" => execution.task.id,
          "lifecycle_id" => execution.lifecycle_id,
          "working_round_id" => execution.working_round_id,
          "planning_attempt_id" => execution.planning_attempt_id,
          "dispatch_id" => execution.dispatch_id,
          "observed_role" => execution.role,
          "status" => status,
          "started_at" => launch_started_at(execution),
          "finished_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "starting_head" => execution.expected_starting_head,
          "head_sha" => head,
          "changed_paths" => paths,
          "dirty" => paths != [],
          "runtime_process_id" => Map.get(session.metadata, :codex_app_server_pid),
          "app_server_thread_id" => session.thread_id,
          "summary" => result_summary(result)
        }

        write_json(execution.execution_path, evidence)
      end
    rescue
      error -> {:error, {:execution_cleanup_failed, error}}
    end
  end

  defp message_handler(recipient, execution, workspace) do
    fn message ->
      if is_pid(recipient), do: send(recipient, {:runtime_execution_update, execution.dispatch_id, message})
      if message[:event] in [:turn_completed, :turn_ended_with_error], do: Logger.debug("Runtime observed terminal App Server event workspace=#{workspace}")
    end
  end

  defp runtime_execution_id(execution) do
    case Process.get({__MODULE__, execution.dispatch_id}) do
      nil ->
        value = "runtime-" <> Ecto.UUID.generate()
        Process.put({__MODULE__, execution.dispatch_id}, value)
        value

      value ->
        value
    end
  end

  defp launch_started_at(execution), do: Process.get({__MODULE__, execution.dispatch_id, :started_at}) || DateTime.utc_now() |> DateTime.to_iso8601()

  defp write_json(path, value) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(value, pretty: true) <> "\n")
    :ok
  end

  defp git_head(workspace) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: workspace, stderr_to_stdout: true) do
      {head, 0} -> {:ok, String.trim(head)}
      {_output, status} -> {:error, {:git_head_failed, status}}
    end
  end

  defp changed_paths(workspace) do
    case System.cmd("git", ["status", "--porcelain=v1", "-z", "--untracked-files=all"], cd: workspace, stderr_to_stdout: true) do
      {raw, 0} ->
        parse_porcelain_z(raw)

      {_output, status} ->
        {:error, {:git_status_failed, status}}
    end
  end

  defp parse_porcelain_z(raw) when is_binary(raw) do
    records = String.split(raw, <<0>>, trim: true)
    parse_status_records(records, [])
  end

  defp parse_porcelain_z(_), do: {:error, :porcelain_output_invalid}

  defp parse_status_records([], paths), do: {:ok, paths |> Enum.uniq() |> Enum.sort()}

  defp parse_status_records([record | rest], paths) when byte_size(record) >= 4 do
    status = binary_part(record, 0, 2)
    path = binary_part(record, 3, byte_size(record) - 3)

    if path == "" or String.contains?(path, <<0>>) do
      {:error, :porcelain_path_invalid}
    else
      rename? = String.at(status, 0) in ["R", "C"] or String.at(status, 1) in ["R", "C"]

      if rename? and rest == [] do
        {:error, :porcelain_rename_missing_source}
      else
        {extra, remaining} = if rename?, do: {hd(rest), tl(rest)}, else: {nil, rest}
        if rename? and extra == "", do: {:error, :porcelain_rename_empty_source}, else: parse_status_records(remaining, [path, extra | paths] |> Enum.reject(&is_nil/1))
      end
    end
  end

  defp parse_status_records(_records, _paths), do: {:error, :porcelain_record_invalid}

  defp result_summary({:ok, %{result: result}}), do: inspect(result, limit: 20, printable_limit: 2_000)
  defp result_summary({:error, reason}), do: inspect(reason, limit: 20, printable_limit: 2_000)
  defp result_summary(other), do: inspect(other, limit: 20, printable_limit: 2_000)
end
