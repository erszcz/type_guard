# Ecto

The integration is active when Ecto is a dependency of the project.

## Why validate against `t()`

Ecto casts a field by its Ecto type, which can be wider than its type in
`t()`:

- A `:map` field cast from any map, typed as a struct or a map with specific
  keys.
- A field that `t()` types as non-nil, but that the changeset does not
  require.
- A value that a changeset function sets with `put_change/3`, which Ecto
  does not cast.

`TypeGuard.Ecto` checks a changeset against the `t()` of its schema:

```elixir
defmodule Shop.Customer do
  use Ecto.Schema
  use TypeGuard

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :preferences, :map
    embeds_one :address, Shop.Address
  end

  @type t() :: %__MODULE__{
          name: String.t(),
          preferences: Shop.Preferences.t() | nil,
          address: Shop.Address.t()
        }

  def changeset(customer \\ %__MODULE__{}, attrs) do
    customer
    |> cast(attrs, [:name, :preferences])
    |> cast_embed(:address)
    |> TypeGuard.Ecto.validate()
  end
end
```

## The validations

| Function | Error | Added to |
| --- | --- | --- |
| `TypeGuard.Ecto.validate_non_nil/1` | `{"can't be blank", validation: :required}` | each required field that is `nil` |
| `TypeGuard.Ecto.validate_type/1` | `{"is invalid", validation: :type}` | each field whose value does not conform |
| `TypeGuard.Ecto.validate/1` | both, in that order | |

Both validations:

- go into the nested changesets of embeds and associations, and report an
  error in the nested changeset where it occurs. A nested changeset that
  replaces or deletes an embed is skipped.
- leave a field that already has an error alone.
- skip a changeset whose schema does not use TypeGuard, but still go into
  its nested changesets.

`validate_non_nil/1` adds the same error as `Ecto.Changeset.validate_required/3`,
but it accepts an empty string. Ecto casts an empty string to `nil` by
default, so this only matters for a value set without casting.

Run `validate_non_nil/1` before `validate_type/1`, or use `validate/1`:
`validate_type/1` alone reports `nil` in a required field as invalid.

## Polymorphic embeds

With [PolymorphicEmbed](https://hex.pm/packages/polymorphic_embed) as a
dependency, a field declared with `polymorphic_embeds_one/2` or
`polymorphic_embeds_many/2` and typed with `PolymorphicEmbed.t()` is checked
against its declared embed modules. `PolymorphicEmbed.t()` itself is
`any()`, so without the integration the field would not be checked.

```elixir
polymorphic_embeds_many :attachments,
  types: [image: Shop.Image, video: Shop.Video],
  type_field_name: :kind,
  on_type_not_found: :raise,
  on_replace: :delete

@type t() :: %__MODULE__{attachments: [PolymorphicEmbed.t()]}
```

Here each attachment must be a `Shop.Image` or `Shop.Video` struct whose
fields conform to its `t()`. The rest of the field type stays as written,
such as the list or `| nil`. See `TypeGuard.PolymorphicEmbed`.

PolymorphicEmbed puts the cast embed structs into the changes, not nested
changesets. So the validations report an error in a polymorphic embed on the
polymorphic field itself, as `{"is invalid", validation: :type}`, even for a
`nil` in a required field of the embed.
