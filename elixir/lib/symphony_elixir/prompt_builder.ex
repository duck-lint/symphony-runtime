defmodule SymphonyElixir.PromptBuilder do
  @moduledoc """
  Builds agent prompts from normalized tracker work item data.
  """

  alias SymphonyElixir.{Config, Workflow}

  @render_opts [strict_variables: true, strict_filters: true]

  @spec build_prompt(SymphonyElixir.Tracker.Issue.t(), keyword()) :: String.t()
  def build_prompt(issue, opts \\ []) do
    template =
      Workflow.current()
      |> prompt_template!()
      |> parse_template!()

    rendered =
      template
      |> Solid.render!(
      %{
        "attempt" => Keyword.get(opts, :attempt),
        "issue" => issue |> Map.from_struct() |> to_solid_map(),
        "execution" => opts |> Keyword.get(:execution, %{}) |> to_solid_value()
      },
      @render_opts
    )
    |> IO.iodata_to_binary()

    rendered <> dispatch_guidance(Keyword.get(opts, :execution))
  end

  defp dispatch_guidance(%{role: role, input_path: input_path, result_path: result_path}) do
    result_guidance =
      case role do
        "ARCHITECT" ->
          """
          For ARCHITECT, set `packet` to null and author only Architect findings.
          Set `authorized_write_paths` to an empty list except for
          `planning_complete`, where it may contain explicit repository-relative
          files and/or directories for the next Implementer; never use absolute
          paths or `..`.
          """

        _ ->
          """
          For this specialized role, set `packet` to the packet authored by this
          execution, set top-level `findings` and `authorized_write_paths` to
          empty lists, and never include `role_results`. Implementer packet
          `head_sha` must be null because the trusted host creates the commit;
          read-only roles may report their observed input HEAD.
          """
      end

    """

    ## Runtime dispatch contract

    You are executing exactly one fresh #{role} role. Read the host-owned
    input packet at #{input_path}. Write exactly one JSON object to
    #{result_path} before ending the turn. Copy task identity, expected state,
    expected workpad version, expected starting HEAD, and workpad body from
    that input packet. Set `role_run_id` to the dispatched identity and set
    `role` to #{role}.

    #{result_guidance}
    """
  end

  defp dispatch_guidance(_), do: ""

  defp prompt_template!({:ok, %{prompt_template: prompt}}), do: default_prompt(prompt)

  defp prompt_template!({:error, reason}) do
    raise RuntimeError, "workflow_unavailable: #{inspect(reason)}"
  end

  defp parse_template!(prompt) when is_binary(prompt) do
    Solid.parse!(prompt)
  rescue
    error ->
      reraise %RuntimeError{
                message: "template_parse_error: #{Exception.message(error)} template=#{inspect(prompt)}"
              },
              __STACKTRACE__
  end

  defp to_solid_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_solid_value(value)} end)
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_map()
  defp to_solid_value(value) when is_map(value), do: to_solid_map(value)
  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp default_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      Config.workflow_prompt()
    else
      prompt
    end
  end
end
