# OpenApiSpex

The integration is active when OpenApiSpex is a dependency of the project.

## Why type the cast

`OpenApiSpex.Plug.CastAndValidate` validates a request against a schema and
casts it. The controller action then reads the cast value from
`conn.body_params`, which has no useful type. The schema already knows the
shape of that value, so a typespec can come from the schema:

```elixir
defmodule Shop.CreateOrder do
  use TypeGuard

  alias OpenApiSpex.Schema

  @schema %Schema{
    type: :object,
    properties: %{
      note: %Schema{type: :string},
      placed_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:placed_at],
    "x-struct": __MODULE__
  }

  defstruct [:note, :placed_at]

  def schema, do: @schema

  @type t() :: unquote(TypeGuard.OpenApiSpex.type(@schema, __MODULE__))
  @type relaxed() :: unquote(TypeGuard.OpenApiSpex.relaxed_type(@schema))
end
```

The result is an ordinary `@type`, equal to:

```elixir
@type t() :: %Shop.CreateOrder{note: String.t() | nil, placed_at: DateTime.t()}
```

Dialyzer and other static tools read it, and `use TypeGuard` makes it checkable
at run time.

A project with its own schema macro can generate both types in a
`@before_compile` callback, so that each schema module defines them.

## `t()` and `relaxed()`

`t()` is the value that the cast makes from the schema of the module.

`relaxed()` is the same value without the `x-struct` of the module. The cast of
`anyOf` removes the `x-struct` of each branch and merges the maps of the branches
that match. A module that a schema names in an `anyOf` needs `relaxed()`.

## Helpers for an accessor

`struct?/2` tells if the cast makes the struct of a module from a schema.
`body?/1` tells if a schema can be a request body. A macro can use them to
generate a function that reads the cast body of a conn as `t()`.

## Limits

- A typespec cannot state most constraints of a schema, such as `pattern` or
  `maxItems`. The cast still checks them. A positive `minItems` gives a nonempty
  list, `[t, ...]`, whatever the number is.
- `%OpenApiSpex.Reference{}` has the type `term()`, because its target is known
  only at run time. Name the schema module instead.
- A typespec cannot name a string key of a map, so properties with string names
  and additional properties share one optional `String.t()` key.
- `format: :binary` has the type `term()`, because a multipart file part casts
  into a `Plug.Upload`.
- An `x-validate` module replaces the cast, so this integration cannot read the
  value that it returns. A string schema with a validator has the type
  `String.t()`. A validator that returns another type needs a schema with that
  type, for example an `enum` of atoms.
