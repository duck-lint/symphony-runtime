defmodule SymphonyElixir.OrchestratorTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Orchestrator

  test "a stale local completion cannot suppress an authorized older dispatch" do
    older_dispatch_id = Ecto.UUID.generate()
    newer_dispatch_id = Ecto.UUID.generate()

    state = %Orchestrator.State{
      completed: MapSet.new([older_dispatch_id]),
      running: %{}
    }

    # Pilot returns the older row first. Both rows remain schedulable because
    # Runtime-local completion is not lifecycle authority.
    assert Orchestrator.dispatch_schedulable_for_test?(state, older_dispatch_id)
    assert Orchestrator.dispatch_schedulable_for_test?(state, newer_dispatch_id)
  end

  test "a failed execution is observable and is not recorded as completed" do
    dispatch_id = Ecto.UUID.generate()
    ref = make_ref()
    state = %Orchestrator.State{
      running: %{dispatch_id => %{ref: ref}},
      completed: MapSet.new()
    }

    assert {:noreply, updated} =
             Orchestrator.handle_info({ref, {:error, :terminal_reconciliation_failed}}, state)

    assert updated.running == %{}
    assert updated.completed == MapSet.new()
    assert updated.last_error ==
             {:dispatch_execution_failed, dispatch_id, :terminal_reconciliation_failed}
  end

  test "a successfully reconciled execution remains observable as completed" do
    dispatch_id = Ecto.UUID.generate()
    ref = make_ref()
    state = %Orchestrator.State{running: %{dispatch_id => %{ref: ref}}}

    assert {:noreply, updated} = Orchestrator.handle_info({ref, :ok}, state)

    assert updated.running == %{}
    assert MapSet.member?(updated.completed, dispatch_id)
    assert updated.last_error == nil
  end
end
