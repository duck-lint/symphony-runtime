defmodule SymphonyElixir.PMContinuity do
  @moduledoc """Task-keyed PM continuity, separate from fresh specialist executions."""

  use GenServer

  @max_entries 32
  @max_summary_bytes 4_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec prompt_suffix(String.t(), String.t()) :: String.t()
  def prompt_suffix(task_id, "PROJECT-MANAGER") do
    case GenServer.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, {:prompt, task_id})
      _ -> ""
    end
  end
  def prompt_suffix(_task_id, _role), do: ""

  @spec record(String.t(), term()) :: :ok
  def record(task_id, result) when is_binary(task_id) do
    if pid = GenServer.whereis(__MODULE__), do: GenServer.cast(pid, {:record, task_id, result})
    :ok
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:prompt, task_id}, _from, state) do
    suffix = case Map.get(state, task_id) do
      nil -> ""
      entries -> "\n\n## Prior PM/Dispatcher continuity for this durable task\n" <> Enum.join(entries, "\n")
    end
    {:reply, suffix, state}
  end

  @impl true
  def handle_cast({:record, task_id, result}, state) do
    summary = result |> inspect(limit: 20, printable_limit: @max_summary_bytes) |> String.slice(0, @max_summary_bytes)
    entries = Map.get(state, task_id, []) |> Kernel.++([summary]) |> Enum.take(-@max_entries)
    {:noreply, Map.put(state, task_id, entries)}
  end
end
