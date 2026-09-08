defmodule SymphonyElixir.PromptBuilder do
  @moduledoc """Builds one role prompt from the Pilot dispatch and workflow text."""

  alias SymphonyElixir.{Config, PilotProjection}
  @render_opts [strict_variables: false, strict_filters: true]

  @spec build(PilotProjection.t()) :: String.t()
  def build(%PilotProjection{} = dispatch) do
    template = Config.workflow_prompt() |> Solid.parse!()
    rendered = Solid.render!(template, %{"task" => stringify(dispatch.task), "execution" => execution_map(dispatch)}, @render_opts)
    rendered <> protocol_instructions(dispatch)
  end

  defp execution_map(dispatch) do
    %{"task_id" => dispatch.task.id, "identifier" => dispatch.task.identifier,
      "lifecycle_id" => dispatch.lifecycle_id, "working_round_id" => dispatch.working_round_id,
      "planning_attempt_id" => dispatch.planning_attempt_id, "dispatch_id" => dispatch.dispatch_id,
      "role" => dispatch.role, "expected_starting_head" => dispatch.expected_starting_head,
      "capability_grant" => dispatch.grant, "result_path" => dispatch.result_path}
  end

  defp protocol_instructions(dispatch) do
    role = dispatch.role
    """

    ## Pilot execution contract

    You are one fresh #{role} execution. Read the Pilot dispatch at
    #{dispatch.namespace}/host/dispatch.json and write exactly one
    `symphony-pilot-execution-result/v2` object to #{dispatch.result_path}.
    The role and capability grant are already authorized by Pilot. Do not add
    paths, write Git metadata, stage, commit, mutate Pilot state, or claim
    lifecycle meaning. Planner `proposed_implementation_paths` is evidence
    for Pilot and cannot grant authority. Return only evidence from this
    execution.
    """
  end

  defp stringify(value) when is_map(value), do: Map.new(value, fn {key, nested} -> {to_string(key), stringify(nested)} end)
  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp stringify(value), do: value
end
