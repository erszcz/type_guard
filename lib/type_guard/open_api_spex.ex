if Code.ensure_loaded?(OpenApiSpex.Schema) do
  defmodule TypeGuard.OpenApiSpex do
    @moduledoc """
    Typespecs of the values that `OpenApiSpex.Plug.CastAndValidate` makes.

    A schema describes the JSON of a request. The cast turns that JSON into
    other Elixir values, so the type of the cast value differs from the type
    of the JSON. This module builds the typespec of the cast value from the
    schema:

        defmodule Shop.CreateOrder do
          use TypeGuard

          @schema %OpenApiSpex.Schema{
            type: :object,
            properties: %{
              note: %OpenApiSpex.Schema{type: :string},
              placed_at: %OpenApiSpex.Schema{type: :string, format: :"date-time"}
            },
            required: [:placed_at],
            "x-struct": __MODULE__
          }

          defstruct [:note, :placed_at]

          def schema, do: @schema

          @type t() :: unquote(TypeGuard.OpenApiSpex.type(@schema, __MODULE__))
          @type relaxed() :: unquote(TypeGuard.OpenApiSpex.relaxed_type(@schema))
        end

    The cast gives these values:

      * An object with an `x-struct` becomes that struct. An absent property
        without a `default` is `nil`.
      * An object without an `x-struct` becomes a map with atom keys. An absent
        property stays absent. A property with a `default` is always present.
      * An enum value is the member of the enum, for example an atom.
      * A `date-time` string becomes a `DateTime`, and a `date` string becomes a
        `Date`.
      * `oneOf` and `anyOf` give the value of a matching branch.
      * `allOf` gives the value of its scalar part, or the merged maps of its
        object parts.
      * A `nullable` schema also admits `nil`.

    The cast also checks constraints that a typespec cannot state, such as
    `pattern` or `maxItems`, so the type leaves them out. A positive `minItems`
    is the exception: it makes the type a nonempty list, `[t, ...]`. That is
    weaker than `minItems: 3`, but it holds for every value of the schema.

    A schema that this module cannot describe has the type `term()`.

    ## References to other schema modules

    A property or a branch can name another schema module. Its type is then
    `Module.t()`, or `Module.relaxed()` in an `anyOf`, because the cast ignores
    the `x-struct` of each branch of `anyOf`. Each schema module must define
    both types. The reference stays a remote type, so a schema does not depend
    on another schema at compile time.

    A `%OpenApiSpex.Reference{}` has the type `term()`, because its target is
    known only at run time.

    ## Custom validators

    An `x-validate` module replaces the cast of its schema, so this module
    cannot read the value that the validator returns. A schema of type `:string`
    with a validator has the type `String.t()`, also with a `format`. The other
    types stay as they are. A validator that returns a value of another type
    needs a schema with a different type, for example an `enum` of atoms.

    See the [OpenApiSpex guide](open_api_spex.md).
    """

    alias OpenApiSpex.Reference
    alias OpenApiSpex.Schema

    @doc """
    Whether the cast makes the struct of `module` from `schema`.
    """
    @spec struct?(Schema.t(), module()) :: boolean()
    def struct?(%Schema{} = schema, module), do: struct_module(schema) == module

    @doc """
    Whether `schema` can be a request body: an object, or a union whose inline branches are
    objects. A branch that is another schema module counts as an object.
    """
    @spec body?(Schema.t()) :: boolean()
    def body?(%Schema{oneOf: one_of, anyOf: any_of, allOf: all_of} = schema) do
      case one_of || any_of || all_of do
        nil -> object?(schema)
        branches -> Enum.all?(branches, &(is_atom(&1) or (is_struct(&1, Schema) and object?(&1))))
      end
    end

    @doc """
    Returns the quoted type of the value that the cast gives for `schema` without its `x-struct`.
    The cast ignores the `x-struct` of each branch of `anyOf`.
    """
    @spec relaxed_type(Schema.t()) :: Macro.t()
    def relaxed_type(%Schema{} = schema), do: relaxed_value(schema)

    @doc """
    Returns the quoted type of the value that the cast gives for `schema`, the schema of `module`.
    """
    @spec type(Schema.t(), module()) :: Macro.t()
    def type(%Schema{} = schema, module) do
      cond do
        # The cast gives the value of a branch, not the struct of this schema.
        composite?(schema) and struct_module(schema) == module ->
          value(%{schema | "x-struct": nil})

        struct_module(schema) == module ->
          nullable(struct_type(schema, module), schema)

        true ->
          value(schema)
      end
    end

    # The type of a value of `schema`.
    defp value(module) when is_atom(module) and not is_nil(module), do: remote(module, :t)
    defp value(%Reference{}), do: term()

    defp value(%Schema{nullable: true} = schema),
      do: union([value(%{schema | nullable: false}), nil])

    defp value(%Schema{enum: enum}) when is_list(enum), do: union(Enum.map(enum, &literal/1))

    defp value(%Schema{oneOf: branches}) when is_list(branches),
      do: union(Enum.map(branches, &value/1))

    # The cast removes the `x-struct` of each branch. Then it merges the maps of the matching
    # branches.
    defp value(%Schema{anyOf: branches}) when is_list(branches),
      do: union(Enum.map(branches, &relaxed_value/1))

    defp value(%Schema{allOf: parts}) when is_list(parts), do: all_of(parts)

    defp value(%Schema{} = schema) do
      case struct_module(schema) do
        nil -> by_type(schema)
        module -> remote(module, :t)
      end
    end

    defp value(_other), do: term()

    # The cast of `allOf` casts the value with each part. Scalars stay as they are, and the maps of
    # object parts merge. One part gives the value of that part. An inline scalar part gives the
    # type of the value of several parts.
    defp all_of([part]), do: relaxed_value(part)

    defp all_of(parts) do
      case Enum.find(parts, &scalar?/1) do
        nil -> term()
        part -> value(part)
      end
    end

    defp scalar?(%Schema{type: type}), do: type in [:string, :integer, :number, :boolean]
    defp scalar?(_part), do: false

    defp relaxed_value(module) when is_atom(module) and not is_nil(module),
      do: remote(module, :relaxed)

    defp relaxed_value(%Schema{} = schema), do: value(%{schema | "x-struct": nil})
    defp relaxed_value(other), do: value(other)

    # A validator replaces the cast of the format. See "Custom validators" in the moduledoc.
    defp by_type(%Schema{:type => :string, :"x-validate" => validator})
         when not is_nil(validator),
         do: remote(String, :t)

    defp by_type(%Schema{type: :string, format: :"date-time"}), do: remote(DateTime, :t)
    defp by_type(%Schema{type: :string, format: :date}), do: remote(Date, :t)
    # A multipart file part casts into a `Plug.Upload`.
    defp by_type(%Schema{type: :string, format: :binary}), do: term()
    defp by_type(%Schema{type: :string}), do: remote(String, :t)
    defp by_type(%Schema{type: :integer}), do: {:integer, [], []}
    defp by_type(%Schema{type: :number}), do: {:number, [], []}
    defp by_type(%Schema{type: :boolean}), do: {:boolean, [], []}

    defp by_type(%Schema{type: :array, items: nil, minItems: minimum})
         when is_integer(minimum) and minimum > 0,
         do: {:nonempty_list, [], []}

    defp by_type(%Schema{type: :array, items: nil}), do: {:list, [], []}

    defp by_type(%Schema{type: :array, items: items, minItems: minimum})
         when is_integer(minimum) and minimum > 0,
         do: [value(items), {:..., [], []}]

    defp by_type(%Schema{items: items, type: :array}), do: [value(items)]
    defp by_type(%Schema{type: :object} = schema), do: map_type(schema)

    defp by_type(%Schema{properties: properties} = schema) when is_map(properties),
      do: map_type(schema)

    defp by_type(_schema), do: term()

    # A struct: every property is a field. An absent property without a default is nil.
    defp struct_type(%Schema{properties: properties} = schema, module) do
      fields =
        for {name, property} <- Enum.sort(properties || %{}) do
          type = value(property)
          if present?(schema, name, property), do: {name, type}, else: {name, union([type, nil])}
        end

      {:%, [], [module, {:%{}, [], fields}]}
    end

    # A map: a property is a required key when the cast always puts it there. A typespec cannot
    # name a string key, so the properties with string names and the additional properties
    # share one optional key of type `String.t()`.
    defp map_type(%Schema{properties: properties, additionalProperties: additional} = schema) do
      {atom_named, string_named} =
        properties
        |> Kernel.||(%{})
        |> Enum.sort()
        |> Enum.split_with(fn {name, _} -> is_atom(name) end)

      keys =
        for {name, property} <- atom_named do
          kind = if present?(schema, name, property), do: :required, else: :optional
          {{kind, [], [name]}, value(property)}
        end

      string_types = Enum.map(string_named, fn {_name, property} -> value(property) end)

      case {keys, string_keys(string_types, additional)} do
        {[], nil} when properties == nil -> {:map, [], []}
        {keys, nil} -> {:%{}, [], keys}
        {keys, extra} -> {:%{}, [], keys ++ [extra]}
      end
    end

    # An additional property keeps its string key.
    defp string_keys([], false), do: nil
    defp string_keys(types, false), do: {optional(string()), union(types)}

    defp string_keys(_types, additional) when additional in [nil, true],
      do: {optional(string()), term()}

    defp string_keys(types, additional),
      do: {optional(string()), union([value(additional) | types])}

    defp present?(%Schema{required: required}, name, property),
      do: name in (required || []) or default?(property)

    defp default?(%Schema{default: default}), do: not is_nil(default)
    defp default?(_property), do: false

    defp object?(%Schema{type: :object}), do: true
    defp object?(%Schema{properties: properties}), do: is_map(properties)

    # A macro can set `x-struct` on any schema, but the cast uses it only for an object that is
    # not a union.
    defp struct_module(%Schema{} = schema) do
      if object?(schema) and not composite?(schema), do: Map.get(schema, :"x-struct")
    end

    defp composite?(%Schema{oneOf: one_of, anyOf: any_of}), do: is_list(one_of) or is_list(any_of)

    defp nullable(type, %Schema{nullable: true}), do: union([type, nil])
    defp nullable(type, _schema), do: type

    defp literal(value) when is_atom(value) or is_integer(value), do: value
    defp literal(value) when is_binary(value), do: string()
    defp literal(value) when is_float(value), do: {:float, [], []}
    defp literal(_value), do: term()

    # A union without repeated members. Elixir writes a union as nested `|` operators.
    defp union([]), do: term()

    defp union(types) do
      types
      |> Enum.flat_map(&members/1)
      |> Enum.uniq()
      |> Enum.reverse()
      |> Enum.reduce(fn type, acc -> {:|, [], [type, acc]} end)
    end

    defp members({:|, _, [left, right]}), do: members(left) ++ members(right)
    defp members(type), do: [type]

    defp remote(module, name), do: {{:., [], [module, name]}, [], []}
    defp string, do: remote(String, :t)
    defp term, do: {:term, [], []}
    defp optional(type), do: {:optional, [], [type]}
  end
end
