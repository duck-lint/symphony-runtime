defmodule SymphonyElixir.SQLiteAdapterTest do
  use SymphonyElixir.TestSupport

  alias Exqlite.Sqlite3
  alias SymphonyElixir.Tracker.SQLite.Adapter

  @alpha_queued "11111111-1111-1111-1111-111111111111"
  @beta_queued "22222222-2222-2222-2222-222222222222"
  @alpha_human_blocked "33333333-3333-3333-3333-333333333333"
  @alpha_ready "44444444-4444-4444-4444-444444444444"
  @alpha_project_blocked "55555555-5555-5555-5555-555555555555"

  test "sqlite selects through the existing tracker boundary and binds no tools or secrets" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "sqlite",
      tracker_database_path: fixture_path(),
      tracker_project_slug: "alpha",
      tracker_active_states: ["QUEUED"],
      tracker_terminal_states: ["READY_FOR_HUMAN_MERGE"]
    )

    assert {:ok, SymphonyElixir.Tracker.SQLite.Adapter} = Tracker.adapter_for_kind("sqlite")
    assert :ok = Config.validate!()
    assert Tracker.adapter() == SymphonyElixir.Tracker.SQLite.Adapter

    binding = Tracker.bind_agent_tools()
    assert binding.tool_specs == []
    assert binding.secret_environment_names == []

    response = Tracker.execute_bound_agent_tool(binding, "sqlite_query", %{}, [])
    refute response["success"]
    assert response["output"] =~ "Unsupported dynamic tool"
  end

  test "accepted pilot fixture maps local tasks and filters every state read by project" do
    settings = settings()
    assert :ok = Adapter.validate_config(settings)

    assert {:ok, queued} = Adapter.fetch_issues_by_states_for_test(["QUEUED"], settings)
    assert Enum.map(queued, & &1.id) == [@alpha_queued, @alpha_project_blocked]

    alpha_issue = hd(queued)
    assert alpha_issue.id == @alpha_queued
    assert alpha_issue.identifier == "T-000001"
    assert alpha_issue.title == "Alpha queued"
    assert alpha_issue.description == "Objective for Alpha queued"
    assert alpha_issue.state == "QUEUED"
    assert alpha_issue.branch_name == "codex/alpha-11111111"
    assert alpha_issue.native_ref == nil
    assert alpha_issue.assignee_id == nil
    assert alpha_issue.priority == nil
    assert alpha_issue.url == nil
    assert alpha_issue.labels == []
    assert alpha_issue.blocked_by == []
    assert alpha_issue.dispatchable
    assert DateTime.to_iso8601(alpha_issue.created_at) == "2026-09-01T12:00:00Z"
    assert DateTime.to_iso8601(alpha_issue.updated_at) == "2026-09-01T12:00:00Z"

    project_blocked = Enum.find(queued, &(&1.id == @alpha_project_blocked))
    refute project_blocked.dispatchable

    assert {:ok, [human_blocked]} =
             Adapter.fetch_issues_by_states_for_test(["HUMAN_BLOCKED"], settings)

    assert human_blocked.id == @alpha_human_blocked
    refute human_blocked.dispatchable

    assert {:ok, [ready]} = Adapter.fetch_issues_by_states_for_test(["READY_FOR_HUMAN_MERGE"], settings)
    assert ready.id == @alpha_ready
    refute ready.dispatchable

    assert {:ok, []} = Adapter.fetch_issues_by_states_for_test([], settings)
    refute Enum.any?(queued, &(&1.id == @beta_queued))
  end

  test "adapter routing is blocker-only for every lifecycle state" do
    for state <- [
          "QUEUED",
          "PLANNED",
          "IMPLEMENTED",
          "REVIEW",
          "ADVERSARIAL_REVIEW",
          "FINAL_MECHANICAL_ACCEPTANCE",
          "ARCHIVIST"
        ] do
      assert {:ok, %Issue{state: ^state, dispatchable: true}} =
               Adapter.normalize_row_for_test([
                 "11111111-1111-1111-1111-111111111111",
                 "T-000001",
                 "title",
                 "objective",
                 state,
                 "codex/task",
                 "2026-09-01T12:00:00Z",
                 "2026-09-01T12:00:00Z",
                 0
               ])

      assert {:ok, %Issue{state: ^state, dispatchable: false}} =
               Adapter.normalize_row_for_test([
                 "11111111-1111-1111-1111-111111111111",
                 "T-000001",
                 "title",
                 "objective",
                 state,
                 "codex/task",
                 "2026-09-01T12:00:00Z",
                 "2026-09-01T12:00:00Z",
                 1
               ])
    end
  end

  test "public tracker callbacks use the configured SQLite tracker" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "sqlite",
      tracker_database_path: fixture_path(),
      tracker_project_slug: "alpha",
      tracker_active_states: ["QUEUED"],
      tracker_terminal_states: ["READY_FOR_HUMAN_MERGE"]
    )

    assert {:ok, [%{id: @alpha_queued}, %{id: @alpha_project_blocked}]} =
             Adapter.fetch_issues_by_states(["QUEUED"])

    assert {:ok, [%{id: @alpha_queued}]} = Adapter.fetch_issues_by_ids([@alpha_queued])
  end

  test "id reads use local task UUIDs and cannot leak another project" do
    settings = settings()

    assert {:ok, issues} =
             Adapter.fetch_issues_by_ids_for_test(
               [@beta_queued, @alpha_queued, "99999999-9999-9999-9999-999999999999"],
               settings
             )

    assert Enum.map(issues, & &1.id) == [@alpha_queued]
  end

  test "invalid state and id inputs fail closed and empty id reads stay empty" do
    settings = settings()

    assert {:error, :invalid_sqlite_states} =
             Adapter.fetch_issues_by_states_for_test(["QUEUED", 42], settings)

    assert {:error, :invalid_sqlite_issue_ids} =
             Adapter.fetch_issues_by_ids_for_test([42], settings)

    assert {:ok, []} = Adapter.fetch_issues_by_ids_for_test([], settings)
  end

  test "read-only configuration and fetches do not mutate the pilot-produced fixture" do
    settings = settings()
    before = File.read!(fixture_path())
    before_hash = :crypto.hash(:sha256, before)
    assert :ok = Adapter.validate_config(settings)
    assert {:ok, _issues} = Adapter.fetch_issues_by_states_for_test(["QUEUED"], settings)
    assert File.read!(fixture_path()) == before
    assert :crypto.hash(:sha256, File.read!(fixture_path())) == before_hash

    # A WAL database may acquire SQLite's shared-memory index while a
    # readonly reader is attached. That is SQLite read coordination state,
    # not a write to the authoritative database or WAL contents.
    if File.exists?(fixture_path() <> "-wal") do
      assert File.stat!(fixture_path() <> "-wal").size == 0
    end
  end

  test "missing, non-regular, and malformed configuration fails closed without creating a database" do
    missing = Path.join(System.tmp_dir!(), "symphony-missing-#{System.unique_integer([:positive])}.sqlite3")
    refute File.exists?(missing)
    assert {:error, :sqlite_database_missing} = Adapter.validate_config(settings(database_path: missing))
    refute File.exists?(missing)

    directory = Path.join(System.tmp_dir!(), "symphony-directory-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    assert {:error, {:sqlite_database_not_regular, :directory}} =
             Adapter.validate_config(settings(database_path: directory))

    assert {:error, :missing_sqlite_project_slug} = Adapter.validate_config(settings(project_slug: nil))
    assert {:error, :invalid_sqlite_project_slug} = Adapter.validate_config(settings(project_slug: "Alpha"))

    assert {:error, :sqlite_database_path_must_be_absolute} =
             Adapter.validate_config(settings(database_path: "relative.sqlite3"))

    assert {:error, :missing_sqlite_database_path} =
             Adapter.validate_config(settings(database_path: "   "))

    assert {:error, :missing_sqlite_database_path} =
             Adapter.validate_config(settings(database_path: nil))

    assert {:error, {:sqlite_database_inaccessible, _reason}} =
             Adapter.validate_config(settings(database_path: "/tmp/symphony-invalid-null\0.sqlite3"))
  end

  test "regular but invalid SQLite files fail during contract validation" do
    path = Path.join(System.tmp_dir!(), "symphony-invalid-db-#{System.unique_integer([:positive])}.sqlite3")
    File.write!(path, "not a SQLite database")

    on_exit(fn -> File.rm(path) end)

    assert {:sqlite_query_failed, _reason} = Adapter.validate_config(settings(database_path: path))
  end

  test "unreadable regular SQLite files fail at open on POSIX" do
    if match?({:unix, _}, :os.type()) do
      path = Path.join(System.tmp_dir!(), "symphony-unreadable-db-#{System.unique_integer([:positive])}.sqlite3")
      File.write!(path, "unreadable")
      File.chmod!(path, 0o000)

      on_exit(fn ->
        File.chmod(path, 0o600)
        File.rm(path)
      end)

      assert {:error, {:sqlite_open_failed, _reason}} =
               Adapter.validate_config(settings(database_path: path))
    end
  end

  test "schema version, migration identity, partial schema, and required timestamps fail closed" do
    for {name, mutation, expected} <- [
          {"older", "PRAGMA user_version = 0", {:sqlite_incompatible_schema_version, 0}},
          {"newer", "PRAGMA user_version = 2", {:sqlite_unsupported_schema_version, 2}},
          {"identity", "UPDATE schema_migrations SET identity = 'wrong'", {:sqlite_invalid_migration_identity, [[1, "wrong"]]}},
          {
            "partial",
            "DROP TABLE blockers",
            {:sqlite_incompatible_schema, {:missing_columns, "blockers", ["task_id", "kind", "status"]}}
          },
          {
            "missing-field",
            "UPDATE tasks SET id = NULL WHERE id = '#{@alpha_queued}'",
            {:sqlite_invalid_task_row, {:missing, :id}}
          },
          {"timestamp", "UPDATE tasks SET created_at = 'not-a-timestamp'", {:sqlite_malformed_timestamp, :created_at}},
          {
            "null-timestamp",
            "UPDATE tasks SET created_at = zeroblob(1) WHERE id = '#{@alpha_queued}'",
            {:sqlite_malformed_timestamp, :created_at}
          }
        ] do
      path = copy_fixture(name)
      execute_mutation(path, mutation)

      result =
        if name in ["timestamp", "missing-field", "null-timestamp"] do
          Adapter.fetch_issues_by_states_for_test(["QUEUED"], settings(database_path: path))
        else
          Adapter.validate_config(settings(database_path: path))
        end

      assert_matches_sqlite_error(result, expected)
    end
  end

  test "closes the opened connection when schema validation fails" do
    owner = self()

    for {name, mutation, expected} <- [
          {"newer", "PRAGMA user_version = 2", {:sqlite_unsupported_schema_version, 2}},
          {"identity", "UPDATE schema_migrations SET identity = 'wrong'", {:sqlite_invalid_migration_identity, [[1, "wrong"]]}},
          {"partial", "DROP TABLE blockers", {:sqlite_incompatible_schema, {:missing_columns, "blockers", ["task_id", "kind", "status"]}}}
        ] do
      path = copy_fixture("close-#{name}")
      execute_mutation(path, mutation)

      result =
        Adapter.with_validated_connection_for_test(
          settings(database_path: path),
          fn _connection -> :ok end,
          fn connection -> send(owner, {:opened, name, connection}) end
        )

      assert {:error, ^expected} = result
      assert_receive {:opened, ^name, connection}
      assert {:error, _reason} = Sqlite3.prepare(connection, "SELECT 1")
    end
  end

  test "closes the opened connection when the tracker callback raises" do
    owner = self()

    assert_raise RuntimeError, "callback failure", fn ->
      Adapter.with_validated_connection_for_test(
        settings(),
        fn _connection -> raise "callback failure" end,
        fn connection -> send(owner, {:opened, connection}) end
      )
    end

    assert_receive {:opened, connection}
    assert {:error, _reason} = Sqlite3.prepare(connection, "SELECT 1")
  end

  test "covers defensive SQLite error boundaries and malformed normalized rows" do
    assert {:error, {:sqlite_open_failed, :forced_configuration_failure}} =
             Adapter.open_readonly_for_test(fixture_path(), fn _connection ->
               {:error, :forced_configuration_failure}
             end)

    {:ok, closed_connection} = Sqlite3.open(fixture_path(), mode: :readonly)
    assert :ok = Sqlite3.close(closed_connection)

    assert {:error, {:sqlite_query_failed, _reason}} =
             Adapter.query_for_test(closed_connection, "SELECT 1", [])

    assert {:error, {:sqlite_query_failed, _reason}} =
             Adapter.validate_required_columns_for_test(closed_connection)

    assert {:error, {:sqlite_invalid_task_row, []}} = Adapter.normalize_row_for_test([])

    assert {:error, {:sqlite_invalid_task_row, {:missing, :id}}} =
             Adapter.normalize_row_for_test([
               nil,
               "T-000001",
               "title",
               "objective",
               "QUEUED",
               "branch",
               "2026-09-01T12:00:00Z",
               "2026-09-01T12:00:00Z",
               0
             ])

    assert {:error, {:sqlite_malformed_timestamp, nil}} =
             Adapter.normalize_row_for_test([
               "11111111-1111-1111-1111-111111111111",
               "T-000001",
               "title",
               "objective",
               "QUEUED",
               "branch",
               nil,
               "2026-09-01T12:00:00Z",
               0
             ])
  end

  defp settings(overrides \\ []) do
    %{
      kind: "sqlite",
      database_path: Keyword.get(overrides, :database_path, fixture_path()),
      project_slug: Keyword.get(overrides, :project_slug, "alpha"),
      active_states: ["QUEUED"],
      terminal_states: ["READY_FOR_HUMAN_MERGE"]
    }
  end

  defp fixture_path do
    Path.expand("../fixtures/pilot_control_plane_v1.sqlite3", __DIR__)
  end

  defp copy_fixture(name) do
    path = Path.join(System.tmp_dir!(), "symphony-sqlite-#{name}-#{System.unique_integer([:positive])}.sqlite3")
    File.cp!(fixture_path(), path)

    on_exit(fn ->
      File.rm(path)
      File.rm(path <> "-wal")
      File.rm(path <> "-shm")
    end)

    path
  end

  defp execute_mutation(path, sql) do
    {:ok, connection} = Sqlite3.open(path, mode: :readwrite)
    assert :ok = Sqlite3.execute(connection, sql)
    assert :ok = Sqlite3.close(connection)
  end

  defp assert_matches_sqlite_error({:error, actual}, {:sqlite_query_failed, _}) do
    assert match?({:sqlite_query_failed, _}, actual)
  end

  defp assert_matches_sqlite_error({:error, actual}, expected), do: assert(actual == expected)

  defp assert_matches_sqlite_error(actual, expected) do
    flunk("expected #{inspect(expected)}, got #{inspect(actual)}")
  end
end
