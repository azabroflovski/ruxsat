defmodule RuxsatFilterTest.User do
  defstruct [:id, :role]
end

defmodule RuxsatFilterTest.Post do
  defstruct [:id, :user_id, published: false]
end

defmodule RuxsatFilterTest.Tag do
  defstruct [:id]
end

defmodule RuxsatFilterTest do
  use ExUnit.Case, async: true

  alias RuxsatFilterTest.{Post, Tag, User}

  defmodule Policy do
    use Ruxsat

    allow :read, Post, role: :admin
    allow :read, Post, where: [published: true]
    allow :read, Post, owner: true
    allow :update, Post, role: :editor, owner: true
    allow :review, Post, role: :editor, where: [published: false]
    allow :review, Post, role: [:editor, :admin], where: [published: false]
    allow :edit_draft, Post, owner: true, where: [published: false]
    allow :list, Post
    allow :show, Tag, where: [published: true]
    allow :archive, Post, role: :admin
    allow :archive, Post, if: &__MODULE__.archivable?/2

    def archivable?(_user, %Post{published: published}), do: not published
    def archivable?(_user, _post), do: false
  end

  @admin %User{id: 1, role: :admin}
  @editor %User{id: 2, role: :editor}
  @viewer %User{id: 3, role: :viewer}

  describe "where" do
    test "allows when every field matches" do
      assert Policy.can?(nil, :read, %Post{published: true})
    end

    test "denies when a field does not match" do
      refute Policy.can?(nil, :read, %Post{published: false, user_id: 99})
    end

    test "denies when there is no resource instance" do
      refute Policy.can?(@editor, :review, Post)
    end

    test "combines with other options using AND" do
      assert Policy.can?(@viewer, :edit_draft, %Post{user_id: 3, published: false})
      refute Policy.can?(@viewer, :edit_draft, %Post{user_id: 3, published: true})
      refute Policy.can?(@viewer, :edit_draft, %Post{user_id: 99, published: false})
    end

    test "raises when the resource struct lacks the field" do
      assert_raise KeyError, fn -> Policy.can?(nil, :show, %Tag{}) end
    end

    test "is reported by explain/3" do
      assert {:denied, [{rule, :where_mismatch}, {_rule, :where_mismatch}]} =
               Policy.explain(@editor, :review, %Post{published: true})

      assert rule.where == [published: false]
    end
  end

  describe "filter/3" do
    test "returns :all when a rule without record conditions passes" do
      assert Policy.filter(@admin, :read, Post) == :all
      assert Policy.filter(nil, :list, Post) == :all
    end

    test "returns one set per passing rule in declaration order" do
      assert Policy.filter(@viewer, :read, Post) == {:any, [[published: true], [user_id: 3]]}
    end

    test "skips owner rules when the subject has no id" do
      assert Policy.filter(nil, :read, Post) == {:any, [[published: true]]}
      assert Policy.filter(%User{id: nil}, :read, Post) == {:any, [[published: true]]}
    end

    test "skips rules whose role does not match" do
      assert Policy.filter(@editor, :update, Post) == {:any, [[user_id: 2]]}
      assert Policy.filter(@viewer, :update, Post) == :none
    end

    test "puts owner and where of one rule into one set" do
      assert Policy.filter(@viewer, :edit_draft, Post) ==
               {:any, [[user_id: 3, published: false]]}
    end

    test "removes duplicate sets" do
      assert Policy.filter(@editor, :review, Post) == {:any, [[published: false]]}
    end

    test "returns :none when there are no rules" do
      assert Policy.filter(@admin, :destroy, Post) == :none
      assert Policy.filter(@admin, :read, :unknown) == :none
    end

    test "raises when a rule uses :if, regardless of the subject" do
      for subject <- [@admin, @viewer, nil] do
        assert_raise ArgumentError, ~r/:if/, fn -> Policy.filter(subject, :archive, Post) end
      end
    end

    test "agrees with can?/3 for every record" do
      subjects = [@admin, @editor, @viewer, %User{id: nil}, %{id: 2}, nil]

      records =
        for user_id <- [nil, 1, 2, 3], published <- [true, false] do
          %Post{user_id: user_id, published: published}
        end

      for subject <- subjects,
          action <- [:read, :update, :review, :edit_draft, :list, :destroy],
          record <- records do
        filter = Policy.filter(subject, action, Post)

        assert matches?(filter, record) == Policy.can?(subject, action, record),
               "#{inspect(action)} disagrees for #{inspect(subject)} on #{inspect(record)}"
      end
    end
  end

  describe "compile-time validation of where" do
    test "rejects values that are not a non-empty keyword list" do
      assert_compile_error(~r/expected :where/, "allow :read, Post, where: []")
      assert_compile_error(~r/expected :where/, "allow :read, Post, where: :published")
    end

    test "rejects values that are not literals" do
      assert_compile_error(~r/expected :where/, "allow :read, Post, where: [deleted_at: nil]")
      assert_compile_error(~r/expected :where/, "allow :read, Post, where: [status: [:a, :b]]")
      assert_compile_error(~r/expected :where/, "allow :read, Post, where: [count: 1 + 1]")
    end

    test "rejects duplicate fields" do
      assert_compile_error(
        ~r/duplicate fields in :where/,
        "allow :read, Post, where: [a: 1, a: 2]"
      )
    end
  end

  defp matches?(:all, _record), do: true
  defp matches?(:none, _record), do: false

  defp matches?({:any, sets}, record) do
    Enum.any?(sets, fn set ->
      Enum.all?(set, fn {field, value} -> Map.fetch!(record, field) == value end)
    end)
  end

  defp assert_compile_error(message, code) do
    module = "RuxsatFilterTest.Invalid#{System.unique_integer([:positive])}"

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
