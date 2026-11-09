defmodule TypeGuard.OpenApiSpexTest do
  use ExUnit.Case, async: true

  alias OpenApiSpex.Reference
  alias OpenApiSpex.Schema

  defp type(schema, module \\ Owner),
    do: schema |> TypeGuard.OpenApiSpex.type(module) |> Macro.to_string()

  defp relaxed(schema), do: schema |> TypeGuard.OpenApiSpex.relaxed_type() |> Macro.to_string()

  # The type of a value of `schema`, read from a map with one required key.
  defp value(schema) do
    "%{required(:v) => " <> rest =
      type(%Schema{
        type: :object,
        properties: %{v: schema},
        required: [:v],
        additionalProperties: false
      })

    String.trim_trailing(rest, "}")
  end

  defp object(properties, attrs),
    do: struct(Schema, Map.merge(%{properties: properties, type: :object}, attrs))

  describe "type/2 of an object" do
    test "an object with the x-struct of the module is its struct; an optional field can be nil" do
      schema =
        object(
          %{
            name: %Schema{type: :string},
            note: %Schema{type: :string},
            mode: %Schema{type: :string, default: "draft"}
          },
          %{required: [:name], "x-struct": Owner}
        )

      assert "%Owner{mode: String.t(), name: String.t(), note: String.t() | nil}" == type(schema)
    end

    test "an object without an x-struct is a map; an optional key without a default is optional" do
      schema =
        object(
          %{
            name: %Schema{type: :string},
            note: %Schema{type: :string},
            mode: %Schema{type: :string, default: "draft"}
          },
          %{required: [:name], additionalProperties: false}
        )

      assert "%{required(:mode) => String.t(), required(:name) => String.t(), optional(:note) => String.t()}" ==
               type(schema)
    end

    test "string property names and additional properties share an optional String.t() key" do
      schema =
        object(%{"a.b" => %Schema{type: :integer}, id: %Schema{type: :string}}, %{
          required: [:id],
          additionalProperties: %Schema{type: :boolean}
        })

      assert "%{required(:id) => String.t(), optional(String.t()) => boolean() | integer()}" ==
               type(schema)
    end

    test "open additional properties are optional String.t() keys of any value" do
      schema =
        object(%{id: %Schema{type: :string}}, %{required: [:id], additionalProperties: true})

      assert "%{required(:id) => String.t(), optional(String.t()) => term()}" == type(schema)
    end

    test "a closed object without properties is a map" do
      assert "map()" == type(%Schema{type: :object, additionalProperties: false})
    end

    test "an object without properties is a map with string keys" do
      assert "%{optional(String.t()) => term()}" == type(%Schema{type: :object})
    end

    test "a nullable struct admits nil" do
      schema =
        object(%{id: %Schema{type: :string}}, %{
          required: [:id],
          nullable: true,
          "x-struct": Owner
        })

      assert "%Owner{id: String.t()} | nil" == type(schema)
    end
  end

  describe "type/2 of a value" do
    test "maps formats, enums, nullable values, lists and references" do
      expected = [
        {"DateTime.t()", %Schema{type: :string, format: :"date-time"}},
        {"Date.t()", %Schema{type: :string, format: :date}},
        {"Plug.Upload.t() | String.t()", %Schema{type: :string, format: :binary}},
        {"String.t() | nil", %Schema{type: :string, nullable: true}},
        {"integer()", %Schema{type: :integer}},
        {"number()", %Schema{type: :number}},
        {"boolean()", %Schema{type: :boolean}},
        {":a | :b", %Schema{type: :string, enum: [:a, :b]}},
        {"1 | 2", %Schema{type: :integer, enum: [1, 2]}},
        {"[integer()]", %Schema{type: :array, items: %Schema{type: :integer}}},
        {"list()", %Schema{type: :array}},
        {"Other.t()", Other},
        {"TypeGuard.unchecked()", %Reference{"$ref": "#/components/schemas/Other"}}
      ]

      for {type, schema} <- expected do
        assert {^type, ^schema} = {value(schema), schema}
      end
    end

    test "a validator replaces the cast of the format, so the value stays a string" do
      assert "String.t()" ==
               value(%Schema{type: :string, format: :"date-time", "x-validate": Validator})
    end

    test "a positive minItems is a nonempty list" do
      items = %Schema{type: :integer}

      assert "[integer(), ...]" == value(%Schema{type: :array, items: items, minItems: 1})
      assert "[integer(), ...]" == value(%Schema{type: :array, items: items, minItems: 3})
      assert "nonempty_list()" == value(%Schema{type: :array, minItems: 1})
    end

    test "a minItems of zero is a list" do
      items = %Schema{type: :integer}

      assert "[integer()]" == value(%Schema{type: :array, items: items, minItems: 0})
      assert "list()" == value(%Schema{type: :array, minItems: 0})
    end

    test "a string enum is String.t()" do
      assert "String.t()" == value(%Schema{type: :string, enum: ["a", "b"]})
    end

    test "the x-struct of a schema that is not an object does not apply" do
      assert "String.t() | nil" == type(%Schema{type: :string, nullable: true, "x-struct": Owner})
    end

    test "allOf of one part is the type of the part" do
      assert "First.relaxed()" == value(%Schema{allOf: [First]})
    end

    test "allOf of scalars and constraints is the scalar" do
      parts = [%Schema{minLength: 1}, %Schema{type: :string}]

      assert "String.t()" == value(%Schema{allOf: parts})
    end

    test "allOf of objects is not checked, because the cast merges the parts" do
      assert "TypeGuard.unchecked()" == value(%Schema{allOf: [First, Second]})
    end

    test "a schema that it cannot describe is not checked" do
      for schema <- [
            %Schema{type: :string, enum: [%{a: 1}]},
            %Schema{type: :string, enum: []},
            %Schema{oneOf: []},
            %{type: :string}
          ] do
        assert {"TypeGuard.unchecked()", ^schema} = {value(schema), schema}
      end
    end

    test "a schema that admits any value is term()" do
      assert "term()" == value(%Schema{})
    end

    test "oneOf is the union of the branch types, also when the schema has the x-struct" do
      schema = %Schema{type: :object, oneOf: [First, Second], "x-struct": Owner}

      assert "First.t() | Second.t()" == type(schema)
    end

    test "anyOf is the union of the branch types without their structs" do
      assert "First.relaxed() | String.t()" ==
               type(%Schema{anyOf: [First, %Schema{type: :string}]})
    end
  end

  describe "relaxed_type/1" do
    test "is a map for an object with an x-struct" do
      schema =
        object(%{id: %Schema{type: :string}}, %{
          required: [:id],
          additionalProperties: false,
          "x-struct": Owner
        })

      assert "%{required(:id) => String.t()}" == relaxed(schema)
    end
  end

  describe "struct?/2" do
    test "is true for an object whose x-struct is the module" do
      assert TypeGuard.OpenApiSpex.struct?(object(%{}, %{"x-struct": Owner}), Owner)
      refute TypeGuard.OpenApiSpex.struct?(object(%{}, %{"x-struct": Other}), Owner)
    end

    test "is false for a schema that is not an object, and for a union" do
      refute TypeGuard.OpenApiSpex.struct?(%Schema{type: :string, "x-struct": Owner}, Owner)
      refute TypeGuard.OpenApiSpex.struct?(%Schema{oneOf: [First], "x-struct": Owner}, Owner)
    end
  end

  describe "body?/1" do
    test "is true for an object, a union of schema modules and a union of inline objects" do
      assert TypeGuard.OpenApiSpex.body?(object(%{}, %{}))
      assert TypeGuard.OpenApiSpex.body?(%Schema{oneOf: [First, Second]})
      assert TypeGuard.OpenApiSpex.body?(%Schema{anyOf: [First, object(%{}, %{})]})
    end

    test "is false for a scalar and for a union with an inline scalar" do
      refute TypeGuard.OpenApiSpex.body?(%Schema{type: :string})
      refute TypeGuard.OpenApiSpex.body?(%Schema{oneOf: [First, %Schema{type: :string}]})
    end
  end

  describe "a module that defines t() with type/2" do
    alias TypeGuard.Fixtures.OpenApiSpex.{Order, Search}

    defp cast(body, module), do: OpenApiSpex.Cast.cast(module.schema(), body, %{})

    test "the cast of a struct schema conforms, with an absent property as nil" do
      body = %{"id" => "o-1", "placed_at" => "2026-01-01T00:00:00Z"}

      assert {:ok, %Order{id: "o-1", note: nil, status: :open, placed_at: placed_at} = order} =
               cast(body, Order)

      assert %DateTime{} = placed_at
      assert TypeGuard.valid?(order)
    end

    test "a struct that the cast cannot make does not conform" do
      refute TypeGuard.valid?(%Order{id: nil, status: :open, placed_at: nil})
    end

    test "the cast of a map schema conforms, with an absent property absent" do
      assert {:ok, %{term: "a", limit: 10} = search} = cast(%{"term" => "a"}, Search)

      refute is_map_key(search, :tag)
      assert TypeGuard.check(Search, :t, search)
    end

    test "a map without a required key does not conform" do
      refute TypeGuard.check(Search, :t, %{limit: 10})
    end

    test "an empty list does not conform to an array with a positive minItems" do
      assert {:ok, %{term: "a", tags: ["b"]} = search} =
               cast(%{"term" => "a", "tags" => ["b"]}, Search)

      assert TypeGuard.check(Search, :t, search)
      refute TypeGuard.check(Search, :t, %{search | tags: []})
    end

    test "a map with a value of the wrong type or an unknown key does not conform" do
      refute TypeGuard.check(Search, :t, %{term: 1, limit: 10})
      refute TypeGuard.check(Search, :t, %{term: "a", limit: 10, other: 1})
    end
  end

  describe "a module with unchecked: :raise" do
    defp compile_schema(name, schema) do
      module = Module.concat(TypeGuard.Fixtures.OpenApiSpex, name)

      Code.compile_string("""
      defmodule #{inspect(module)} do
        use TypeGuard, unchecked: :raise

        @schema #{schema}
        def schema, do: @schema

        @type t() :: unquote(TypeGuard.OpenApiSpex.type(@schema, __MODULE__))
      end
      """)

      module
    end

    test "does not compile with a schema that is not checked" do
      assert_raise TypeGuard.UncheckedError, ~r/cannot check TypeGuard.unchecked\(\)/, fn ->
        compile_schema(
          "StrictReference",
          ~s(%OpenApiSpex.Schema{type: :object, properties: %{owner: %OpenApiSpex.Reference{"$ref": "#/components/schemas/Owner"}}})
        )
      end
    end

    test "checks an upload as a Plug.Upload or a string" do
      module =
        compile_schema(
          "StrictUpload",
          "%OpenApiSpex.Schema{type: :string, format: :binary}"
        )

      upload = %Plug.Upload{path: "/tmp/a", filename: "a.png", content_type: "image/png"}

      assert {:ok, ^upload} = OpenApiSpex.Cast.cast(module.schema(), upload, %{})
      assert {:ok, "text"} = OpenApiSpex.Cast.cast(module.schema(), "text", %{})
      assert TypeGuard.check(module, :t, upload)
      assert TypeGuard.check(module, :t, "text")
      refute TypeGuard.check(module, :t, 1)
      refute TypeGuard.check(module, :t, %{path: "/tmp/a"})
    end
  end
end
