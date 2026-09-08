defmodule SymphonyElixir.ExecutionBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.{AgentRunner, Codex.AppServer, PilotProjection, Workspace}

  test "Pilot task identifiers are the workspace directory identity" do
    assert Workspace.workspace_key("T-000001") == "T-000001"
    assert_raise ArgumentError, fn -> Workspace.workspace_key("unsafe/task") end
  end

  test "NUL-delimited porcelain includes both rename paths" do
    raw = "R  harness/new.md\x00harness/old.md\x00C  src/copy.ex\x00src/original.ex\x00"
    assert {:ok, paths} = AgentRunner.parse_porcelain_z_for_test(raw)
    assert paths == ["harness/new.md", "harness/old.md", "src/copy.ex", "src/original.ex"]
  end

  test "direct App Server calls require a Pilot execution grant" do
    assert {:error, :pilot_execution_grant_required} =
             AppServer.validate_execution_for_test(%{}, "/tmp/workspace")
  end

  test "obsolete Architect role is not an executable Runtime role" do
    assert {:error, :invalid_role} =
             AppServer.validate_execution_for_test(%PilotProjection{role: "ARCHITECT"}, "/tmp/workspace")
  end

  test "non-writer grant cannot contain project write roots" do
    task_id = Ecto.UUID.generate()
    dispatch_id = Ecto.UUID.generate()
    execution = %PilotProjection{role: "REVIEWER", dispatch_id: dispatch_id,
      result_path: "/tmp/pilot/outbox/result.json",
      expected_starting_head: String.duplicate("a", 40),
      grant: %{id: Ecto.UUID.generate(), task_id: task_id, dispatch_id: dispatch_id,
        issued_at: "2026-09-08T00:00:00Z", role: "REVIEWER",
        read_scopes: ["project"], write_scopes: ["src"]}, task: %{id: task_id}}
    assert {:error, :writer_scope_mismatch} =
             AppServer.validate_execution_for_test(execution, "/tmp/workspace")
  end
end
