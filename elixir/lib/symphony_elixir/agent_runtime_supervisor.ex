defmodule SymphonyElixir.AgentRuntimeSupervisor do
  @moduledoc """Supervises Runtime execution mechanics and task-scoped PM continuity."""

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    task_supervisor_name =
      Keyword.get(opts, :task_supervisor_name, SymphonyElixir.TaskSupervisor)

    orchestrator_name = Keyword.get(opts, :orchestrator_name, SymphonyElixir.Orchestrator)

    children = [
      Supervisor.child_spec(
        {Task.Supervisor, name: task_supervisor_name},
        id: task_supervisor_name
      ),
      Supervisor.child_spec(SymphonyElixir.PMContinuity, id: SymphonyElixir.PMContinuity),
      Supervisor.child_spec(
        {SymphonyElixir.Orchestrator, name: orchestrator_name, task_supervisor: task_supervisor_name},
        id: orchestrator_name
      )
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
