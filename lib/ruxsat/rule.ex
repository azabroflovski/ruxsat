defmodule Ruxsat.Rule do
  @moduledoc """
  A single `allow` rule.

  Rules are created at compile time by `Ruxsat.allow/3`. You can list them
  with `rules/0` on your policy module.

    * `:action` - the action atom, e.g. `:update`
    * `:resource` - struct module or atom, e.g. `MyApp.Post`
    * `:role` - `nil` or a list of role atoms
    * `:owner` - `nil` or the resource field compared with `subject.id`
    * `:where` - `nil` or a keyword list of resource fields and literal values
    * `:if` - `nil` or a function `(subject, resource) -> boolean`
  """

  @enforce_keys [:action, :resource]
  defstruct [:action, :resource, role: nil, owner: nil, where: nil, if: nil]

  @type reason :: :missing_role | :not_owner | :where_mismatch | :condition_failed

  @type t :: %__MODULE__{
          action: atom,
          resource: atom,
          role: [atom] | nil,
          owner: atom | nil,
          where: keyword | nil,
          if: (term, term -> boolean) | nil
        }

  @doc """
  Checks one rule against a subject and a resource.

  Options are checked in order: `role`, `owner`, `where`, `if`. Stops at the
  first failure.
  """
  @spec check(t, term, term) :: :ok | {:error, reason}
  def check(%__MODULE__{} = rule, subject, resource) do
    cond do
      not role?(rule.role, subject) -> {:error, :missing_role}
      not owner?(rule.owner, subject, resource) -> {:error, :not_owner}
      not where?(rule.where, resource) -> {:error, :where_mismatch}
      not condition?(rule, subject, resource) -> {:error, :condition_failed}
      true -> :ok
    end
  end

  @doc """
  Returns the filter set of one rule for a subject.

  Returns `:skip` when the rule cannot pass for this subject. Otherwise returns
  `{:ok, set}`, where `set` lists the fields a record must match. Raises for
  rules with `:if`, because functions cannot be turned into data.
  """
  @spec filter(t, term) :: {:ok, keyword} | :skip
  def filter(%__MODULE__{if: nil} = rule, subject) do
    cond do
      not role?(rule.role, subject) -> :skip
      is_nil(rule.owner) -> {:ok, List.wrap(rule.where)}
      id = subject_id(subject) -> {:ok, [{rule.owner, id} | List.wrap(rule.where)]}
      true -> :skip
    end
  end

  def filter(%__MODULE__{} = rule, _subject) do
    raise ArgumentError,
          "cannot build a filter for #{inspect(rule.action)} on #{inspect(rule.resource)}: " <>
            "a rule uses :if, which cannot be turned into data"
  end

  defp role?(nil, _subject), do: true

  defp role?(roles, %{role: subject_roles}) when is_list(subject_roles),
    do: Enum.any?(subject_roles, &(&1 in roles))

  defp role?(roles, %{role: role}), do: role in roles
  defp role?(_roles, _subject), do: false

  defp owner?(nil, _subject, _resource), do: true

  defp owner?(field, subject, resource) when is_map(resource) do
    value = Map.fetch!(resource, field)
    id = subject_id(subject)
    id != nil and value == id
  end

  defp owner?(_field, _subject, _resource), do: false

  defp subject_id(%{id: id}), do: id
  defp subject_id(_subject), do: nil

  defp where?(nil, _resource), do: true

  defp where?(fields, resource) when is_map(resource) do
    Enum.all?(fields, fn {field, value} -> Map.fetch!(resource, field) == value end)
  end

  defp where?(_fields, _resource), do: false

  defp condition?(%{if: nil}, _subject, _resource), do: true

  defp condition?(%{if: fun} = rule, subject, resource) when is_function(fun, 2) do
    case fun.(subject, resource) do
      result when is_boolean(result) ->
        result

      other ->
        raise ArgumentError,
              "expected :if condition of rule #{inspect(rule.action)} on " <>
                "#{inspect(rule.resource)} to return a boolean, got: #{inspect(other)}"
    end
  end

  defp condition?(rule, _subject, _resource) do
    raise ArgumentError,
          "expected :if condition of rule #{inspect(rule.action)} on " <>
            "#{inspect(rule.resource)} to be a function of arity 2, got: #{inspect(rule.if)}"
  end
end
