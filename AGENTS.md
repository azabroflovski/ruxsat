# AGENTS.md

Guide for AI agents and contributors working on Ruxsat.

## Sources of truth

1. **This file.** It holds the design, the semantics, and the scope.
2. **The tests.** They pin down the public behavior.
3. `README.md` only describes the API that exists. It is never a design source.
   When the API changes, update this file and the tests first, then the README.

## What Ruxsat is

Ruxsat is a small authorization library for Elixir. It answers one question:
*may this subject perform this action on this resource?*

```elixir
defmodule MyApp.Authorization do
  use Ruxsat

  allow :read, Post
  allow :update, Post, role: [:admin, :editor]
  allow :update, Post, owner: true
  allow :publish, Post, if: &__MODULE__.can_publish?/2

  def can_publish?(user, post), do: user.verified and not post.archived
end

MyApp.Authorization.can?(user, :update, post)       # boolean
MyApp.Authorization.authorize(user, :update, post)  # :ok | {:error, :forbidden}
MyApp.Authorization.authorize!(user, :update, post) # :ok or raises
MyApp.Authorization.explain(user, :update, post)    # debugging
MyApp.Authorization.rules()                         # introspection
```

The target: an Elixir developer understands it in 10 minutes and uses it in 5.

## Principles

- Small, explicit, idiomatic Elixir. Plain functions over DSL.
- No runtime dependencies. No Phoenix, Plug, Ecto or LiveView in core.
- No GenServer, ETS, registries or process state. Rules are compiled into
  the policy module.
- No behaviours or protocols the user must implement. Subjects and resources
  are plain maps and structs.
- The library never does I/O. If a condition needs the database, that is the
  user's `if:` function.
- Deny by default.

## Architecture

```text
lib/ruxsat.ex                  use Ruxsat, allow/2,3, compile-time validation,
                               @before_compile code generation, runtime evaluation
lib/ruxsat/rule.ex             %Ruxsat.Rule{} and evaluation of a single rule
lib/ruxsat/forbidden_error.ex  exception raised by authorize!/3
```

### Compile model

1. `use Ruxsat` imports `allow/2,3`, registers an accumulating module
   attribute and sets `@before_compile Ruxsat`.
2. `allow` validates its arguments **at compile time**. Invalid input raises
   `CompileError`. It then stores the rule, plus the quoted `if:` expression,
   in the attribute.
3. `__before_compile__` generates, in the user's module:
   - a private dispatch function with one clause per `{action, resource}`
     returning that pair's rules, plus a catch-all returning `[]`;
   - `rules/0`, `can?/3`, `authorize/3`, `authorize!/3` and `explain/3`. Each
     is a thin wrapper that calls the evaluation functions in `Ruxsat`.
4. `if:` expressions are injected as code, not stored as data. That is why
   remote captures, local captures and `fn` all work.

Keep the evaluation logic in plain functions (`Ruxsat`, `Ruxsat.Rule`), not in
generated code. Generated code should stay trivial.

## Semantics (normative)

- **Deny by default.** No matching rule means forbidden. This includes
  unknown actions and resources.
- **Rules combine with OR.** One passing rule is enough.
- **Options within one rule combine with AND.** They are evaluated in the
  order `role`, `owner`, `if`, and evaluation stops at the first failure.
- **There are no deny rules.** So there are no conflicts and no rule ordering
  semantics.
- **Resource type:** a struct matches by `__struct__`, and an atom (module or
  plain atom) matches itself. A plain map or any other value has no type and
  matches no rules.
- **`role:`** takes an atom or a non-empty list of atoms, stored as a list.
  It passes when `subject.role` is one of them. If `subject.role` is a list,
  any overlap passes. A `nil` subject or a subject without `:role` fails.
- **`owner:`** takes `true` (field `:user_id`) or a field atom. It passes when
  `resource.<field> == subject.id` and `subject.id` is not `nil`. If the
  resource is not a map (for example `Post` in a `:create` check), it fails.
  If a struct resource lacks the field, `KeyError` is raised because that is a
  programmer error.
- **`if:`** takes a capture or `fn` of arity 2, called as
  `(subject, resource)`. It must return a boolean. Any other return value
  raises `ArgumentError`.
- **Subject** can be any term. `nil` means a guest.

### Return values

- `can?/3` returns `boolean`.
- `authorize/3` returns `:ok | {:error, :forbidden}`. It never returns detailed
  reasons, which could leak information and are ambiguous across several rules.
- `authorize!/3` returns `:ok` or raises `Ruxsat.ForbiddenError`. The message
  contains only the action and the resource type, never the subject.
- `explain/3` returns one of:
  - `{:allowed, %Ruxsat.Rule{}}`: the first rule that passed.
  - `{:denied, :no_rules}`: no rule exists for this action and resource.
  - `{:denied, [{%Ruxsat.Rule{}, reason}]}`: each rule that failed, in
    declaration order. `reason` is one of `:missing_role`, `:not_owner`,
    `:condition_failed`.
- `rules/0` returns all rules in declaration order.

### Security model

`can?/3` is for UI decisions such as showing a button. It is not a security
boundary. The code that performs the operation must call `authorize/3` or
`authorize!/3`.

## Out of scope (MVP)

Not in the MVP: deny/cannot rules, wildcards (`:all`, `:manage`), action
lists, `permissions(subject)`, query scoping (Ecto), Plug/Phoenix/LiveView
integration, field-level permissions, rules loaded at runtime or from the
database, string role coercion, configurable role or id fields, and
`plug_status` on the exception.

## Development rules

- Before adding any feature, ask: **is this required for the core use case?**
  If not, do not add it. Propose it to the maintainer instead.
- Adding a runtime dependency needs explicit maintainer approval.
- Test the public API only: generated functions, compile errors and
  documented raises. Do not test private helpers or generated function names.
- Every semantic rule above must have a test. If you change the semantics,
  change this file in the same commit.
- Prefer a clear `CompileError` over a runtime surprise.
- Keep `lib/` small. If a change grows it significantly, stop and reconsider.
- Any user-visible change to the public API, semantics or error messages gets
  an entry under `## [Unreleased]` in `CHANGELOG.md`. Write it for users, not
  as a list of commits. Mark breaking changes with **Breaking** and say how to
  migrate. Internal refactoring and test-only changes do not need an entry.
- To release: move `Unreleased` to a new version section with a date, bump
  `@version` in `mix.exs`, commit, tag `vX.Y.Z`, push, then `mix hex.publish`.

## Commands

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```
