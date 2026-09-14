defmodule RuxsatTest.User do
  defstruct [:id, :role, :email, verified: false]
end

defmodule RuxsatTest.Post do
  defstruct [:id, :user_id, archived: false]
end

defmodule RuxsatTest.Comment do
  defstruct [:id, :author_id]
end

defmodule RuxsatTest.Tag do
  defstruct [:id, :name]
end

defmodule RuxsatTest do
  use ExUnit.Case, async: true

  alias RuxsatTest.{Comment, Post, Tag, User}

  defmodule Policy do
    use Ruxsat

    allow :read, Post
    allow :create, Post, role: :editor
    allow :update, Post, role: [:admin, :editor]
    allow :update, Post, owner: true
    allow :delete, Post, role: :admin
    allow :update, Comment, owner: :author_id
    allow :update, Tag, owner: true
    allow :publish, Post, role: :editor, owner: true
    allow :archive, Post, if: &__MODULE__.can_archive?/2

    allow :feature, Post,
      if: fn
        %{verified: verified}, _post -> verified
        _, _ -> false
      end

    allow :comment, Post, if: &open?/2
    allow :broken, Post, if: fn _user, _post -> nil end
    allow :view, :dashboard, role: :admin

    def can_archive?(%{id: id}, %Post{user_id: id, archived: false}), do: true
    def can_archive?(_user, _post), do: false

    defp open?(_user, %Post{archived: archived}), do: not archived
    defp open?(_user, _post), do: false
  end

  defmodule EmptyPolicy do
    use Ruxsat
  end

  @admin %User{id: 1, role: :admin}
  @editor %User{id: 2, role: :editor}
  @viewer %User{id: 3, role: :viewer}

  describe "allow without options" do
    test "allows any subject" do
      post = %Post{user_id: 99}

      assert Policy.can?(@viewer, :read, post)
      assert Policy.can?(nil, :read, post)
      assert Policy.can?(%{name: "plain map"}, :read, post)
    end

    test "matches the resource module when there is no instance" do
      assert Policy.can?(@viewer, :read, Post)
    end
  end

  describe "deny by default" do
    test "denies unknown actions" do
      refute Policy.can?(@admin, :destroy, %Post{})
    end

    test "denies resources without rules" do
      refute Policy.can?(@admin, :read, %Comment{})
      refute Policy.can?(@admin, :read, Comment)
    end

    test "denies resources without a type" do
      refute Policy.can?(@admin, :read, %{user_id: 1})
      refute Policy.can?(@admin, :read, nil)
      refute Policy.can?(@admin, :read, "post")
    end

    test "denies everything in a policy without rules" do
      refute EmptyPolicy.can?(@admin, :read, %Post{})
      assert EmptyPolicy.authorize(@admin, :read, %Post{}) == {:error, :forbidden}
      assert EmptyPolicy.rules() == []
    end
  end

  describe "role" do
    test "allows the matching role" do
      assert Policy.can?(@editor, :create, Post)
    end

    test "denies other roles" do
      refute Policy.can?(@admin, :create, Post)
      refute Policy.can?(@viewer, :create, Post)
    end

    test "denies subjects without a role" do
      refute Policy.can?(nil, :create, Post)
      refute Policy.can?(%{id: 2}, :create, Post)
      refute Policy.can?(%User{id: 2, role: nil}, :create, Post)
    end

    test "works with plain map subjects" do
      assert Policy.can?(%{role: :editor}, :create, Post)
    end

    test "works with atom resources" do
      assert Policy.can?(@admin, :view, :dashboard)
      refute Policy.can?(@editor, :view, :dashboard)
    end
  end

  describe "multiple roles" do
    test "allows any listed role" do
      post = %Post{user_id: 99}

      assert Policy.can?(@admin, :update, post)
      assert Policy.can?(@editor, :update, post)
      refute Policy.can?(@viewer, :update, post)
    end

    test "allows a subject with a list of roles when any overlaps" do
      assert Policy.can?(%{role: [:viewer, :editor]}, :create, Post)
      refute Policy.can?(%{role: [:viewer, :guest]}, :create, Post)
      refute Policy.can?(%{role: []}, :create, Post)
    end
  end

  describe "owner" do
    test "allows the owner" do
      assert Policy.can?(@viewer, :update, %Post{user_id: @viewer.id})
    end

    test "denies non-owners" do
      refute Policy.can?(@viewer, :update, %Post{user_id: 99})
    end

    test "uses a custom field" do
      assert Policy.can?(@viewer, :update, %Comment{author_id: @viewer.id})
      refute Policy.can?(@viewer, :update, %Comment{author_id: 99})
    end

    test "never treats nil ids as ownership" do
      refute Policy.can?(%User{id: nil}, :update, %Post{user_id: nil})
      refute Policy.can?(%{}, :update, %Post{user_id: nil})
      refute Policy.can?(nil, :update, %Post{user_id: nil})
    end

    test "denies when there is no resource instance" do
      refute Policy.can?(@viewer, :update, Post)
    end

    test "works with plain map subjects" do
      assert Policy.can?(%{id: 5}, :update, %Post{user_id: 5})
    end

    test "raises when the resource struct lacks the owner field" do
      assert_raise KeyError, fn -> Policy.can?(@viewer, :update, %Tag{}) end
    end
  end

  describe "options within one rule" do
    test "all must pass" do
      assert Policy.can?(@editor, :publish, %Post{user_id: @editor.id})
      refute Policy.can?(@editor, :publish, %Post{user_id: 99})
      refute Policy.can?(@viewer, :publish, %Post{user_id: @viewer.id})
    end
  end

  describe "multiple rules" do
    test "any passing rule allows" do
      # role rule passes, owner rule fails
      assert Policy.can?(@editor, :update, %Post{user_id: 99})
      # role rule fails, owner rule passes
      assert Policy.can?(@viewer, :update, %Post{user_id: @viewer.id})
      # both fail
      refute Policy.can?(@viewer, :update, %Post{user_id: 99})
    end
  end

  describe "if" do
    test "accepts a remote capture" do
      assert Policy.can?(@viewer, :archive, %Post{user_id: @viewer.id})
      refute Policy.can?(@viewer, :archive, %Post{user_id: @viewer.id, archived: true})
    end

    test "accepts an anonymous function" do
      assert Policy.can?(%User{verified: true}, :feature, %Post{})
      refute Policy.can?(%User{verified: false}, :feature, %Post{})
      refute Policy.can?(nil, :feature, %Post{})
    end

    test "accepts a local capture of a private function" do
      assert Policy.can?(nil, :comment, %Post{})
      refute Policy.can?(nil, :comment, %Post{archived: true})
    end

    test "raises when the condition does not return a boolean" do
      assert_raise ArgumentError, ~r/to return a boolean, got: nil/, fn ->
        Policy.can?(@admin, :broken, %Post{})
      end
    end
  end

  describe "authorize/3" do
    test "returns :ok when allowed" do
      assert Policy.authorize(@admin, :delete, %Post{}) == :ok
    end

    test "returns {:error, :forbidden} when denied" do
      assert Policy.authorize(@editor, :delete, %Post{}) == {:error, :forbidden}
      assert Policy.authorize(@editor, :unknown, %Post{}) == {:error, :forbidden}
    end
  end

  describe "authorize!/3" do
    test "returns :ok when allowed" do
      assert Policy.authorize!(@admin, :delete, %Post{}) == :ok
    end

    test "raises Ruxsat.ForbiddenError when denied" do
      error =
        assert_raise Ruxsat.ForbiddenError, fn ->
          Policy.authorize!(%User{id: 7, email: "secret@example.com"}, :delete, %Post{})
        end

      assert error.action == :delete
      assert error.resource == Post
      assert Exception.message(error) == "forbidden: :delete on RuxsatTest.Post"
      refute Exception.message(error) =~ "secret"
    end
  end

  describe "explain/3" do
    test "returns the first passing rule" do
      assert {:allowed, rule} = Policy.explain(@editor, :update, %Post{user_id: @editor.id})
      assert rule.role == [:admin, :editor]
    end

    test "returns every failing rule with its reason" do
      assert {:denied, [{role_rule, :missing_role}, {owner_rule, :not_owner}]} =
               Policy.explain(@viewer, :update, %Post{user_id: 99})

      assert role_rule.role == [:admin, :editor]
      assert owner_rule.owner == :user_id
    end

    test "reports a failed condition" do
      assert {:denied, [{_rule, :condition_failed}]} =
               Policy.explain(@viewer, :archive, %Post{user_id: 99})
    end

    test "reports when there are no rules" do
      assert Policy.explain(@admin, :destroy, %Post{}) == {:denied, :no_rules}
      assert Policy.explain(@admin, :read, %{}) == {:denied, :no_rules}
    end

    test "agrees with can?/3" do
      post = %Post{user_id: @viewer.id}

      for subject <- [@admin, @editor, @viewer, nil],
          action <- [:read, :create, :update, :delete, :publish, :destroy] do
        allowed? = match?({:allowed, _}, Policy.explain(subject, action, post))
        assert allowed? == Policy.can?(subject, action, post)
      end
    end
  end

  describe "rules/0" do
    test "returns rules in declaration order with normalized options" do
      rules = Policy.rules()

      assert [
               %Ruxsat.Rule{action: :read, resource: Post, role: nil, owner: nil, if: nil},
               %Ruxsat.Rule{action: :create, resource: Post, role: [:editor]},
               %Ruxsat.Rule{action: :update, resource: Post, role: [:admin, :editor]},
               %Ruxsat.Rule{action: :update, resource: Post, owner: :user_id},
               %Ruxsat.Rule{action: :delete, resource: Post, role: [:admin]},
               %Ruxsat.Rule{action: :update, resource: Comment, owner: :author_id}
               | _
             ] = rules

      archive = Enum.find(rules, &(&1.action == :archive))
      assert is_function(archive.if, 2)
    end
  end

  describe "compile-time validation" do
    test "rejects an action that is not an atom" do
      assert_compile_error(~r/expected action to be an atom/, ~s|allow "read", Post|)
    end

    test "rejects a resource that is not a module or an atom" do
      assert_compile_error(
        ~r/expected resource to be a module or an atom/,
        ~s|allow :read, "post"|
      )
    end

    test "rejects options that are not a keyword list" do
      assert_compile_error(~r/expected options to be a keyword list/, "allow :read, Post, :admin")
    end

    test "rejects unknown options" do
      assert_compile_error(~r/unknown option :rol/, "allow :read, Post, rol: :admin")
    end

    test "rejects duplicate options" do
      assert_compile_error(~r/duplicate options/, "allow :read, Post, role: :a, role: :b")
    end

    test "rejects invalid roles" do
      assert_compile_error(~r/expected :role/, ~s|allow :read, Post, role: "admin"|)
      assert_compile_error(~r/expected :role/, "allow :read, Post, role: []")
      assert_compile_error(~r/expected :role/, "allow :read, Post, role: nil")
    end

    test "rejects invalid owner" do
      assert_compile_error(~r/expected :owner/, "allow :read, Post, owner: false")
      assert_compile_error(~r/expected :owner/, ~s|allow :read, Post, owner: "user_id"|)
    end

    test "rejects conditions that are not functions" do
      assert_compile_error(
        ~r/expected :if to be a function capture/,
        "allow :read, Post, if: true"
      )
    end

    test "rejects conditions with the wrong arity" do
      assert_compile_error(~r/arity 2/, "allow :read, Post, if: &Kernel.is_nil/1")
      assert_compile_error(~r/arity 2/, "allow :read, Post, if: fn user -> user end")
    end
  end

  defp assert_compile_error(message, code) do
    module = "RuxsatTest.Invalid#{System.unique_integer([:positive])}"

    assert_raise CompileError, message, fn ->
      Code.compile_string("""
      defmodule #{module} do
        use Ruxsat
        #{code}
      end
      """)
    end
  end
end
