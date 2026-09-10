defmodule SymphonyElixir.PMContinuityTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.PMContinuity

  test "continuity is task-scoped and never shared with specialists" do
    assert is_pid(Process.whereis(PMContinuity))

    PMContinuity.record("task-a", %{summary: "accepted PM observation"})

    assert PMContinuity.prompt_suffix("task-a", "PROJECT-MANAGER") =~ "accepted PM observation"
    assert PMContinuity.prompt_suffix("task-b", "PROJECT-MANAGER") == ""
    assert PMContinuity.prompt_suffix("task-a", "PLANNER") == ""
  end
end
