# TypeGuard

TypeGuard checks values at runtime against the plain typespecs of your
modules. You keep writing ordinary `@type` definitions, and `use TypeGuard`
generates a check for each of them at compile time.

```elixir
defmodule Shop.Line do
  use TypeGuard

  defstruct [:sku, :quantity, :note]

  @type t() :: %__MODULE__{
          sku: String.t(),
          quantity: pos_integer(),
          note: String.t() | nil
        }
end

TypeGuard.valid?(%Shop.Line{sku: "s-1", quantity: 2})
#=> true

TypeGuard.invalid_fields(%Shop.Line{sku: "s-1", quantity: 0})
#=> [:quantity]

TypeGuard.required_fields(Shop.Line)
#=> [:sku, :quantity]
```

## Installation

```elixir
def deps do
  [{:type_guard, "~> 0.1"}]
end
```

## Conventions

- **Opt in per module.** `use TypeGuard` generates a check for each public
  type of the module that has no parameters. The types stay plain `@type`
  definitions, so Dialyzer and other static tools read them as before.
  See [Conventions](guides/conventions.md).
- **Checks are plain code.** Each check is a boolean expression of guards,
  built once at compile time. Nothing is interpreted at runtime.
- **A struct is checked field by field.** When `t()` is a struct type of the
  module, `TypeGuard.invalid_fields/1` names each field whose value does not
  conform to its type.
- **A field is required when its type rejects `nil`.** There is no separate
  list of required fields to keep in step with the type.
- **A type of another module of your project is checked by that module.**
  The check calls it at runtime, so a reload of that module updates every
  check that uses it, and no module depends on another at compile time.
  See [Code reloading](guides/code_reloading.md).
- **A type of another application is read from its compiled typespec.** For
  a dependency, Elixir or Erlang/OTP, the check is built at compile time from
  the typespec. A short table of overrides keeps common struct types, such as
  `DateTime.t()`, to a single `is_struct/2`. See
  [Remote types](guides/remote_types.md).
- **What cannot be checked is trusted, and reported.** Types with
  parameters, types of project modules that do not use TypeGuard and opaque
  types of other applications pass. `TypeGuard.Coverage` lists them.
- **Integrations turn on by themselves.** With Ecto, `TypeGuard.Ecto`
  validates changesets against `t()`. With PolymorphicEmbed, a polymorphic
  field is checked against its declared embed modules. See
  [Ecto](guides/ecto.md).

## Example

The `examples/catalog` directory of the repository holds a small Ecto project that uses
TypeGuard with nested embeds, polymorphic embeds and types from
dependencies.

## Compatibility

Tested with Elixir 1.20 on Erlang/OTP 29.
