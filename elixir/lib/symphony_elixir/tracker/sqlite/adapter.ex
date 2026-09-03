defmodule SymphonyElixir.Tracker.SQLite.Adapter do
  @moduledoc """
  Read-only adapter for the host-owned `symphony-pilot` control database.

  Pilot owns the schema and all writes. This adapter opens one connection per
  read with SQLite's readonly flag, validates the small v1 contract it
  consumes, and never exposes the connection to the agent or orchestrator.
  """

  @behaviour SymphonyElixir.Tracker

  alias Exqlite.Sqlite3
  alias SymphonyElixir.Config
  alias SymphonyElixir.Tracker.Issue

  @schema_version 1
  @migration_identity "control-plane-v1"
  @busy_timeout_ms 5_000
  @project_slug_pattern ~r/^[a-z0-9][a-z0-9-]{0,63}$/

  @required_columns [
    {"schema_migrations", ~w(version identity)},
    {"tasks", ~w(id identifier project_slug title objective state branch created_at updated_at)},
    {"blockers", ~w(task_id kind status)}
  ]

  # This is defense in depth over SQLite's `:readonly` open mode and
  # `query_only` connection setting. PRAGMA remains allowed because contract
  # validation reads user_version and table metadata without changing the DB.
  @read_only_actions [
    :attach,
    :detach,
    :insert,
    :update,
    :delete,
    :create_table,
    :drop_table,
    :create_index,
    :drop_index,
    :create_trigger,
    :drop_trigger,
    :create_view,
    :drop_view,
    :alter_table,
    :reindex,
    :analyze,
    :create_temp_table,
    :drop_temp_table,
    :create_temp_index,
    :drop_temp_index,
    :create_temp_trigger,
    :drop_temp_trigger,
    :create_temp_view,
    :drop_temp_view,
    :create_vtable,
    :drop_vtable
  ]

  @task_select """
    SELECT
      tasks.id,
      tasks.identifier,
      tasks.title,
      tasks.objective,
      tasks.state,
      tasks.branch,
      tasks.created_at,
      tasks.updated_at,
      EXISTS(
        SELECT 1 FROM blockers
        WHERE blockers.task_id = tasks.id AND blockers.status = 'open'
      ) AS has_open_blocker
    FROM tasks
  """

  @spec validate_config(map()) :: :ok | {:error, term()}
  def validate_config(tracker_settings) do
    with :ok <- validate_settings_shape(tracker_settings) do
      validate_open_connection(tracker_settings)
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(states) when is_list(states) do
    fetch_issues_by_states(states, Config.settings!().tracker)
  end

  @doc false
  @spec fetch_issues_by_states_for_test([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states_for_test(states, tracker_settings)
      when is_list(states) and is_map(tracker_settings) do
    fetch_issues_by_states(states, tracker_settings)
  end

  @spec fetch_issues_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_ids(ids) when is_list(ids) do
    fetch_issues_by_ids(ids, Config.settings!().tracker)
  end

  @doc false
  @spec fetch_issues_by_ids_for_test([String.t()], map()) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_ids_for_test(ids, tracker_settings)
      when is_list(ids) and is_map(tracker_settings) do
    fetch_issues_by_ids(ids, tracker_settings)
  end

  @doc false
  @spec with_validated_connection_for_test(map(), (reference() -> term()), (reference() -> term())) ::
          term()
  def with_validated_connection_for_test(tracker_settings, function, on_open)
      when is_map(tracker_settings) and is_function(function, 1) and is_function(on_open, 1) do
    with_validated_connection(tracker_settings, function, on_open)
  end

  @doc false
  @spec open_readonly_for_test(String.t(), (reference() -> :ok | {:error, term()})) ::
          {:ok, reference()} | {:error, term()}
  def open_readonly_for_test(path, configure) when is_binary(path) and is_function(configure, 1) do
    open_readonly(path, configure)
  end

  @doc false
  @spec validate_required_columns_for_test(reference()) :: :ok | {:error, term()}
  def validate_required_columns_for_test(connection), do: validate_required_columns(connection)

  @doc false
  @spec query_for_test(reference(), String.t(), list()) :: {:ok, list()} | {:error, term()}
  def query_for_test(connection, sql, parameters) when is_binary(sql) and is_list(parameters) do
    query(connection, sql, parameters)
  end

  @doc false
  @spec normalize_row_for_test(list()) :: {:ok, Issue.t()} | {:error, term()}
  def normalize_row_for_test(row) when is_list(row), do: normalize_row(row)

  @spec agent_tool_specs() :: [map()]
  def agent_tool_specs, do: []

  @spec secret_environment_names(map()) :: [String.t()]
  def secret_environment_names(_tracker_settings), do: []

  defp fetch_issues_by_states(states, tracker_settings) do
    case normalize_states(states) do
      {:ok, normalized_states} ->
        with_validated_connection(tracker_settings, fn connection ->
          fetch_by_states(connection, tracker_settings.project_slug, normalized_states)
        end)

      error ->
        error
    end
  end

  defp fetch_issues_by_ids(ids, tracker_settings) do
    case validate_issue_ids(ids) do
      :ok ->
        with_validated_connection(tracker_settings, fn connection ->
          fetch_by_ids(connection, tracker_settings.project_slug, Enum.uniq(ids))
        end)

      error ->
        error
    end
  end

  defp fetch_by_states(_connection, _project_slug, []), do: {:ok, []}

  defp fetch_by_states(connection, project_slug, states) do
    placeholders = Enum.map_join(states, ", ", fn _state -> "?" end)
    sql = @task_select <> " WHERE tasks.project_slug = ? AND tasks.state IN (" <> placeholders <> ") ORDER BY tasks.identifier"

    with {:ok, rows} <- query(connection, sql, [project_slug | states]) do
      normalize_rows(rows)
    end
  end

  defp fetch_by_ids(_connection, _project_slug, []), do: {:ok, []}

  defp fetch_by_ids(connection, project_slug, ids) do
    placeholders = Enum.map_join(ids, ", ", fn _id -> "?" end)
    sql = @task_select <> " WHERE tasks.project_slug = ? AND tasks.id IN (" <> placeholders <> ") ORDER BY tasks.identifier"

    with {:ok, rows} <- query(connection, sql, [project_slug | ids]) do
      normalize_rows(rows)
    end
  end

  defp validate_settings_shape(tracker_settings) do
    case validate_project_slug(Map.get(tracker_settings, :project_slug)) do
      :ok -> validate_database_path(Map.get(tracker_settings, :database_path))
      error -> error
    end
  end

  defp validate_open_connection(tracker_settings) do
    case with_validated_connection(tracker_settings, fn _connection -> :ok end) do
      :ok -> :ok
      error -> error
    end
  end

  defp validate_project_slug(value) when is_binary(value) do
    if Regex.match?(@project_slug_pattern, value) do
      :ok
    else
      {:error, :invalid_sqlite_project_slug}
    end
  end

  defp validate_project_slug(_value), do: {:error, :missing_sqlite_project_slug}

  defp validate_database_path(value) when is_binary(value) do
    cond do
      String.trim(value) == "" ->
        {:error, :missing_sqlite_database_path}

      Path.type(value) != :absolute ->
        {:error, :sqlite_database_path_must_be_absolute}

      true ->
        case File.lstat(value) do
          {:ok, %File.Stat{type: :regular}} -> :ok
          {:ok, %File.Stat{type: type}} -> {:error, {:sqlite_database_not_regular, type}}
          {:error, :enoent} -> {:error, :sqlite_database_missing}
          {:error, reason} -> {:error, {:sqlite_database_inaccessible, reason}}
        end
    end
  end

  defp validate_database_path(_value), do: {:error, :missing_sqlite_database_path}

  defp validate_issue_ids(ids) do
    if Enum.all?(ids, &is_binary/1) do
      :ok
    else
      {:error, :invalid_sqlite_issue_ids}
    end
  end

  defp normalize_states(states) do
    normalized = Enum.map(states, &normalize_state/1)

    if Enum.all?(normalized, &is_binary/1) do
      {:ok, Enum.uniq(normalized)}
    else
      {:error, :invalid_sqlite_states}
    end
  end

  defp normalize_state(value) when is_binary(value), do: String.upcase(String.trim(value))
  defp normalize_state(_value), do: nil

  defp with_validated_connection(tracker_settings, function),
    do: with_validated_connection(tracker_settings, function, fn _connection -> :ok end)

  defp with_validated_connection(tracker_settings, function, on_open) do
    with :ok <- validate_settings_shape(tracker_settings),
         {:ok, connection} <- open_readonly(tracker_settings.database_path) do
      # The close bracket begins immediately after open succeeds. This keeps
      # failed contract validation and callback exceptions from leaking NIF
      # connections during polling or workflow reload.
      try do
        on_open.(connection)

        case validate_schema(connection) do
          :ok -> function.(connection)
          error -> error
        end
      after
        _ = Sqlite3.close(connection)
      end
    end
  end

  @spec open_readonly(String.t()) :: {:ok, reference()} | {:error, term()}
  defp open_readonly(path), do: open_readonly(path, &configure_readonly/1)

  defp open_readonly(path, configure) do
    case Sqlite3.open(path, mode: :readonly) do
      {:ok, connection} ->
        case configure.(connection) do
          :ok ->
            {:ok, connection}

          {:error, reason} ->
            _ = Sqlite3.close(connection)
            {:error, {:sqlite_open_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:sqlite_open_failed, reason}}
    end
  end

  defp configure_readonly(connection) do
    with :ok <- Sqlite3.set_busy_timeout(connection, @busy_timeout_ms),
         :ok <- Sqlite3.execute(connection, "PRAGMA query_only = ON"),
         :ok <- Sqlite3.execute(connection, "PRAGMA foreign_keys = ON") do
      Sqlite3.set_authorizer(connection, @read_only_actions)
    end
  end

  defp validate_schema(connection) do
    with {:ok, [[version]]} <- query(connection, "PRAGMA user_version", []),
         :ok <- validate_version(version),
         {:ok, migration_rows} <-
           query(connection, "SELECT version, identity FROM schema_migrations ORDER BY version", []),
         :ok <- validate_migration_identity(migration_rows),
         :ok <- validate_required_columns(connection) do
      :ok
    else
      {:error, {:sqlite_query_failed, _reason} = error} -> error
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_version(@schema_version), do: :ok

  defp validate_version(version) when is_integer(version) and version > @schema_version do
    {:error, {:sqlite_unsupported_schema_version, version}}
  end

  defp validate_version(version), do: {:error, {:sqlite_incompatible_schema_version, version}}

  defp validate_migration_identity([[@schema_version, @migration_identity]]), do: :ok

  defp validate_migration_identity(rows), do: {:error, {:sqlite_invalid_migration_identity, rows}}

  defp validate_required_columns(connection) do
    Enum.reduce_while(@required_columns, :ok, fn {table, required}, :ok ->
      case query(connection, "PRAGMA table_info(" <> table <> ")", []) do
        {:ok, rows} ->
          validate_columns(table, required, rows)

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_columns(table, required, rows) do
    columns = Enum.map(rows, &Enum.at(&1, 1))
    missing = required -- columns

    if missing == [] do
      {:cont, :ok}
    else
      {:halt, {:error, {:sqlite_incompatible_schema, {:missing_columns, table, missing}}}}
    end
  end

  defp query(connection, sql, parameters) do
    case Sqlite3.prepare(connection, sql) do
      {:ok, statement} ->
        try do
          with :ok <- Sqlite3.bind(statement, parameters) do
            case Sqlite3.fetch_all(connection, statement) do
              {:ok, rows} -> {:ok, rows}
              {:error, reason} -> {:error, {:sqlite_query_failed, reason}}
            end
          end
        after
          _ = Sqlite3.release(connection, statement)
        end

      {:error, reason} ->
        {:error, {:sqlite_query_failed, reason}}
    end
  end

  defp normalize_rows(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, issues} ->
      case normalize_row(row) do
        {:ok, issue} -> {:cont, {:ok, [issue | issues]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, issues} -> {:ok, Enum.reverse(issues)}
      error -> error
    end
  end

  defp normalize_row([
         id,
         identifier,
         title,
         objective,
         state,
         branch,
         created_at,
         updated_at,
         has_open_blocker
       ]) do
    with :ok <- required_text(id, :id),
         :ok <- required_text(identifier, :identifier),
         :ok <- required_text(title, :title),
         :ok <- required_text(objective, :objective),
         :ok <- required_text(state, :state),
         :ok <- required_text(branch, :branch),
         {:ok, created_at} <- parse_timestamp(created_at, :created_at),
         {:ok, updated_at} <- parse_timestamp(updated_at, :updated_at) do
      {:ok,
       %Issue{
         id: id,
         identifier: identifier,
         title: title,
         description: objective,
         state: state,
         branch_name: branch,
         created_at: created_at,
         updated_at: updated_at,
         labels: [],
         native_ref: nil,
         assignee_id: nil,
         priority: nil,
         url: nil,
         blocked_by: [],
         dispatchable: dispatchable?(state, has_open_blocker)
       }}
    end
  end

  defp normalize_row(row), do: {:error, {:sqlite_invalid_task_row, row}}

  defp required_text(value, _field) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp required_text(_value, field), do: {:error, {:sqlite_invalid_task_row, {:missing, field}}}

  defp parse_timestamp(value, _field) when not is_binary(value), do: {:error, {:sqlite_malformed_timestamp, value}}

  defp parse_timestamp(value, field) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> {:ok, timestamp}
      {:error, _reason} -> {:error, {:sqlite_malformed_timestamp, field}}
    end
  end

  defp dispatchable?("QUEUED", 0), do: true
  defp dispatchable?(_state, _has_open_blocker), do: false
end
