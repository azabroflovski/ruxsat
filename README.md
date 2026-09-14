# Ruxsat

Small, explicit authorization for Elixir.

You declare `allow` rules for actions on resources. Everything else is denied.
When the logic gets complex, you write a plain Elixir function. There is no
policy engine, no process state and no framework dependency.

## Installation

Not published on Hex yet. When it is:

```elixir
def deps do
  [{:ruxsat, "~> 0.1.0"}]
end
```

To call `allow` without parentheses, add to `.formatter.exs`:

```elixir
import_deps: [:ruxsat]
```

## Example

```elixir
defmodule MyApp.Authorization do
  use Ruxsat

  alias MyApp.{Comment, Post}

  allow :read, Post
  allow :create, Post, role: :editor
  allow :update, Post, role: [:admin, :editor]
  allow :update, Post, owner: true
  allow :delete, Post, role: :admin
  allow :update, Comment, owner: :author_id
  allow :publish, Post, if: &__MODULE__.can_publish?/2

  def can_publish?(user, post), do: user.verified and not post.archived
end
```

```elixir
MyApp.Authorization.can?(user, :update, post)
#=> true

MyApp.Authorization.authorize(user, :delete, post)
#=> {:error, :forbidden}

MyApp.Authorization.authorize!(user, :delete, post)
#=> ** (Ruxsat.ForbiddenError) forbidden: :delete on MyApp.Post
```

Subjects and resources are plain structs or maps. The subject can be `nil`,
for example a guest.

## Rules

- No matching rule means access is denied.
- Several rules for the same action: **any** one passing is enough.
- Several options in one rule: **all** must pass.
- There are no deny rules, so rules never conflict and their order does not
  matter.

The resource can be a struct (`post`) or a module or atom (`Post`,
`:dashboard`). Passing the module is useful before a record exists:

```elixir
MyApp.Authorization.can?(user, :create, Post)
```

A plain map resource has no type, so it matches no rules.

### Roles

```elixir
allow :delete, Post, role: :admin
allow :update, Post, role: [:admin, :editor]
```

A role rule checks `subject.role`, which can be an atom or a list of atoms.
If your roles are stored differently, use `if:`.

### Ownership

```elixir
allow :update, Post, owner: true             # post.user_id == user.id
allow :update, Comment, owner: :author_id    # comment.author_id == user.id
```

A `nil` id never counts as ownership. Ownership cannot be proven without a
resource instance, so `can?(user, :update, Post)` is `false` for owner rules.

### Custom conditions

```elixir
allow :update, Post, if: &__MODULE__.can_edit?/2
allow :update, Post, if: &can_edit?/2
allow :read, Post, if: fn user, post -> post.public or user.staff end
```

The function receives `(subject, resource)` and must return a boolean. Any
other return value raises. You can combine it with other options:
`role: :editor, if: &within_quota?/2`.

## `can?` vs `authorize`

- `can?/3` returns a boolean. Use it to decide what the UI shows.
- `authorize/3` returns `:ok` or `{:error, :forbidden}`. Use it where the
  operation is performed:

  ```elixir
  def delete_post(user, post) do
    with :ok <- Authorization.authorize(user, :delete, post) do
      Repo.delete(post)
    end
  end
  ```

- `authorize!/3` returns `:ok` or raises `Ruxsat.ForbiddenError`.

## Debugging

```elixir
MyApp.Authorization.explain(user, :update, post)
#=> {:denied,
#    [{%Ruxsat.Rule{role: [:admin, :editor], ...}, :missing_role},
#     {%Ruxsat.Rule{owner: :user_id, ...}, :not_owner}]}

MyApp.Authorization.explain(user, :archive, post)
#=> {:denied, :no_rules}

MyApp.Authorization.rules()
#=> [%Ruxsat.Rule{action: :read, resource: MyApp.Post, ...}, ...]
```

The possible reasons are `:missing_role`, `:not_owner` and `:condition_failed`.
Invalid rules, such as unknown options or a wrong `if:` arity, fail at compile
time.

## Security model

- **`can?/3` is not a security boundary.** Hiding a button does not protect
  anything. Call `authorize/3` or `authorize!/3` in the code that actually
  performs the operation, such as a context function or command handler.
- `authorize/3` deliberately returns only `:forbidden`. To see the reasons,
  use `explain/3`, and do not send its output to clients.
- Ruxsat never touches the database. A check costs whatever your `if:`
  functions cost, so avoid hidden queries in them or load the data beforehand.

## Limitations

- No deny rules, wildcards or action lists.
- No query scoping. It will not filter an Ecto query for you.
- No Plug, Phoenix or LiveView integration.
- The role field (`:role`) and the id field (`:id`) are fixed. Use `if:` for
  anything else.

## Roadmap

These are ideas only, and will be added only if they are required by real use:

- query scoping (`scope(user, :read, Post)`) without an Ecto dependency;
- optional Plug helpers in a separate package.
