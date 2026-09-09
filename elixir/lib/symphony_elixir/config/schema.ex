defmodule SymphonyElixir.Config.Schema do
  @moduledoc "Runtime configuration that does not duplicate Pilot semantics."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @type t :: %__MODULE__{}

  defmodule Pilot do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:database_path, :string)
      field(:project_slug, :string)
      field(:reconcile_command, {:array, :string})
    end
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:database_path, :project_slug, :reconcile_command], empty_values: [])
      |> validate_required([:database_path, :project_slug, :reconcile_command])
      |> validate_change(:database_path, fn :database_path, value ->
        if Path.type(value) == :absolute, do: [], else: [database_path: "must be absolute"]
      end)
      |> validate_change(:project_slug, fn :project_slug, value ->
        if Regex.match?(~r/^[a-z0-9][a-z0-9-]{0,63}$/, value), do: [], else: [project_slug: "is unsafe"]
      end)
      |> validate_change(:reconcile_command, fn :reconcile_command, value ->
        if is_list(value) and value != [] and Enum.all?(value, &(is_binary(&1) and &1 != "")), do: [], else: [reconcile_command: "must be a non-empty command"]
      end)
    end
  end

  defmodule Polling do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:interval_ms, :integer, default: 1_000)
    end
    def changeset(schema, attrs), do: schema |> cast(attrs, [:interval_ms], empty_values: []) |> validate_number(:interval_ms, greater_than: 0)
  end

  defmodule Workspace do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:root, :string)
      field(:materialize_command, {:array, :string})
      field(:repository_remote, :string)
    end
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:root, :materialize_command, :repository_remote], empty_values: [])
      |> validate_required([:root, :materialize_command, :repository_remote])
      |> validate_change(:repository_remote, fn :repository_remote, value ->
        if is_binary(value) and value != "" and not String.contains?(value, ["\n", "\r", "\0"]), do: [], else: [repository_remote: "is invalid"]
      end)
      |> validate_change(:materialize_command, fn :materialize_command, value ->
        if is_list(value) and value != [] and Enum.all?(value, &(is_binary(&1) and &1 != "")), do: [], else: [materialize_command: "must be a non-empty command"]
      end)
    end
  end

  defmodule Agent do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:max_concurrent_agents, :integer, default: 1)
    end
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:max_concurrent_agents], empty_values: [])
      |> validate_number(:max_concurrent_agents, greater_than: 0)
    end
  end

  defmodule Codex do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:command, :string, default: "codex app-server")
      field(:approval_policy, :string, default: "never")
      field(:thread_sandbox, :string, default: "workspace-write")
      field(:turn_sandbox_policy, :map)
      field(:turn_timeout_ms, :integer, default: 3_600_000)
      field(:read_timeout_ms, :integer, default: 5_000)
      field(:stall_timeout_ms, :integer, default: 300_000)
    end
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:command, :approval_policy, :thread_sandbox, :turn_sandbox_policy, :turn_timeout_ms, :read_timeout_ms, :stall_timeout_ms], empty_values: [])
      |> validate_required([:command])
      |> validate_number(:turn_timeout_ms, greater_than: 0)
      |> validate_number(:read_timeout_ms, greater_than: 0)
      |> validate_number(:stall_timeout_ms, greater_than_or_equal_to: 0)
    end
  end

  defmodule Observability do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:dashboard_enabled, :boolean, default: true)
      field(:refresh_ms, :integer, default: 1_000)
      field(:render_interval_ms, :integer, default: 16)
    end
    def changeset(schema, attrs) do
      schema |> cast(attrs, [:dashboard_enabled, :refresh_ms, :render_interval_ms], empty_values: [])
      |> validate_number(:refresh_ms, greater_than: 0)
      |> validate_number(:render_interval_ms, greater_than: 0)
    end
  end

  defmodule Server do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:port, :integer)
      field(:host, :string, default: "127.0.0.1")
    end
    def changeset(schema, attrs), do: schema |> cast(attrs, [:port, :host], empty_values: []) |> validate_number(:port, greater_than_or_equal_to: 0)
  end

  embedded_schema do
    embeds_one(:pilot, Pilot, on_replace: :update, defaults_to_struct: true)
    embeds_one(:polling, Polling, on_replace: :update, defaults_to_struct: true)
    embeds_one(:workspace, Workspace, on_replace: :update, defaults_to_struct: true)
    embeds_one(:agent, Agent, on_replace: :update, defaults_to_struct: true)
    embeds_one(:codex, Codex, on_replace: :update, defaults_to_struct: true)
    embeds_one(:observability, Observability, on_replace: :update, defaults_to_struct: true)
    embeds_one(:server, Server, on_replace: :update, defaults_to_struct: true)
  end

  @spec parse(map()) :: {:ok, t()} | {:error, {:invalid_workflow_config, String.t()}}
  def parse(config) when is_map(config) do
    config
    |> normalize_keys()
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, settings} -> {:ok, settings}
      {:error, changeset} -> {:error, {:invalid_workflow_config, format_errors(changeset)}}
    end
  end

  defp changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [])
    |> cast_embed(:pilot, with: &Pilot.changeset/2)
    |> cast_embed(:polling, with: &Polling.changeset/2)
    |> cast_embed(:workspace, with: &Workspace.changeset/2)
    |> cast_embed(:agent, with: &Agent.changeset/2)
    |> cast_embed(:codex, with: &Codex.changeset/2)
    |> cast_embed(:observability, with: &Observability.changeset/2)
    |> cast_embed(:server, with: &Server.changeset/2)
    |> validate_required([:pilot, :workspace])
  end

  defp normalize_keys(value) when is_map(value), do: Map.new(value, fn {key, nested} -> {normalize_key(key), normalize_keys(nested)} end)
  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value
  defp normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_key(value), do: to_string(value)

  defp format_errors(changeset) do
    changeset |> traverse_errors(&translate_error/1) |> Enum.map_join(", ", fn {key, value} -> "#{key} #{value}" end)
  end
  defp translate_error({message, options}) do
    Enum.reduce(options, message, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
  end
end
