defmodule SymphonyElixir.PilotProjectionContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.{PilotProjection, PromptBuilder}

  test "accepts only an exact Pilot dispatch packet and grant" do
    row = %{dispatch_id: uuid(), task_id: uuid(), identifier: "T-000001", lifecycle_id: uuid(),
      working_round_id: uuid(), planning_attempt_id: uuid(), role: "PLANNER",
      expected_starting_head: String.duplicate("a", 40), grant_id: uuid(),
      read_scopes: ["project", "registered_harness_artifacts"],
      write_scopes: ["harness/plans"], issued_at: "2026-09-08T00:00:00Z"}
    packet = %{"schema" => "symphony-pilot-dispatch/v1", "task_id" => row.task_id,
      "identifier" => row.identifier,
      "lifecycle_id" => row.lifecycle_id, "working_round_id" => row.working_round_id,
      "planning_attempt_id" => row.planning_attempt_id, "dispatch_id" => row.dispatch_id,
      "role" => row.role, "expected_starting_head" => row.expected_starting_head,
      "capability_grant" => %{"id" => row.grant_id, "task_id" => row.task_id,
        "dispatch_id" => row.dispatch_id, "role" => row.role, "issued_at" => row.issued_at,
        "read_scopes" => row.read_scopes, "write_scopes" => row.write_scopes}}

    assert {:ok, ^packet} = PilotProjection.validate_dispatch_packet_for_test(packet, row)
    assert {:error, :pilot_dispatch_packet_mismatch} =
             PilotProjection.validate_dispatch_packet_for_test(put_in(packet["capability_grant"]["write_scopes"], ["."]), row)
  end

  test "an existing execution receipt does not hide an authorized dispatch" do
    receipt = Path.join(System.tmp_dir!(), "symphony-execution-#{System.unique_integer([:positive])}.json")
    File.write!(receipt, "{}\n")
    on_exit(fn -> File.rm(receipt) end)
    dispatch = %PilotProjection{dispatch_id: uuid(), execution_path: receipt}
    assert {:ok, ^dispatch} = PilotProjection.visible_authorized_dispatch_for_test(dispatch)
  end

  test "Pilot-selected handoffs are rendered, while Runtime supplies no context" do
    dispatch = %PilotProjection{task: %{id: uuid(), identifier: "T-000001", title: "task", objective: "objective"},
      lifecycle_id: uuid(), working_round_id: uuid(), planning_attempt_id: uuid(), dispatch_id: uuid(),
      role: "PLANNER", expected_starting_head: String.duplicate("a", 40),
      grant: %{id: uuid(), read_scopes: ["project"], write_scopes: ["harness/plan"]},
      namespace: "/tmp/dispatch", result_path: "/tmp/dispatch/outbox/result.json",
      handoff_inputs: [%{"kind" => "PM_HANDOFF", "source_role" => "PROJECT-MANAGER",
        "source_dispatch_id" => uuid(), "input" => %{"summary" => "bounded request"}}]}

    prompt = PromptBuilder.build(dispatch)
    assert prompt =~ "bounded request"
    refute prompt =~ "PMContinuity"
  end

  defp uuid, do: Ecto.UUID.generate()
end
