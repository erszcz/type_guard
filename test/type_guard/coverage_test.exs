defmodule TypeGuard.CoverageTest do
  use ExUnit.Case, async: true

  alias TypeGuard.Coverage
  alias TypeGuard.Fixtures.{Ids, Plain, Shapes, UsesPlain}

  test "references/1 says how each remote type is checked" do
    checks = Map.new(Coverage.references(Shapes), &{{&1.module, &1.type}, &1.check})

    assert %{
             {Ids, :id} => :checked,
             {String, :t} => :override,
             {Decimal, :t} => :override,
             {Ecto.Changeset, :types} => :spec,
             {DateTime, :t} => :override,
             {UUIDv7, :t} => :spec,
             {System, :time_unit} => :spec
           } == checks
  end

  test "trusted/1 counts the references that are not checked" do
    assert %{{Plain, :t, 0} => 1} == Coverage.trusted([UsesPlain, Shapes])
  end
end
