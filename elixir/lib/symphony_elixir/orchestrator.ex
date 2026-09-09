defmodule SymphonyElixir.Orchestrator do
  @moduledoc """
  Schedules only the Pilot-authorized dispatch currently available.

  Runtime never computes the next role or interprets lifecycle state. A Pilot
  dispatch is the only scheduler input; process failures are Runtime facts,
  not permission to manufacture another dispatch.
  """

  use GenServer
  require Logger

  alias SymphonyElixir.{AgentRunner, Config, PilotProjection, StatusDashboard}

  defmodule State do
    @moduledoc false
    defstruct [
      :poll_interval_ms,
      :max_concurrent_agents,
      :tick_ref,
      :task_supervisor,
      running: %{},
      completed: MapSet.new(),
      last_error: nil,
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      rate_limits: nil
    ]
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    settings = Config.settings!()

    state = %State{
      poll_interval_ms: settings.polling.interval_ms,
      max_concurrent_agents: settings.agent.max_concurrent_agents,
      task_supervisor: Keyword.get(opts, :task_supervisor, SymphonyElixir.TaskSupervisor)
    }

    {:ok, schedule_poll(state, 0)}
  end

  @impl true
  def handle_info(:poll, state) do
    state = maybe_dispatch(state)
    state = schedule_poll(state, state.poll_interval_ms)
    StatusDashboard.notify_update()
    {:noreply, state}
  end

  def handle_info({:runtime_execution_update, dispatch_id, message}, state) do
    case Map.get(state.running, dispatch_id) do
      nil -> {:noreply, state}
      entry -> {:noreply, %{state | running: Map.put(state.running, dispatch_id, Map.merge(entry, update_entry(message)))}}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    case find_by_ref(state.running, ref) do
      {dispatch_id, entry} ->
        Process.demonitor(ref, [:flush])
        state = %{state | running: Map.delete(state.running, dispatch_id), completed: MapSet.put(state.completed, dispatch_id)}
        Logger.info("Runtime execution finished dispatch_id=#{dispatch_id} result=#{inspect(result, limit: 10)}")
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_by_ref(state.running, ref) do
      {dispatch_id, _entry} ->
        Logger.warning("Runtime process ended dispatch_id=#{dispatch_id} reason=#{inspect(reason)}; Pilot retains lifecycle authority")
        {:noreply, %{state | running: Map.delete(state.running, dispatch_id), last_error: reason}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @spec snapshot() :: map() | :unavailable
  def snapshot, do: snapshot(__MODULE__, 15_000)

  @spec snapshot(GenServer.server(), timeout()) :: map() | :unavailable
  def snapshot(server, timeout) do
    try do
      GenServer.call(server, :snapshot, timeout)
    catch
      :exit, _ -> :unavailable
    end
  end

  @spec request_refresh() :: {:ok, map()} | :unavailable
  def request_refresh, do: request_refresh(__MODULE__)

  @spec request_refresh(GenServer.server()) :: {:ok, map()} | :unavailable
  def request_refresh(server) do
    try do
      {:ok, GenServer.call(server, :request_refresh, 15_000)}
    catch
      :exit, _ -> :unavailable
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, snapshot_payload(state), state}
  def handle_call(:request_refresh, _from, state), do: {:reply, Map.put(snapshot_payload(state), :requested_at, DateTime.utc_now()), state}

  defp maybe_dispatch(%State{running: running, max_concurrent_agents: limit} = state) when map_size(running) >= limit, do: state

  defp maybe_dispatch(%State{} = state) do
    case PilotProjection.next_dispatch(Config.settings!()) do
      {:ok, nil} ->
        state

      {:ok, %PilotProjection{dispatch_id: dispatch_id} = dispatch} ->
        if MapSet.member?(state.completed, dispatch_id) or Map.has_key?(state.running, dispatch_id) do
          state
        else
          recipient = self()
          task = Task.Supervisor.async_nolink(state.task_supervisor, fn -> AgentRunner.run(dispatch, recipient) end)
          entry = %{dispatch: dispatch, ref: task.ref, pid: task.pid, started_at: DateTime.utc_now(), last_event: nil, last_message: nil, session_id: nil, token_usage: %{}}
          %{state | running: Map.put(state.running, dispatch_id, entry)}
        end

      {:error, reason} ->
        Logger.warning("Pilot dispatch projection unavailable: #{inspect(reason)}")
        %{state | last_error: reason}
    end
  end

  defp snapshot_payload(state) do
    executions =
      Enum.map(state.running, fn {dispatch_id, entry} ->
        dispatch = entry.dispatch

        %{
          task_id: dispatch.task.id,
          identifier: dispatch.task.identifier,
          lifecycle_id: dispatch.lifecycle_id,
          working_round_id: dispatch.working_round_id,
          planning_attempt_id: dispatch.planning_attempt_id,
          expected_role: dispatch.role,
          dispatch_id: dispatch_id,
          runtime_execution_id: entry[:runtime_execution_id],
          workspace_path: nil,
          process_id: entry[:process_id],
          session_id: entry.session_id,
          started_at: entry.started_at,
          last_event: entry.last_event,
          last_message: entry.last_message,
          token_usage: entry.token_usage
        }
      end)

    running = Enum.filter(executions, fn entry -> is_binary(entry.runtime_execution_id) end)
    authorized_dispatches = Enum.filter(executions, fn entry -> is_nil(entry.runtime_execution_id) end)

    %{
      running: running,
      authorized_dispatches: authorized_dispatches,
      completed_dispatches: MapSet.to_list(state.completed),
      codex_totals: state.codex_totals,
      rate_limits: state.rate_limits,
      polling: %{next_poll_in_ms: state.poll_interval_ms, last_error: state.last_error}
    }
  end

  defp update_entry(message) when is_map(message) do
    %{
      last_event: Map.get(message, :event),
      last_message: inspect(Map.get(message, :message, message), limit: 10),
      session_id: Map.get(message, :session_id),
      process_id: Map.get(message, :codex_app_server_pid),
      runtime_execution_id: Map.get(message, :runtime_execution_id),
      token_usage: Map.get(message, :usage, %{})
    }
  end

  defp update_entry(_), do: %{}
  defp find_by_ref(running, ref), do: Enum.find_value(running, fn {dispatch_id, entry} -> if entry.ref == ref, do: {dispatch_id, entry} end)
  defp schedule_poll(state, delay), do: %{state | tick_ref: Process.send_after(self(), :poll, delay)}
end
