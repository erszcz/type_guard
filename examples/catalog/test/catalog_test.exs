defmodule CatalogTest do
  use ExUnit.Case, async: true

  alias Catalog.{Image, Product, Sku, Video}

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => UUIDv7.generate(),
        "sku" => "KB-1042",
        "name" => "Keyboard",
        "price" => "49.90",
        "tags" => ["input"],
        "attributes" => %{"layout" => "ISO"},
        "dimensions" => %{"width" => 440, "height" => 30},
        "media" => [%{"kind" => "image", "url" => "/kb.png"}]
      },
      overrides
    )
  end

  defp errors(attrs) do
    {:error, changeset} = Catalog.new_product(attrs)
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  test "a product built from valid attributes conforms to t()" do
    assert {:ok, %Product{} = product} = Catalog.new_product(attrs())
    assert TypeGuard.valid?(product)
  end

  test "a required field reports can't be blank, also in a nested embed" do
    assert %{name: ["can't be blank"], dimensions: %{height: ["can't be blank"]}} ==
             errors(attrs(%{"name" => nil, "dimensions" => %{"width" => 440}}))
  end

  test "a value that Ecto casts but t() does not admit is invalid" do
    assert %{attributes: ["is invalid"]} == errors(attrs(%{"attributes" => %{"weight" => 1.2}}))
    assert %{id: ["is invalid"]} == errors(attrs(%{"id" => "not-a-uuid"}))
  end

  test "an embed is validated in its own changeset" do
    assert %{dimensions: %{width: ["can't be blank"]}} ==
             errors(attrs(%{"dimensions" => %{"height" => 30}}))
  end

  test "a polymorphic embed is validated on its field" do
    # PolymorphicEmbed puts the cast structs, not changesets, into the changes.
    assert %{media: ["is invalid"]} ==
             errors(attrs(%{"media" => [%{"kind" => "video", "url" => "/kb.mp4"}]}))
  end

  test "a polymorphic field admits only its declared embed modules" do
    {:ok, product} = Catalog.new_product(attrs())

    assert [] ==
             TypeGuard.invalid_fields(%{product | media: [%Video{url: "/kb.mp4", seconds: 9}]})

    assert [:media] == TypeGuard.invalid_fields(%{product | media: [%{url: "/kb.png"}]})
    assert [:media] == TypeGuard.invalid_fields(%{product | media: [%Image{url: nil}]})
  end

  test "required fields follow from t()" do
    assert [:id, :sku, :name, :price, :status, :tags, :attributes, :dimensions, :media] ==
             TypeGuard.required_fields(Product)
  end

  test "the coverage report says how each remote type is checked" do
    checks = Map.new(TypeGuard.Coverage.references(Product), &{{&1.module, &1.type}, &1.check})

    assert %{
             {UUIDv7, :t} => :spec,
             {Sku, :t} => :checked,
             {Decimal, :t} => :override,
             {String, :t} => :override,
             {Date, :t} => :override,
             {Catalog.Dimensions, :t} => :checked,
             {Image, :t} => :checked,
             {Video, :t} => :checked
           } == checks

    assert %{} == TypeGuard.Coverage.trusted([Product])
  end
end
