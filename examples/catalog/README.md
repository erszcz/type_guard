# Catalog

A small Ecto project that uses TypeGuard. It shows:

- an embedded schema checked against its `t()` with `TypeGuard.Ecto.validate/1`,
- a `:map` field whose type in `t()` is narrower than what Ecto casts,
- nested embeds, with errors reported in the nested changeset,
- a polymorphic embed checked against its declared embed modules,
- types of dependencies (`UUIDv7.t()`, `Decimal.t()`) and of another project
  module (`Catalog.Sku.t()`),
- the coverage report of `TypeGuard.Coverage`.

```console
mix deps.get
mix test
```
