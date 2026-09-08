defmodule SymphonyElixir.PilotProjection do
  @moduledoc """
  Read-only boundary for the Pilot dispatch contract.

  This module answers only whether an already-authorized dispatch exists and
  returns its exact grant. It never chooses a role, advances lifecycle state,
  or writes Pilot state.
  """

  alias Exqlite.Sqlite3
  alias SymphonyElixir.Config.Schema

  @dispatch_schema "symphony-pilot-dispatch/v1"
  @roles ~w(PROJECT-MANAGER PLANNER IMPLEMENTER REVIEWER ADVERSARY ARCHIVIST)
  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
  @sha ~r/^[0-9a-f]{40}$/
  @max_json_bytes 128 * 1024
  @busy_timeout_ms 5_000

  # SQLite readonly mode and query_only protect the database at the storage
  # layer; the authorizer is defense in depth for every projection query.
  @read_only_actions [
    :attach, :detach, :insert, :update, :delete,
    :create_table, :drop_table, :create_index, :drop_index,
    :create_trigger, :drop_trigger, :create_view, :drop_view,
    :alter_table, :reindex, :analyze,
    :create_temp_table, :drop_temp_table, :create_temp_index, :drop_temp_index,
    :create_temp_trigger, :drop_temp_trigger, :create_temp_view, :drop_temp_view,
    :create_vtable, :drop_vtable
  ]

  defstruct [:task, :lifecycle_id, :working_round_id, :planning_attempt_id, :dispatch_id,
             :role, :expected_starting_head, :grant, :namespace, :result_path, :execution_path,
             :result_root, :write_roots]

  @type t :: %__MODULE__{}

  @spec next_dispatch(Schema.t()) :: {:ok, t() | nil} | {:error, term()}
  def next_dispatch(%Schema{} = settings) do
    path = settings.pilot.database_path
    with {:ok, row} <- read_authorized_row(path, settings.pilot.project_slug),
         {:ok, dispatch} <- load_dispatch(path, row) do
      if dispatch && File.exists?(dispatch.execution_path), do: {:ok, nil}, else: {:ok, dispatch}
    end
  end

  @doc false
  @spec validate_dispatch_packet_for_test(map(), map()) :: {:ok, map()} | {:error, term()}
  def validate_dispatch_packet_for_test(packet, row), do: validate_packet(packet, row)

  @spec workspace_id(t()) :: String.t()
  def workspace_id(%__MODULE__{task: %{identifier: identifier}}), do: identifier

  defp read_authorized_row(path, project_slug) when is_binary(path) and is_binary(project_slug) do
    with {:ok, connection} <- open_readonly(path) do
      try do
        query(connection, """
        SELECT d.id, d.task_id, d.lifecycle_id, d.working_round_id,
               d.planning_attempt_id, d.role, d.expected_starting_head,
               t.identifier, t.title, t.objective, t.state, t.branch,
               t.project_slug, t.current_head, t.base_sha, g.id, g.read_scopes_json,
               g.write_scopes_json, g.issued_at
        FROM role_dispatches d
        JOIN tasks t ON t.id = d.task_id
        JOIN capability_grants g ON g.dispatch_id = d.id AND g.task_id = d.task_id
        WHERE d.status = 'AUTHORIZED' AND t.project_slug = ?
        ORDER BY d.created_at, d.id
        LIMIT 1
        """, [project_slug])
        |> case do
          {:ok, []} -> {:ok, nil}
          {:ok, [row]} -> {:ok, row}
          {:ok, _rows} -> {:error, :pilot_projection_ambiguous}
          error -> error
        end
      after
        _ = Sqlite3.close(connection)
      end
    end
  end

  defp read_authorized_row(_path, _project_slug), do: {:error, :pilot_projection_configuration_invalid}

  defp load_dispatch(_path, nil), do: {:ok, nil}
  defp load_dispatch(path, row) do
    with {:ok, [dispatch_id, task_id, lifecycle_id, round_id, attempt_id, role, starting_head,
                identifier, title, objective, state, branch, project_slug, current_head, base_sha,
                grant_id, read_json, write_json, issued_at]} <- {:ok, row},
         :ok <- validate_uuid(dispatch_id, :dispatch_id),
         :ok <- validate_uuid(task_id, :task_id),
         :ok <- validate_uuid(lifecycle_id, :lifecycle_id),
         :ok <- validate_optional_uuid(round_id, :working_round_id),
         :ok <- validate_optional_uuid(attempt_id, :planning_attempt_id),
         :ok <- validate_role(role),
         :ok <- validate_sha(starting_head, :expected_starting_head),
         :ok <- validate_sha(base_sha, :base_sha),
         :ok <- validate_optional_sha(current_head, :current_head),
         {:ok, read_scopes} <- decode_scope_list(read_json),
         {:ok, write_scopes} <- decode_scope_list(write_json),
         :ok <- validate_grant(role, read_scopes, write_scopes),
         {:ok, namespace} <- namespace_for(path, project_slug, identifier, dispatch_id),
         {:ok, packet} <- read_json_file(Path.join(namespace, "host/dispatch.json")),
         {:ok, _} <- validate_packet(packet, %{dispatch_id: dispatch_id, task_id: task_id,
           lifecycle_id: lifecycle_id, working_round_id: round_id, planning_attempt_id: attempt_id,
           role: role, expected_starting_head: starting_head, grant_id: grant_id,
           read_scopes: read_scopes, write_scopes: write_scopes, issued_at: issued_at,
           identifier: identifier}) do
      {:ok, %__MODULE__{
        task: %{id: task_id, identifier: identifier, title: title, objective: objective,
          state: state, branch: branch, current_head: current_head, base_sha: base_sha},
        lifecycle_id: lifecycle_id, working_round_id: round_id, planning_attempt_id: attempt_id,
        dispatch_id: dispatch_id, role: role, expected_starting_head: starting_head,
        grant: %{id: grant_id, role: role, read_scopes: read_scopes, write_scopes: write_scopes,
          issued_at: issued_at}, namespace: namespace,
        result_path: Path.join(namespace, "outbox/result.json"),
        execution_path: Path.join(namespace, "host/execution.json")}}
    end
  end

  defp validate_packet(packet, row) when is_map(packet) do
    grant = Map.get(packet, "capability_grant")
    expected = %{"schema" => @dispatch_schema, "task_id" => row.task_id,
      "identifier" => row.identifier,
      "lifecycle_id" => row.lifecycle_id, "working_round_id" => row.working_round_id,
      "planning_attempt_id" => row.planning_attempt_id, "dispatch_id" => row.dispatch_id,
      "role" => row.role, "expected_starting_head" => row.expected_starting_head}
    if Enum.all?(expected, fn {key, value} -> Map.get(packet, key) == value end) and
       is_map(grant) and Map.get(grant, "id") == row.grant_id and
       Map.get(grant, "role") == row.role and
       decode_grant_fields(grant, row) do
      {:ok, packet}
    else
      {:error, :pilot_dispatch_packet_mismatch}
    end
  end
  defp validate_packet(_packet, _row), do: {:error, :pilot_dispatch_packet_invalid}

  defp decode_grant_fields(grant, row) do
    read = Map.get(grant, "read_scopes") || decode_packet_scopes(Map.get(grant, "read_scopes_json"))
    write = Map.get(grant, "write_scopes") || decode_packet_scopes(Map.get(grant, "write_scopes_json"))
    Map.get(grant, "task_id") == row.task_id and Map.get(grant, "dispatch_id") == row.dispatch_id and
      Map.get(grant, "issued_at") == row.issued_at and read == row.read_scopes and write == row.write_scopes
  end

  defp decode_packet_scopes(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, scopes} when is_list(scopes) -> scopes
      _ -> nil
    end
  end
  defp decode_packet_scopes(_), do: nil

  defp validate_grant(role, read_scopes, write_scopes) do
    cond do
      role not in @roles -> {:error, :invalid_role}
      Enum.any?(read_scopes ++ write_scopes, &git_metadata?/1) -> {:error, :grant_includes_git_metadata}
      role in ["PROJECT-MANAGER", "REVIEWER", "ADVERSARY"] and write_scopes != [] -> {:error, :non_writer_has_write_scope}
      role in ["PLANNER", "IMPLEMENTER", "ARCHIVIST"] and write_scopes == [] -> {:error, :writer_grant_is_empty}
      true -> :ok
    end
  end

  defp decode_scope_list(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, scopes} when is_list(scopes) ->
        if Enum.all?(scopes, &safe_scope?/1), do: {:ok, scopes}, else: {:error, :invalid_capability_scope}
      _ -> {:error, :invalid_capability_scope}
    end
  end
  defp decode_scope_list(_), do: {:error, :invalid_capability_scope}
  defp safe_scope?(value) when is_binary(value) and value != "" do
    not String.starts_with?(value, "/") and not String.contains?(value, ["\\", "\0"]) and
      not Enum.any?(String.split(value, "/"), &(&1 in ["", ".", ".."]))
  end
  defp safe_scope?(_), do: false
  defp git_metadata?(path), do: path == ".git" or String.starts_with?(path, ".git/")

  defp namespace_for(database_path, project_slug, identifier, dispatch_id) do
    if is_binary(project_slug) and Regex.match?(~r/^[a-z0-9][a-z0-9-]{0,63}$/, project_slug) and
       is_binary(identifier) and Regex.match?(~r/^T-[0-9]{6}$/, identifier) and
       is_binary(dispatch_id) and Regex.match?(@uuid, dispatch_id) do
      {:ok, Path.join([Path.dirname(database_path), project_slug, "lifecycle", identifier, dispatch_id])}
    else
      {:error, :invalid_dispatch_namespace}
    end
  end

  defp read_json_file(path) do
    case File.read(path) do
      {:ok, raw} when byte_size(raw) <= @max_json_bytes ->
        case Jason.decode(raw) do {:ok, value} -> {:ok, value}; _ -> {:error, :invalid_json} end
      {:ok, _} -> {:error, :json_too_large}
      {:error, reason} -> {:error, {:dispatch_file_unreadable, reason}}
    end
  end

  defp open_readonly(path) do
    case Sqlite3.open(path, mode: :readonly) do
      {:ok, connection} ->
        case configure_readonly(connection) do
          :ok -> {:ok, connection}
          {:error, reason} -> _ = Sqlite3.close(connection); {:error, {:pilot_database_readonly_setup_failed, reason}}
        end
      {:error, reason} -> {:error, {:pilot_database_open_failed, reason}}
    end
  end

  defp configure_readonly(connection) do
    with :ok <- Sqlite3.set_busy_timeout(connection, @busy_timeout_ms),
         :ok <- Sqlite3.execute(connection, "PRAGMA query_only = ON"),
         :ok <- Sqlite3.execute(connection, "PRAGMA foreign_keys = ON") do
      Sqlite3.set_authorizer(connection, @read_only_actions)
    end
  end

  defp query(connection, sql, parameters) do
    with {:ok, statement} <- Sqlite3.prepare(connection, sql),
         :ok <- Sqlite3.bind(statement, parameters) do
      try do
        case Sqlite3.fetch_all(connection, statement) do
          {:ok, rows} -> {:ok, rows}
          {:error, reason} -> {:error, {:pilot_projection_query_failed, reason}}
        end
      after
        _ = Sqlite3.release(connection, statement)
      end
    else
      {:error, reason} -> {:error, {:pilot_projection_query_failed, reason}}
    end
  end

  defp validate_uuid(value, _field) when is_binary(value) do
    if Regex.match?(@uuid, value), do: :ok, else: {:error, :invalid_identity}
  end
  defp validate_uuid(_value, _field), do: {:error, :invalid_identity}
  defp validate_optional_uuid(nil, _field), do: :ok
  defp validate_optional_uuid(value, field), do: validate_uuid(value, field)
  defp validate_role(value) when value in @roles, do: :ok
  defp validate_role(_), do: {:error, :invalid_role}
  defp validate_sha(value, _field) when is_binary(value) do
    if Regex.match?(@sha, value), do: :ok, else: {:error, :invalid_sha}
  end
  defp validate_sha(_value, _field), do: {:error, :invalid_sha}
  defp validate_optional_sha(nil, _field), do: :ok
  defp validate_optional_sha(value, field), do: validate_sha(value, field)
end
