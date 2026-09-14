defmodule Ruxsat do
  @moduledoc """
  Small, explicit authorization for Elixir.

      defmodule MyApp.Authorization do
        use Ruxsat

        allow :read, Post
        allow :create, Post, role: :editor
        allow :update, Post, owner: true
        allow :publish, Post, if: &__MODULE__.can_publish?/2

        def can_publish?(user, post), do: user.verified and not post.archived
      end

  `use Ruxsat` generates these functions in your module:

    * `can?(subject, action, resource)` - returns a boolean. Use it for UI.
    * `authorize(subject, action, resource)` - returns `:ok` or
      `{:error, :forbidden}`. Use it where the operation is performed.
    * `authorize!(subject, action, resource)` - returns `:ok` or raises
      `Ruxsat.ForbiddenError`.
    * `explain(subject, action, resource)` - tells you why access was allowed
      or denied. Use it for debugging.
    * `rules()` - returns all rules in declaration order.

  ## Semantics

    * Access is denied unless a rule allows it.
    * Rules combine with OR: one passing rule is enough.
    * Options within one rule combine with AND.
    * A struct resource matches rules by its module. An atom matches itself.
      Other values match no rules.

  See `allow/3` for the options.

  ## Security

  `can?/3` is not a security boundary. Always call `authorize/3` or
  `authorize!/3` in the code that performs the operation.
  """

  alias Ruxsat.Rule

  @options [:role, :owner, :if]

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Ruxsat, only: [allow: 2, allow: 3]
      Module.register_attribute(__MODULE__, :ruxsat_rules, accumulate: true)
      @before_compile Ruxsat
    end
  end

  @doc """
  Allows `action` on `resource`.

  `resource` is a struct module (`Post`) or an atom (`:dashboard`).

  ## Options

  All given options must pass.

    * `:role` - an atom or a list of atoms. Passes when `subject.role` is one
      of them. If `subject.role` is a list, any overlap passes.
    * `:owner` - `true` or a field name. Passes when `resource.<field>` equals
      `subject.id`. `true` means `:user_id`. A `nil` id never passes.
    * `:if` - a function `(subject, resource) -> boolean`. It can be a remote
      capture, a local capture or an anonymous `fn`.

  ## Examples

      allow :read, Post
      allow :update, Post, role: [:admin, :editor]
      allow :update, Comment, owner: :author_id
      allow :publish, Post, role: :editor, if: &published_allowed?/2

  """
  defmacro allow(action, resource, opts \\ []) do
    env = __CALLER__

    opts = validate_opts!(opts, env)

    rule = %Rule{
      action: validate_action!(action, env),
      resource: validate_resource!(resource, env),
      role: validate_role!(Keyword.fetch(opts, :role), env),
      owner: validate_owner!(Keyword.fetch(opts, :owner), env)
    }

    condition = validate_condition!(Keyword.fetch(opts, :if), env)

    quote do
      @ruxsat_rules {unquote(Macro.escape(rule)), unquote(Macro.escape(condition))}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    entries = env.module |> Module.get_attribute(:ruxsat_rules) |> Enum.reverse()

    dispatch =
      entries
      |> Enum.group_by(fn {rule, _condition} -> {rule.action, rule.resource} end)
      |> Enum.map(fn {{action, resource}, group} ->
        quote do
          defp __ruxsat_rules__(unquote(action), unquote(resource)) do
            unquote(Enum.map(group, &rule_ast/1))
          end
        end
      end)

    quote do
      @doc "Returns all authorization rules in declaration order."
      @spec rules() :: [Ruxsat.Rule.t()]
      def rules, do: unquote(Enum.map(entries, &rule_ast/1))

      @doc "Returns `true` if `subject` may perform `action` on `resource`."
      @spec can?(term, atom, term) :: boolean
      def can?(subject, action, resource) do
        Ruxsat.__can__(rules_for(action, resource), subject, resource)
      end

      @doc "Returns `:ok` if allowed, `{:error, :forbidden}` otherwise."
      @spec authorize(term, atom, term) :: :ok | {:error, :forbidden}
      def authorize(subject, action, resource) do
        if can?(subject, action, resource), do: :ok, else: {:error, :forbidden}
      end

      @doc "Returns `:ok` if allowed, raises `Ruxsat.ForbiddenError` otherwise."
      @spec authorize!(term, atom, term) :: :ok
      def authorize!(subject, action, resource) do
        case authorize(subject, action, resource) do
          :ok ->
            :ok

          {:error, :forbidden} ->
            raise Ruxsat.ForbiddenError,
              action: action,
              resource: Ruxsat.__resource_type__(resource)
        end
      end

      @doc "Explains why `subject` may or may not perform `action` on `resource`."
      @spec explain(term, atom, term) ::
              {:allowed, Ruxsat.Rule.t()}
              | {:denied, :no_rules}
              | {:denied, [{Ruxsat.Rule.t(), Ruxsat.Rule.reason()}]}
      def explain(subject, action, resource) do
        Ruxsat.__explain__(rules_for(action, resource), subject, resource)
      end

      defp rules_for(action, resource) do
        __ruxsat_rules__(action, Ruxsat.__resource_type__(resource))
      end

      unquote_splicing(dispatch)
      defp __ruxsat_rules__(_action, _resource_type), do: []
    end
  end

  defp rule_ast({rule, nil}), do: Macro.escape(rule)

  defp rule_ast({rule, condition}) do
    quote do: %{unquote(Macro.escape(rule)) | if: unquote(condition)}
  end

  ## Runtime

  @doc false
  def __resource_type__(%{__struct__: module}), do: module
  def __resource_type__(atom) when is_atom(atom), do: atom
  def __resource_type__(_other), do: nil

  @doc false
  def __can__(rules, subject, resource) do
    Enum.any?(rules, &(Rule.check(&1, subject, resource) == :ok))
  end

  @doc false
  def __explain__([], _subject, _resource), do: {:denied, :no_rules}

  def __explain__(rules, subject, resource) do
    Enum.reduce_while(rules, {:denied, []}, fn rule, {:denied, failures} ->
      case Rule.check(rule, subject, resource) do
        :ok -> {:halt, {:allowed, rule}}
        {:error, reason} -> {:cont, {:denied, failures ++ [{rule, reason}]}}
      end
    end)
  end

  ## Compile-time validation

  defguardp is_name(term) when is_atom(term) and term not in [nil, true, false]

  defp validate_action!(action, _env) when is_name(action), do: action

  defp validate_action!(action, env) do
    compile_error!(env, "expected action to be an atom, got: #{Macro.to_string(action)}")
  end

  defp validate_resource!(resource, env) do
    # Expanding within a function context keeps the resource a runtime
    # dependency, so changing the resource module does not recompile the policy.
    case Macro.expand_literals(resource, %{env | function: {:rules, 0}}) do
      expanded when is_name(expanded) ->
        expanded

      _ ->
        compile_error!(
          env,
          "expected resource to be a module or an atom, got: #{Macro.to_string(resource)}"
        )
    end
  end

  defp validate_opts!(opts, env) do
    unless Keyword.keyword?(opts) do
      compile_error!(env, "expected options to be a keyword list, got: #{Macro.to_string(opts)}")
    end

    for {key, _value} <- opts, key not in @options do
      compile_error!(env, "unknown option #{inspect(key)}, expected one of: #{inspect(@options)}")
    end

    if length(opts) != length(Keyword.keys(opts) |> Enum.uniq()) do
      compile_error!(env, "duplicate options in: #{Macro.to_string(opts)}")
    end

    opts
  end

  defp validate_role!(:error, _env), do: nil
  defp validate_role!({:ok, role}, _env) when is_name(role), do: [role]

  defp validate_role!({:ok, [_ | _] = roles}, env) do
    if Enum.all?(roles, &is_name/1), do: roles, else: invalid_role!(roles, env)
  end

  defp validate_role!({:ok, role}, env), do: invalid_role!(role, env)

  defp invalid_role!(role, env) do
    compile_error!(
      env,
      "expected :role to be an atom or a non-empty list of atoms, got: #{Macro.to_string(role)}"
    )
  end

  defp validate_owner!(:error, _env), do: nil
  defp validate_owner!({:ok, true}, _env), do: :user_id
  defp validate_owner!({:ok, field}, _env) when is_name(field), do: field

  defp validate_owner!({:ok, owner}, env) do
    compile_error!(
      env,
      "expected :owner to be true or a field name, got: #{Macro.to_string(owner)}"
    )
  end

  defp validate_condition!(:error, _env), do: nil

  defp validate_condition!({:ok, {:&, _, [{:/, _, [_, arity]}]} = condition}, env)
       when is_integer(arity) do
    if arity == 2, do: condition, else: invalid_arity!(condition, env)
  end

  defp validate_condition!({:ok, {:&, _, _} = condition}, _env), do: condition

  defp validate_condition!({:ok, {:fn, _, clauses} = condition}, env) do
    if Enum.all?(clauses, &(fn_arity(&1) == 2)),
      do: condition,
      else: invalid_arity!(condition, env)
  end

  defp validate_condition!({:ok, condition}, env) do
    compile_error!(
      env,
      "expected :if to be a function capture or an anonymous function, " <>
        "got: #{Macro.to_string(condition)}"
    )
  end

  defp fn_arity({:->, _, [[{:when, _, args_and_guard}], _body]}), do: length(args_and_guard) - 1
  defp fn_arity({:->, _, [args, _body]}), do: length(args)

  defp invalid_arity!(condition, env) do
    compile_error!(
      env,
      "expected :if to be a function of arity 2 (subject, resource), " <>
        "got: #{Macro.to_string(condition)}"
    )
  end

  defp compile_error!(env, description) do
    raise CompileError, file: env.file, line: env.line, description: description
  end
end
