# Remote types

A remote type, such as `Shop.Money.t()` or `Decimal.t()`, is checked in one
of four ways. The first one that applies wins:

1. **An override.** A short table maps common types to an inline check.
2. **A call to the module.** When the module uses TypeGuard, or belongs to
   the project being compiled, the check calls `TypeGuard.check/3` at
   runtime.
3. **The compiled typespec.** When the module belongs to another
   application, such as a dependency, Elixir or Erlang/OTP, the check is
   built at compile time from its typespec and inlined.
4. **Trusted.** Otherwise the type is not checked.

`TypeGuard.Coverage.references/1` shows which way each remote type of a
module takes.

## Project modules

A module belongs to the project when its compiled file is in the project's
build directory, or when it is not compiled yet. Its types are checked by a
call to its `__type_guard__/2` at runtime, not inlined, for two reasons:

- A module does not get a compile-time dependency on each module whose
  types it uses, so a change of a type does not recompile its users.
- A reload of the module updates every check that uses its types. See
  [Code reloading](code_reloading.md).

A project module that does not use TypeGuard has no checks to call, so its
types are trusted. Add `use TypeGuard` to it to check them.

A cross-module call costs a fraction of a microsecond.

## Other applications

The typespec of a module of another application is read from its compiled
file when the module that uses the type compiles, and the check is inlined. Such a module does not change while the project
runs, so the inlined check stays accurate. The generated code `require`s
each module whose typespec it inlines, so that recompiling that module, such
as after a dependency upgrade, recompiles its users too.

This finds the types of any dependency without configuration. For example,
`UUIDv7.t()` is `<<_::288>>`, and its check becomes
`is_bitstring(value) and bit_size(value) == 288`.

The expansion follows the remote and local types inside a typespec up to a
depth of six definitions, and trusts the rest. A module of another
application that uses TypeGuard is called like a project module instead.

An opaque type of another application hides its structure. Its check is
`is_struct/2` when its typespec is a struct type, and it is trusted
otherwise.

Path dependencies and the other applications of an umbrella project are
other applications too: their types are inlined.

## Overrides

Some types would make a large check for no gain if they were built from
their typespec. These types have an override:

| Type | Check |
| --- | --- |
| `String.t()` | `is_binary/1` |
| `Date.t()`, `Time.t()`, `DateTime.t()`, `NaiveDateTime.t()`, `Duration.t()` | `is_struct/2` |
| `MapSet.t()`, `Range.t()`, `Regex.t()`, `URI.t()`, `Version.t()` | `is_struct/2` |
| `Decimal.t()`, `Plug.Upload.t()` | `is_struct/2` |

An override does not check the parameters of a type: `MapSet.t(String.t())`
checks for a `MapSet` only.

## Finding what is not checked

`TypeGuard.Coverage.trusted/1` counts the remote types that are not checked
across modules:

```elixir
{:ok, modules} = :application.get_key(:my_app, :modules)
TypeGuard.Coverage.trusted(modules)
#=> %{{MyApp.Legacy, :id, 0} => 12, {MyApp.Cache, :entry, 1} => 3}
```

A project module in that list can `use TypeGuard`. A type with parameters
stays trusted.

## Unchecked types

By default, a part of a type that a check cannot check lets any value pass.
With `use TypeGuard, unchecked: :raise`, the module makes it an error:

- At compile time, the module does not compile when one of its checked types
  uses a type with parameters, a recursive private type, a recursive type that
  the module does not check, a built-in type that TypeGuard does not know, a
  type of another application without a typespec, an override with
  parameters, or `TypeGuard.unchecked()`.
- At run time, a check raises `TypeGuard.UncheckedError` when it calls a type
  of another project module that does not use TypeGuard, or that does not
  check that type. That module can compile after this one, so the check
  happens when it is called.

`TypeGuard.unchecked()` is `term()` for static tools. Generated code can use it
to mark a value whose type it does not know, so that a module with
`unchecked: :raise` cannot compile with it.

The typespec of another application is still trusted where it cannot be
checked, for example below the expansion limit or in an opaque type that is
not a struct. A module with `unchecked: :raise` applies the option to its own
checks. A type of another module is checked by the options of that module.
