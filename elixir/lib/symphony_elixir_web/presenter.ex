defmodule SymphonyElixirWeb.Presenter do
  @moduledoc "Projects only Runtime-observed facts; Pilot lifecycle meaning stays upstream."

  alias SymphonyElixir.Orchestrator

  def state_payload(orchestrator, timeout) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    case Orchestrator.snapshot(orchestrator, timeout) do
      %{} = snapshot -> Map.merge(snapshot, %{generated_at: generated_at, lifecycle_source: "Pilot"})
      :timeout -> %{generated_at: generated_at, error: %{code: "snapshot_timeout", message: "Snapshot timed out"}}
      _ -> %{generated_at: generated_at, error: %{code: "snapshot_unavailable", message: "Runtime snapshot unavailable"}}
    end
  end

  def refresh_payload(orchestrator) do
    case Orchestrator.request_refresh(orchestrator) do
      {:ok, payload} -> {:ok, payload}
      _ -> {:error, :unavailable}
    end
  end
end
