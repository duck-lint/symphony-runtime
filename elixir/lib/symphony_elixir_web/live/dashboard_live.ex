defmodule SymphonyElixirWeb.DashboardLive do
  @moduledoc """Live projection of Runtime execution observation."""
  use Phoenix.LiveView, layout: {SymphonyElixirWeb.Layouts, :app}
  alias SymphonyElixirWeb.{Endpoint, Presenter}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :payload, load_payload())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="dashboard-shell">
      <h1>Symphony Runtime</h1>
      <p>Runtime execution observation. Lifecycle meaning is projected by Pilot.</p>
      <%= if @payload[:error] do %>
        <p><%= @payload.error.message %></p>
      <% else %>
        <p>Running executions: <%= length(@payload.running) %></p>
        <ul>
          <li :for={entry <- @payload.running}>
            <%= entry.expected_role %> — <%= entry.dispatch_id %> — task <%= entry.task_id %>
          </li>
        </ul>
      <% end %>
    </main>
    """
  end

  defp load_payload, do: Presenter.state_payload(Endpoint.config(:orchestrator) || SymphonyElixir.Orchestrator, 15_000)
end
