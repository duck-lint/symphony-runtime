defmodule SymphonyElixir.AgentRunner do
  @moduledoc """
  Executes a single tracker work item in its workspace with Codex.
  """

  require Logger
  alias SymphonyElixir.Codex.AppServer
  alias SymphonyElixir.{Config, PromptBuilder, Tracker, Workspace}
  alias SymphonyElixir.Tracker.Issue

  @type worker_host :: String.t() | nil

  @doc false
  @spec continue_with_issue_for_test(Issue.t(), ([String.t()] -> term())) ::
          {:continue, Issue.t()} | {:done, Issue.t()} | {:error, term()}
  def continue_with_issue_for_test(%Issue{} = issue, issue_state_fetcher)
      when is_function(issue_state_fetcher, 1) do
    continue_with_issue?(issue, issue_state_fetcher)
  end

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(issue, codex_update_recipient \\ nil, opts \\ []) do
    # The orchestrator owns host retries so one worker lifetime never hops machines.
    worker_host = selected_worker_host(Keyword.get(opts, :worker_host), Config.settings!().worker.ssh_hosts)

    Logger.info("Starting agent run for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Agent run failed for #{issue_context(issue)}: #{inspect(reason)}")
        raise RuntimeError, "Agent run failed for #{issue_context(issue)}: #{inspect(reason)}"
    end
  end

  defp run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
    Logger.info("Starting worker attempt for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case Workspace.create_for_issue(issue, worker_host) do
      {:ok, workspace} ->
        send_worker_runtime_info(codex_update_recipient, issue, worker_host, workspace)

        try do
          with :ok <- Workspace.run_before_run_hook(workspace, issue, worker_host) do
            run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host)
          end
        after
          Workspace.run_after_run_hook(workspace, issue, worker_host)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_codex_update(recipient, %Issue{id: issue_id}, message)
       when is_binary(issue_id) and is_pid(recipient) do
    send(recipient, {:codex_worker_update, issue_id, message})
    :ok
  end

  defp send_codex_update(_recipient, _issue, _message), do: :ok

  defp send_worker_runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace)
       when is_binary(issue_id) and is_pid(recipient) and is_binary(workspace) do
    send(
      recipient,
      {:worker_runtime_info, issue_id,
       %{
         worker_host: worker_host,
         workspace_path: workspace
       }}
    )

    :ok
  end

  defp send_worker_runtime_info(_recipient, _issue, _worker_host, _workspace), do: :ok

  defp run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host) do
    max_turns = Keyword.get(opts, :max_turns, Config.settings!().agent.max_turns)
    issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issues_by_ids/1)
    dispatch = read_dispatch!(workspace)

    with {:ok, session} <-
           AppServer.start_session(
             workspace,
             worker_host: worker_host,
             role: dispatch.role,
             writable_roots: dispatch.writable_roots
           ) do
      try do
        do_run_codex_turns(session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, dispatch, 1, max_turns)
      after
        AppServer.stop_session(session)
      end
    end
  end

  defp do_run_codex_turns(app_session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, dispatch, turn_number, max_turns) do
    prompt = build_turn_prompt(issue, opts |> Keyword.put(:execution, dispatch_prompt_context(dispatch)), turn_number, max_turns)

    with {:ok, turn_session} <-
           AppServer.run_turn(
             app_session,
             prompt,
             issue,
             on_message: codex_message_handler(codex_update_recipient, issue, dispatch)
           ) do
      Logger.info("Completed agent run for #{issue_context(issue)} session_id=#{turn_session[:session_id]} workspace=#{workspace} turn=#{turn_number}/#{max_turns}")

      case continue_with_issue?(issue, issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < max_turns ->
          Logger.info("Continuing agent run for #{issue_context(refreshed_issue)} after normal turn completion turn=#{turn_number}/#{max_turns}")

          do_run_codex_turns(
            app_session,
            workspace,
            refreshed_issue,
            codex_update_recipient,
            opts,
            issue_state_fetcher,
            dispatch,
            turn_number + 1,
            max_turns
          )

        {:continue, refreshed_issue} ->
          Logger.info("Reached agent.max_turns for #{issue_context(refreshed_issue)} with issue still active; returning control to orchestrator")

          :ok

        {:done, _refreshed_issue} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_turn_prompt(issue, opts, 1, _max_turns), do: PromptBuilder.build_prompt(issue, opts)

  defp build_turn_prompt(_issue, _opts, turn_number, max_turns) do
    """
    Continuation guidance:

    - The previous Codex turn completed normally, but the tracker work item is still in an active state.
    - This is continuation turn ##{turn_number} of #{max_turns} for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """
  end

  defp continue_with_issue?(%Issue{id: issue_id} = issue, issue_state_fetcher) when is_binary(issue_id) do
    case issue_state_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if active_issue_state?(refreshed_issue.state) and issue_routable?(refreshed_issue) do
          {:continue, refreshed_issue}
        else
          {:done, refreshed_issue}
        end

      {:ok, []} ->
        {:done, issue}

      {:error, reason} ->
        {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  defp continue_with_issue?(issue, _issue_state_fetcher), do: {:done, issue}

  defp active_issue_state?(state_name) when is_binary(state_name) do
    normalized_state = normalize_issue_state(state_name)

    Config.settings!().tracker.active_states
    |> Enum.any?(fn active_state -> normalize_issue_state(active_state) == normalized_state end)
  end

  defp active_issue_state?(_state_name), do: false

  defp issue_routable?(%Issue{} = issue) do
    Issue.routable?(issue, Config.settings!().tracker.required_labels)
  end

  defp selected_worker_host(nil, []), do: nil

  defp selected_worker_host(preferred_host, configured_hosts) when is_list(configured_hosts) do
    hosts =
      configured_hosts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case preferred_host do
      host when is_binary(host) and host != "" -> host
      _ when hosts == [] -> nil
      _ -> List.first(hosts)
    end
  end

  defp worker_host_for_log(nil), do: "local"
  defp worker_host_for_log(worker_host), do: worker_host

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp issue_context(%Issue{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end

  defp read_dispatch!(workspace) do
    marker_path = Path.join(workspace, ".git/symphony-preparation.json")

    with {:ok, raw} <- File.read(marker_path),
         {:ok, marker} when is_map(marker) <- Jason.decode(raw),
         role when is_binary(role) <- Map.get(marker, "dispatch_role"),
         role_run_id when is_binary(role_run_id) <- Map.get(marker, "role_run_id"),
         namespace when is_binary(namespace) <- Map.get(marker, "lifecycle_namespace") do
      writable_roots =
        marker
        |> Map.get("writable_roots", nil)
        |> case do
          roots when is_list(roots) -> roots
          _ ->
            case File.read(Path.join(namespace, "inbox/lifecycle.json")) do
              {:ok, packet_raw} ->
                with {:ok, packet} when is_map(packet) <- Jason.decode(packet_raw),
                     %{"writable_roots" => roots} when is_list(roots) <- Map.get(packet, "dispatch", %{}) do
                  roots
                else
                  _ -> []
                end

              _ -> []
            end
        end

      if writable_roots == [] do
        raise RuntimeError, "role dispatch has no writable outbox root"
      end

      %{role: role, role_run_id: role_run_id, namespace: namespace, writable_roots: writable_roots}
    else
      _ -> raise RuntimeError, "role dispatch marker is missing or malformed"
    end
  end

  defp dispatch_prompt_context(dispatch) do
    %{role: dispatch.role, role_run_id: dispatch.role_run_id,
      input_path: Path.join(dispatch.namespace, "inbox/lifecycle.json"),
      result_path: Path.join(dispatch.namespace, "outbox/result.json")}
  end

  defp codex_message_handler(recipient, issue, dispatch) do
    fn message ->
      persist_execution_receipt(dispatch, message)
      send_codex_update(recipient, issue, message)
    end
  end

  defp persist_execution_receipt(dispatch, %{event: event} = message)
       when event in [:session_started, :turn_completed, :turn_failed, :turn_cancelled, :turn_ended_with_error] do
    receipt_path = Path.join(dispatch.namespace, "outbox/execution.json")
    existing =
      case File.read(receipt_path) do
        {:ok, raw} ->
          case Jason.decode(raw) do
            {:ok, value} when is_map(value) -> value
            _ -> %{}
          end

        _ -> %{}
      end

    status = if event == :session_started, do: "started", else: if(event == :turn_completed, do: "finished", else: "failed")
    receipt =
      existing
      |> Map.merge(%{"schema" => "symphony-runtime-execution/v1", "role" => dispatch.role, "role_run_id" => dispatch.role_run_id, "status" => status})
      |> Map.put_new("started_at", DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put("finished_at", if(status == "started", do: Map.get(existing, "finished_at"), else: DateTime.utc_now() |> DateTime.to_iso8601()))
      |> maybe_put_message_identity(message)

    File.write!(receipt_path, Jason.encode!(receipt))
  end

  defp persist_execution_receipt(_dispatch, _message), do: :ok

  defp maybe_put_message_identity(receipt, message) do
    Enum.reduce([:session_id, :thread_id, :turn_id], receipt, fn key, acc ->
      case Map.get(message, key) do
        nil -> acc
        value -> Map.put(acc, Atom.to_string(key), value)
      end
    end)
  end
end
