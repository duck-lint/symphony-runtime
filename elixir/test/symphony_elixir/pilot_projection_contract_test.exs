defmodule SymphonyElixir.PilotProjectionContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.PilotProjection

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

  defp uuid, do: Ecto.UUID.generate()
end
