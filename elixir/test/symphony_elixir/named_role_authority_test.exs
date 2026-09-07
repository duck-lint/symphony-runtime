defmodule SymphonyElixir.NamedRoleAuthorityTest do
  use SymphonyElixir.TestSupport

  test "role dispatch selects read-only or bounded workspace-write policies" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-named-role-authority-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-ROLE-AUTHORITY")
      authorized_root = Path.join(workspace, "src")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex.trace")
      result_root = Path.join(test_root, "lifecycle-outbox")

      File.mkdir_p!(workspace)
      File.mkdir_p!(authorized_root)
      File.mkdir_p!(result_root)
      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="$SYMP_TEST_NAMED_ROLE_TRACE"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"
        case "$count" in
          1) printf '%s\\n' '{"id":1,"result":{}}' ;;
          2) ;;
          3) printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-role-authority"}}}' ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-role-authority"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *) exit 0 ;;
        esac
      done
      """)
      File.chmod!(codex_binary, 0o755)

      previous_trace = System.get_env("SYMP_TEST_NAMED_ROLE_TRACE")
      System.put_env("SYMP_TEST_NAMED_ROLE_TRACE", trace_file)

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_NAMED_ROLE_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_NAMED_ROLE_TRACE")
        end
      end)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server"
      )

      issue = %Issue{
        id: "issue-named-role-authority",
        identifier: "MT-ROLE-AUTHORITY",
        title: "Validate named-role capability assignment",
        description: "Ensure only Implementer receives a bounded write grant",
        state: "In Progress",
        url: "https://example.org/issues/MT-ROLE-AUTHORITY",
        labels: ["backend"]
      }

      for role <- [
            "ARCHITECT",
            "PROJECT-MANAGER",
            "PLANNER",
            "REVIEWER",
            "ADVERSARY",
            "ARCHIVIST",
            "IMPLEMENTER"
          ] do
        File.rm(trace_file)
        target_writable_roots = if role == "IMPLEMENTER", do: [authorized_root], else: []

        assert {:ok, _result} =
                 AppServer.run(workspace, "Run #{role}", issue,
                   role: role,
                   result_writable_root: result_root,
                   target_writable_roots: target_writable_roots
                 )

        payloads =
          trace_file
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, "JSON:"))
          |> Enum.map(&(&1 |> String.trim_leading("JSON:") |> Jason.decode!()))

        thread_start = Enum.find(payloads, &(&1["method"] == "thread/start"))
        turn_start = Enum.find(payloads, &(&1["method"] == "turn/start"))

        if role == "IMPLEMENTER" do
          assert thread_start["params"]["sandbox"] == "workspace-write"
          assert turn_start["params"]["sandboxPolicy"] == %{
                   "type" => "workspaceWrite",
                   "writableRoots" => [result_root, authorized_root],
                   "readOnlyAccess" => %{"type" => "fullAccess"},
                   "networkAccess" => false
                 }
        else
          assert thread_start["params"]["sandbox"] == "workspace-write"
          assert turn_start["params"]["sandboxPolicy"] == %{
                   "type" => "workspaceWrite",
                   "writableRoots" => [result_root],
                   "readOnlyAccess" => %{"type" => "fullAccess"},
                   "networkAccess" => false
                 }
        end
      end

      assert {:error, {:target_write_not_allowed_for_role, "REVIEWER"}} =
               AppServer.start_session(workspace,
                 role: "REVIEWER",
                 result_writable_root: result_root,
                 target_writable_roots: [workspace]
               )

      assert {:error, :target_writable_root_outside_authorized_workspace} =
               AppServer.start_session(workspace,
                 role: "IMPLEMENTER",
                 result_writable_root: result_root,
                 target_writable_roots: [workspace]
               )
    after
      File.rm_rf(test_root)
    end
  end
end
