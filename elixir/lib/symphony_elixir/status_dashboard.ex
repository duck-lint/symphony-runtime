defmodule SymphonyElixir.StatusDashboard do
  @moduledoc "Small Runtime-only projection of observed execution mechanics."

  use GenServer
  alias SymphonyElixir.Config

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def notify_update(server \\ __MODULE__) do
    if pid = GenServer.whereis(server), do: send(pid, :refresh)
    :ok
  end

  def render_offline_status, do: IO.puts("SYMPHONY RUNTIME offline")

  @doc false
  def humanize_codex_message(nil), do: nil
  def humanize_codex_message(value) when is_binary(value), do: String.slice(value, 0, 500)
  def humanize_codex_message(value), do: inspect(value, limit: 10, printable_limit: 500)

  @impl true
  def init(_opts) do
    settings = Config.settings!().observability
    Process.send_after(self(), :tick, settings.refresh_ms)
    {:ok, %{enabled: settings.dashboard_enabled, refresh_ms: settings.refresh_ms, render_fun: &IO.puts/1}}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.enabled, do: state.render_fun.(render_snapshot())
    Process.send_after(self(), :tick, state.refresh_ms)
    {:noreply, state}
  end

  def handle_info(:refresh, state), do: {:noreply, state}

  defp render_snapshot do
    case SymphonyElixir.Orchestrator.snapshot() do
      %{running: running} = snapshot ->
        rows = Enum.map(running, fn entry -> "#{entry.expected_role} #{entry.dispatch_id} task=#{entry.task_id}" end)
        Enum.join(["SYMPHONY RUNTIME", "running=#{length(running)}"] ++ rows, "\n")

      _ ->
        "SYMPHONY RUNTIME unavailable"
    end
  end
end
