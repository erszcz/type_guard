# Conventions

## Opting in

`use TypeGuard` in a module registers a `@before_compile` callback. When the
module body is complete, the callback reads all of its types, including the
ones that other macros define, and generates the checks.

```elixir
defmodule Shop.Order do
  use TypeGuard

  defstruct [:id, :status, lines: []]

  @type status() :: :open | :paid | :shipped
  @type t() :: %__MODULE__{id: String.t(), status: status(), lines: [Shop.Line.t()]}
end
```

`use TypeGuard` takes these options:

- `only: [:id, :status]` checks only the named public types.
- `except: [:t]` checks all public types but the named ones.
- `allow_missing: true` ignores names in `:only` or `:except` that the
  module does not define, instead of raising at compile time.
- `blank: true` defines `blank()`. See [Blank structs](#blank-structs).

A module whose uses select no type, such as one without an `id()` under
`only: [:id], allow_missing: true`, generates no checks at all.

A module can `use TypeGuard` more than once, typically because several
macros add it. It then checks each type that any of the uses selects, so a
plain `use TypeGuard` selects all types. A macro that only provides some
types can add a narrow use, such as `use TypeGuard, only: [:id],
allow_missing: true`, without overriding a wider one.

A type that `:only` or `:except` leaves out is not checked: `TypeGuard.check/3`
returns `true` for it, and `TypeGuard.Coverage` counts its uses in other
modules as trusted. A checked type still expands the local types it uses,
selected or not. When `t()` is left out, the module generates no field
checks, so `TypeGuard.invalid_fields/1` and `TypeGuard.required_fields/1`
return `[]` for its structs. Use `:only` to check the few types of a module
that other modules use, such as an `id()` alias, without generating checks
for the rest.

## What a module generates

| Function | Returns |
| --- | --- |
| `__type_guard__(type, value)` | `true` if `value` conforms to the public type `type/0`. |
| `__type_guard__(:types)` | The public types without parameters that the module checks. |
| `__type_guard__(:fields)` | The fields of `t()`, when `t()` is a struct type of the module. |
| `__type_guard__(:references)` | The remote types in the types of the module, with how they are checked. |
| `__type_guard_field__(field, value)` | `true` if `value` conforms to the type of `field` in `t()`. |

These functions are the protocol between modules and are not meant to be
called directly. Call the functions of `TypeGuard` instead:

| Function | Purpose |
| --- | --- |
| `TypeGuard.check/3` | Checks a value against a type of a module. |
| `TypeGuard.valid?/1` | Checks a struct against the `t()` of its module. |
| `TypeGuard.invalid_fields/1` | Lists the fields of a struct whose values do not conform. |
| `TypeGuard.required_fields/1` | Lists the fields of `t()` whose types reject `nil`. |
| `TypeGuard.nil_fields/1` | Lists the required fields of a struct that hold `nil`. |
| `TypeGuard.checked_types/1` | Lists the types that a module checks. |

## Which types are checked

A check covers public types (`@type` and `@opaque`) without parameters.
A type with parameters, such as `@type page(item) :: [item]`, is not
checked: `TypeGuard.check/3` returns `true` for it, and for a type that the
module does not define. `TypeGuard.checked_types/1` lists the checked types.

Inside a type, these forms are checked:

| Form | Check |
| --- | --- |
| `:a`, `1`, `-1`, `nil`, `true` | Equality with the literal. |
| `a \| b` | Either check. |
| `1..10` | An integer within the range. |
| `[t]`, `list(t)` | A list of elements that conform to `t`. |
| `[t, ...]`, `nonempty_list(t)` | The same, and not empty. |
| `[]` | The empty list. |
| `[key: t]`, `keyword(t)` | A list of `{key, value}` tuples that conform. |
| `{a, b}`, `{a, b, c}` | A tuple of that size whose elements conform. |
| `%{key: t}` | A map with the key, whose value conforms. |
| `%{optional(k) => v}`, `%{k => v}` | Each other entry has a conforming key and value. |
| `%{}` | The empty map. |
| `%Mod{field: t}` | A struct of `Mod` whose listed fields conform. |
| `<<_::size>>`, `<<_::_*unit>>` | A bitstring of that size or unit. |
| Built-in types | The guard of the type, such as `is_binary/1` for `binary()`. |
| A local type | The check of its definition, expanded inline. |
| A remote type | See [Remote types](remote_types.md). |

A map type is closed: an entry that matches neither a listed key nor an
`optional`/`required` pair fails the check. `required(k) => v` is checked
like `optional(k) => v`: the check does not require an entry to exist.

These are not checked and pass: `term()`, `any()`, the arguments and result
of a function type (only `is_function/1` is checked), the element types of a
type with parameters such as `MapSet.t(String.t())`, and a type variable.

A recursive public type calls its own check. A recursive private type is
checked at its first level only.

## Structs and fields

When `t()` is a struct type of the module itself, `%__MODULE__{...}`, the
module also generates a check for each field. `TypeGuard.invalid_fields/1`
returns the fields whose values fail their checks, in the order of `t()`.
The check of `t()` itself is the struct check followed by the field checks.

## Required fields and `nil`

A field is required exactly when the check of its type rejects `nil`.
`TypeGuard.required_fields/1` lists them, and `TypeGuard.nil_fields/1` lists
the required fields of a struct that hold `nil`. A type alias of another
module is resolved, so `email: Shop.Email.t()` is required when
`Shop.Email.t()` is `String.t()` and optional when it is `String.t() | nil`.

A field whose type is not checked is not required, because its check
accepts `nil` too.

## Blank structs

A struct built with `%Shop.Line{}` holds `nil` in each field without a
default, so it does not conform to `t()` while it is being filled. With
`use TypeGuard, blank: true`, a module whose `t()` is a struct type also
defines `@type blank()`, the same struct type with `| nil` added to each
field. A function that takes or returns such a struct, such as an Ecto
`changeset/2`, can then use an accurate type:

```elixir
@spec changeset(blank(), map()) :: Ecto.Changeset.t()
```
