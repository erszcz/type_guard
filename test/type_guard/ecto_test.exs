defmodule TypeGuard.EctoTest do
  use ExUnit.Case, async: true

  alias TypeGuard.Fixtures.{Customer, Settings}

  @valid %{"name" => "Ada", "address" => %{"street" => "Main St"}}

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      {message, opts[:validation]}
    end)
  end

  describe "validate_non_nil/1" do
    test "adds can't be blank to a nil required field, also in nested changesets" do
      changeset =
        %{"address" => %{}, "previous_addresses" => [%{"street" => "Old St"}, %{}]}
        |> Customer.changeset()
        |> TypeGuard.Ecto.validate_non_nil()

      refute changeset.valid?

      assert %{
               name: [{"can't be blank", :required}],
               address: %{street: [{"can't be blank", :required}]},
               previous_addresses: [%{}, %{street: [{"can't be blank", :required}]}]
             } == errors(changeset)
    end

    test "accepts nil in a field whose type admits it, and an empty string" do
      # Ecto casts "" to nil by default, so the empty string is set directly.
      changeset =
        %{"email" => nil, "address" => %{"street" => "Main St"}}
        |> Customer.changeset()
        |> Ecto.Changeset.put_change(:name, "")
        |> TypeGuard.Ecto.validate_non_nil()

      assert changeset.valid?
    end

    test "keeps an error that the field already has" do
      changeset =
        Customer.changeset(%{"name" => 1, "address" => %{"street" => "Main St"}})
        |> TypeGuard.Ecto.validate_non_nil()

      assert %{name: [{"is invalid", :cast}]} == errors(changeset)
    end
  end

  describe "validate_type/1" do
    test "rejects a value that Ecto casts but t() does not admit" do
      changeset =
        @valid
        |> Map.merge(%{"settings" => %{"theme" => "dark"}, "labels" => %{"vip" => -1}})
        |> Customer.changeset()
        |> TypeGuard.Ecto.validate_type()

      assert %{settings: [{"is invalid", :type}], labels: [{"is invalid", :type}]} ==
               errors(changeset)
    end

    test "accepts a value that t() admits" do
      changeset =
        @valid
        |> Map.put("settings", %Settings{theme: :dark})
        |> Customer.changeset()
        |> TypeGuard.Ecto.validate()

      assert changeset.valid?
    end
  end

  test "validate/1 reports nil as blank, not as invalid" do
    changeset =
      %{"address" => %{"street" => "Main St"}}
      |> Customer.changeset()
      |> TypeGuard.Ecto.validate()

    assert %{name: [{"can't be blank", :required}]} == errors(changeset)
  end

  test "a changeset of a schema that does not use TypeGuard is returned unchanged" do
    changeset = Ecto.Changeset.change({%{}, %{a: :integer}}, %{a: nil})
    assert changeset == TypeGuard.Ecto.validate(changeset)
  end
end
