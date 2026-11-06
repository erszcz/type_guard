defmodule TypeGuardTest do
  use ExUnit.Case, async: true

  alias TypeGuard.Fixtures.{Ids, Line, Order, Plain, Shapes, UsesPlain}

  defp check(type, value), do: TypeGuard.check(Shapes, type, value)

  describe "check/3 with local types" do
    test "atom unions, ranges and tuples" do
      assert check(:color, :red)
      refute check(:color, :pink)
      assert check(:level, 10)
      refute check(:level, 11)
      assert check(:offset, -5)
      refute check(:offset, -6)
      assert check(:pair, {:a, 1})
      refute check(:pair, {:a, 1.0})
      refute check(:pair, {:a, 1, 2})
      assert check(:triple, {1, 2, 3})
      refute check(:triple, {1, 2})
    end

    test "lists" do
      assert check(:tags, [])
      assert check(:tags, ["a", "b"])
      refute check(:tags, ["a", :b])
      refute check(:tags, "a")
      assert check(:nonempty_tags, ["a"])
      refute check(:nonempty_tags, [])
      assert check(:options, verbose: true, depth: 2)
      refute check(:options, verbose: 1)
      refute check(:options, other: true)
    end

    test "maps" do
      assert check(:counts, %{"a" => 1})
      refute check(:counts, %{"a" => -1})
      refute check(:counts, %{a: 1})
      assert check(:point, %{x: 1, y: 2.5})
      refute check(:point, %{x: 1})
      refute check(:point, %{x: 1, y: 2, z: 3})
      assert check(:empty, %{})
      refute check(:empty, %{a: 1})
    end

    test "required(:key) requires the key, like %{key: t}" do
      assert check(:required_key, %{id: "a"})
      assert check(:required_key, %{id: "a", note: "b"})
      refute check(:required_key, %{note: "b"})
      refute check(:required_key, %{})
      refute check(:required_key, %{id: 1})
      refute check(:required_key, %{id: "a", other: 1})
      assert check(:required_integer_key, %{1 => "a"})
      refute check(:required_integer_key, %{})
    end

    test "required(type) and a bare key type require at least one entry" do
      for type <- [:required_key_type, :bare_key_type] do
        assert check(type, %{"a" => 1})
        assert check(type, %{"a" => 1, "b" => 2})
        refute check(type, %{})
        refute check(type, %{"a" => "not an integer"})
        refute check(type, %{"a" => 1, "b" => "not an integer"})
        refute check(type, %{a: 1})
      end
    end

    test "required(type) with an unchecked key and value requires one entry of that key type" do
      assert check(:required_any_entry, %{a: 1})
      refute check(:required_any_entry, %{})
      refute check(:required_any_entry, %{"a" => 1})
    end

    test "optional(type) allows no entry" do
      assert check(:counts, %{})
    end

    test "a struct is a map with a :__struct__ entry, so it does not raise" do
      struct = %TypeGuard.Fixtures.Settings{theme: :light}

      refute check(:counts, struct)
      refute check(:required_key_type, struct)
      assert check(:required_any_entry, struct)
    end

    test "bitstrings" do
      assert check(:digest, :crypto.hash(:sha256, "x"))
      refute check(:digest, "short")
      assert check(:bytes, "any bytes")
      refute check(:bytes, <<1::3>>)
    end

    test "a recursive type calls its own check" do
      assert check(:tree, %{value: 1, children: [%{value: 2, children: []}]})
      refute check(:tree, %{value: 1, children: [%{value: :two, children: []}]})
    end

    test "a private type is expanded inline" do
      assert check(:uses_private, :shown)
      refute check(:uses_private, :gone)
    end

    test "built-in types" do
      assert check(:timeout_, :infinity)
      assert check(:timeout_, 0)
      refute check(:timeout_, -1)
      assert check(:mfa_, {Kernel, :+, 2})
      refute check(:mfa_, {Kernel, :+})
      assert check(:keyword_, a: 1)
      refute check(:keyword_, a: :one)
      assert check(:list_, [:a])
      refute check(:list_, ["a"])
      assert check(:flag, true)
      refute check(:flag, 1)
      assert check(:char_, ?a)
      refute check(:char_, -1)
      assert check(:name, "x")
      refute check(:name, "")
      assert check(:handle, self())
      refute check(:handle, :me)
      assert check(:data, ["a", ?b])
      refute check(:data, :a)
      refute check(:nothing, nil)
    end

    test "unions with literals that a broader member covers" do
      assert check(:maybe_atom, nil)
      assert check(:maybe_atom, :a)
      refute check(:maybe_atom, "a")
      assert check(:flag_or_atom, true)
      assert check(:flag_or_atom, :other)
      refute check(:flag_or_atom, 1)
      assert check(:maybe_count, nil)
      assert check(:maybe_count, -3)
      refute check(:maybe_count, :zero)
      assert check(:twice_nil, nil)
      assert check(:twice_nil, 1)
      refute check(:twice_nil, -1)
      assert check(:maybe_unit, nil)
      assert check(:maybe_unit, :second)
      refute check(:maybe_unit, :fortnight)
    end

    test "a type with parameters is not checked" do
      assert check(:parameterized, :anything)
      refute :parameterized in TypeGuard.checked_types(Shapes)
    end
  end

  describe "check/3 with remote types" do
    test "a type of a module that uses TypeGuard" do
      assert check(:id_list, ["a"])
      refute check(:id_list, [1])
    end

    test "types of dependencies and of Elixir" do
      assert check(:price, Decimal.new("1.5"))
      refute check(:price, 1.5)
      assert check(:uuid, UUIDv7.generate())
      refute check(:uuid, "short")
      assert check(:when_, DateTime.utc_now())
      refute check(:when_, ~N[2026-01-01 00:00:00])
      assert check(:calendar_unit, :millisecond)
      assert check(:calendar_unit, 1000)
      refute check(:calendar_unit, :fortnight)
    end

    test "a compiled map type requires its required entries" do
      assert check(:changeset_types, %{name: :string})
      refute check(:changeset_types, %{})
      refute check(:changeset_types, %{"name" => :string})
    end

    test "a type of a module that does not use TypeGuard is trusted" do
      assert TypeGuard.check(UsesPlain, :t, :not_an_integer)
      assert TypeGuard.check(Plain, :t, :not_an_integer)
      refute TypeGuard.adopted?(Plain)
    end
  end

  describe "structs" do
    test "valid?/1 and invalid_fields/1" do
      line = %Line{sku: "s-1", quantity: 2}
      assert TypeGuard.valid?(line)
      assert TypeGuard.valid?(%Order{id: "o-1", status: :open, lines: [line]})

      order = %Order{id: "o-1", status: :lost, lines: [%Line{sku: "s-1", quantity: 0}]}
      refute TypeGuard.valid?(order)
      assert [:status, :lines] == TypeGuard.invalid_fields(order)
    end

    test "required_fields/1 and nil_fields/1" do
      assert [:sku, :quantity] == TypeGuard.required_fields(Line)
      assert [:quantity] == TypeGuard.nil_fields(%Line{sku: "s-1"})
      assert [] == TypeGuard.nil_fields(%Line{sku: "s-1", quantity: 1})
    end

    test "fields/1 and check_field/3" do
      assert [:sku, :quantity, :note] == TypeGuard.fields(Line)
      assert TypeGuard.check_field(Line, :note, nil)
      refute TypeGuard.check_field(Line, :quantity, nil)
      assert TypeGuard.check_field(Line, :not_a_field, :anything)
    end

    test "the blank option defines blank()" do
      {:ok, types} = Code.Typespec.fetch_types(Line)
      assert Enum.any?(types, &match?({:type, {:blank, _, []}}, &1))
      {:ok, types} = Code.Typespec.fetch_types(Order)
      refute Enum.any?(types, &match?({:type, {:blank, _, []}}, &1))
    end
  end

  describe "the :only and :except options" do
    alias TypeGuard.Fixtures.{ExceptT, OnlyId, UsesOnlyId}

    test ":only checks the named types and trusts the rest" do
      assert [:id] == TypeGuard.checked_types(OnlyId)
      assert TypeGuard.check(OnlyId, :id, "8 bytes!")
      refute TypeGuard.check(OnlyId, :id, "short")
      assert TypeGuard.check(OnlyId, :name, :not_a_string)
      assert TypeGuard.check(OnlyId, :t, :not_a_struct)
    end

    test "a module whose t() is left out generates no field checks" do
      assert [] == TypeGuard.fields(OnlyId)
      assert [] == TypeGuard.invalid_fields(%OnlyId{id: 1})
      assert [] == TypeGuard.required_fields(ExceptT)
      assert [:id] == TypeGuard.checked_types(ExceptT)
    end

    test "the :blank option does not need t() to be checked" do
      {:ok, types} = Code.Typespec.fetch_types(ExceptT)
      assert Enum.any?(types, &match?({:type, {:blank, _, []}}, &1))
    end

    test "uses of a type that is left out count as trusted" do
      checks = Map.new(TypeGuard.Coverage.references(UsesOnlyId), &{&1.type, &1.check})
      assert %{id: :checked, name: :trusted} == checks
      refute TypeGuard.check(UsesOnlyId, :ids, ["short"])
      assert TypeGuard.check(UsesOnlyId, :names, [1])
    end

    test "repeated uses check each type that any of them selects" do
      alias TypeGuard.Fixtures.{MergedUses, MergedWithAll}

      assert [:id, :status] == TypeGuard.checked_types(MergedUses)
      refute TypeGuard.check(MergedUses, :status, :maybe)
      assert TypeGuard.check(MergedUses, :note, 1)
      assert [:id, :note] == TypeGuard.checked_types(MergedWithAll)
    end

    test "a module that selects no type generates no checks" do
      alias TypeGuard.Fixtures.SelectsNothing

      refute TypeGuard.adopted?(SelectsNothing)
      refute function_exported?(SelectsNothing, :__type_guard_field__, 2)
      assert TypeGuard.check(SelectsNothing, :name, 1)
    end

    test "an unknown option raises" do
      assert_raise ArgumentError, ~r/the options are/, fn ->
        Code.compile_string(
          "defmodule TypeGuard.Fixtures.BadOption do use TypeGuard, onyl: [:t] end"
        )
      end
    end

    test "a name that is not a public type without parameters raises" do
      for {opts, message} <- [
            {"only: [:idd]", "no public type without parameters named idd/0"},
            {"except: [:secret]", "no public type without parameters named secret/0"},
            {"only: [:id], except: [:t]", "give :only or :except, not both"}
          ] do
        assert_raise ArgumentError, ~r/#{message}/, fn ->
          Code.compile_string("""
          defmodule TypeGuard.Fixtures.BadOptions do
            use TypeGuard, #{opts}
            defstruct [:id]
            @type id() :: String.t()
            @type t() :: %__MODULE__{id: id()}
            @typep secret() :: atom()
          end
          """)
        end
      end
    end
  end

  test "types that a macro defines without parentheses" do
    alias TypeGuard.Fixtures.MacroTypes

    assert [:kind, :t] == TypeGuard.checked_types(MacroTypes)
    assert TypeGuard.check(MacroTypes, :t, %{kind: :one})
    refute TypeGuard.check(MacroTypes, :t, %{kind: :three})
  end

  test "checked_types/1 lists the types without parameters" do
    assert :maybe_id in TypeGuard.checked_types(Ids)
    assert [] == TypeGuard.checked_types(Plain)
  end

  test "a type that the module does not define is not checked" do
    assert TypeGuard.check(Ids, :no_such_type, :anything)
  end
end
