defmodule TypeGuard.UncheckedTest do
  use ExUnit.Case, async: true

  alias TypeGuard.Fixtures.{Strict, StrictInOneUse}
  alias TypeGuard.UncheckedError

  describe "unchecked: :raise at run time" do
    test "a type that the other module checks is checked" do
      assert TypeGuard.check(Strict, :id, "8 bytes!")
      refute TypeGuard.check(Strict, :id, "short")
    end

    test "a module that does not use TypeGuard raises" do
      message =
        ~r/Strict uses TypeGuard with unchecked: :raise and checks a value against TypeGuard.Fixtures.Plain.t\(\), but TypeGuard.Fixtures.Plain does not use TypeGuard/

      assert_raise UncheckedError, message, fn -> TypeGuard.check(Strict, :plain, 1) end
    end

    test "a type that the other module leaves out raises" do
      assert_raise UncheckedError, ~r/OnlyId.name\(\), but .*OnlyId does not check it/, fn ->
        TypeGuard.check(Strict, :name, "a")
      end
    end

    test "a type that the other module does not define raises" do
      assert_raise UncheckedError, ~r/Ids.no_such_type\(\), but .*Ids does not check it/, fn ->
        TypeGuard.check(Strict, :missing, "a")
      end
    end

    test "a recursive type of the module calls its own check" do
      assert TypeGuard.check(Strict, :tree, %{value: 1, children: [%{value: 2, children: []}]})
      refute TypeGuard.check(Strict, :tree, %{value: 1, children: [%{value: :two, children: []}]})
    end

    test "a typespec of another application stays trusted where it cannot be checked" do
      assert TypeGuard.check(Strict, :queue, :not_a_queue)
    end

    test "one use with :raise makes the module raise" do
      assert_raise UncheckedError, ~r/Plain does not use TypeGuard/, fn ->
        TypeGuard.check(StrictInOneUse, :t, 1)
      end
    end
  end

  # Each body compiles with the default `:trust`. With `:raise`, it fails to
  # compile with the message.
  @compile_errors [
    {"@type t() :: Keyword.t(integer())", "t() cannot check Keyword.t/1, a type with parameters"},
    {"@type t() :: MapSet.t(integer())", "t() cannot check the parameters of MapSet.t/1"},
    {"@type t() :: Decimal.no_such()",
     "t() cannot check Decimal.no_such/0, which has no typespec"},
    {"@type t() :: wrap(integer())\n@typep wrap(a) :: [a]",
     "t() cannot check wrap/1, a type with parameters"},
    {"@type t() :: node_()\n@typep node_() :: %{children: [node_()]}",
     "t() cannot check node_(), a recursive private type"},
    {"@type t() :: dynamic()",
     "t() cannot check dynamic(), a built-in type that it does not know"},
    {"@type t() :: TypeGuard.unchecked()",
     "t() cannot check TypeGuard.unchecked(), which marks a value as not checked"},
    {"defstruct [:a]\n@type t() :: %__MODULE__{a: Keyword.t(integer())}",
     "the field a of t() cannot check Keyword.t/1"}
  ]

  describe "unchecked: :raise at compile time" do
    for {{body, message}, index} <- Enum.with_index(@compile_errors) do
      test "#{message}" do
        body = unquote(body)
        index = unquote(index)

        assert [:t] == TypeGuard.checked_types(compile("Trusted#{index}", "use TypeGuard", body))

        assert_raise UncheckedError,
                     ~r/Strict#{index} uses TypeGuard with unchecked: :raise, but the check of #{Regex.escape(unquote(message))}/,
                     fn ->
                       compile("Strict#{index}", "use TypeGuard, unchecked: :raise", body)
                     end
      end
    end

    test "a recursive type that the module does not check" do
      body = "@type t() :: tree()\n@type tree() :: %{children: [tree()]}"

      compile("TrustedTree", "use TypeGuard, only: [:t]", body)

      assert_raise UncheckedError,
                   ~r/tree\(\), a recursive type that the module does not check/,
                   fn ->
                     compile("StrictTree", "use TypeGuard, only: [:t], unchecked: :raise", body)
                   end
    end

    test "a form of type that the checker does not know" do
      ctx = %{strict?: true, env: __ENV__, root: "t()"}
      v = Macro.var(:v, nil)

      assert TypeGuard.Compiler.check({:unknown}, v, %{ctx | strict?: false})

      assert_raise UncheckedError,
                   ~r/cannot check \{:unknown\}, which is not a type that it knows/,
                   fn ->
                     TypeGuard.Compiler.check({:unknown}, v, ctx)
                   end
    end

    test "the option takes :trust or :raise" do
      assert_raise ArgumentError, ~r/:unchecked is :trust or :raise, got: :maybe/, fn ->
        compile("BadUnchecked", "use TypeGuard, unchecked: :maybe", "@type t() :: atom()")
      end
    end
  end

  defp compile(name, use, body) do
    module = Module.concat(TypeGuard.Fixtures.Unchecked, name)

    Code.compile_string("""
    defmodule #{inspect(module)} do
      #{use}
      #{body}
    end
    """)

    module
  end
end
