defmodule Ruxsat.Rule do
  @moduledoc """
  A single `allow` rule.

  Rules are created at compile time by `Ruxsat.allow/3`. You can list them
  with `rules/0` on your policy module.

    * `:action` - the action atom, e.g. `:update`
    * `:resource` - struct module or atom, e.g. `MyApp.Post`
    * `:role` - `nil` or a list of role atoms
    * `:owner` - `nil` or the resource field compared with `subject.id`
    * `:if` - `nil` or a function `(subject, resource) -> boolean`
  """

  @enforce_keys [:action, :resource]
  defstruct [:action, :resource, role: nil, owner: nil, if: nil]

  @type reason :: :missing_role | :not_owner | :condition_failed

  @type t :: %__MODULE__{
          action: atom,
          resource: atom,
          role: [atom] | nil,
          owner: atom | nil,
          if: (term, term -> boolean) | nil
        }

  @doc """
  Checks one rule against a subject and a resource.

  Options are checked in order: `role`, `owner`, `if`. Stops at the first
  failure.
  """
  @spec check(t, term, term) :: :ok | {:error, reason}
  def check(%__MODULE__{} = rule, subject, resource) do
    cond do
      not role?(rule.role, subject) -> {:error, :missing_role}
      not owner?(rule.owner, subject, resource) -> {:error, :not_owner}
      not condition?(rule, subject, resource) -> {:error, :condition_failed}
      true -> :ok
    end
  end

  defp role?(nil, _subject), do: true

  defp role?(roles, %{role: subject_roles}) when is_list(subject_roles),
    do: Enum.any?(subject_roles, &(&1 in roles))

  defp role?(roles, %{role: role}), do: role in roles
  defp role?(_roles, _subject), do: false

  defp owner?(nil, _subject, _resource), do: true

  defp owner?(field, subject, resource) when is_map(resource) do
    value = Map.fetch!(resource, field)

    case subject do
      %{id: id} when not is_nil(id) -> value == id
      _ -> false
    end
  end

  defp owner?(_field, _subject, _resource), do: false

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
