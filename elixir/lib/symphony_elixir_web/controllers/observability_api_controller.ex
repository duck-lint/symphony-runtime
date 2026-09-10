defmodule SymphonyElixirWeb.ObservabilityApiController do
  @moduledoc "Runtime observability API; it is not a lifecycle authority."
  use Phoenix.Controller, formats: [:json]
  alias Plug.Conn
  alias SymphonyElixirWeb.{Endpoint, Presenter}

  @spec state(Conn.t(), map()) :: Conn.t()
  def state(conn, _params), do: json(conn, Presenter.state_payload(orchestrator(), 15_000))

  @spec refresh(Conn.t(), map()) :: Conn.t()
  def refresh(conn, _params) do
    case Presenter.refresh_payload(orchestrator()) do
      {:ok, payload} -> conn |> put_status(202) |> json(payload)
      _ -> conn |> put_status(503) |> json(%{error: %{code: "runtime_unavailable", message: "Runtime unavailable"}})
    end
  end

  @spec method_not_allowed(Conn.t(), map()) :: Conn.t()
  def method_not_allowed(conn, _params), do: conn |> put_status(405) |> json(%{error: %{code: "method_not_allowed", message: "Method not allowed"}})
  @spec not_found(Conn.t(), map()) :: Conn.t()
  def not_found(conn, _params), do: conn |> put_status(404) |> json(%{error: %{code: "not_found", message: "Route not found"}})
  defp orchestrator, do: Endpoint.config(:orchestrator) || SymphonyElixir.Orchestrator
end
