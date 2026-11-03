defmodule Catalog.Product do
  @moduledoc "A product in the catalog."
  use Ecto.Schema
  use TypeGuard, blank: true

  import Ecto.Changeset
  import PolymorphicEmbed

  alias Catalog.{Dimensions, Image, Sku, Video}

  @primary_key false
  embedded_schema do
    field(:id, :string)
    field(:sku, :string)
    field(:name, :string)
    field(:price, :decimal)
    field(:status, Ecto.Enum, values: [:draft, :active, :retired], default: :draft)
    field(:tags, {:array, :string}, default: [])
    # Ecto casts any map here. `t()` admits string keys and values only.
    field(:attributes, :map, default: %{})
    field(:released_on, :date)
    embeds_one(:dimensions, Dimensions, on_replace: :update)

    polymorphic_embeds_many(:media,
      types: [image: Image, video: Video],
      type_field_name: :kind,
      on_type_not_found: :raise,
      on_replace: :delete
    )
  end

  @type status() :: :draft | :active | :retired
  @type t() :: %__MODULE__{
          id: UUIDv7.t(),
          sku: Sku.t(),
          name: String.t(),
          price: Decimal.t(),
          status: status(),
          tags: [String.t()],
          attributes: %{optional(String.t()) => String.t()},
          released_on: Date.t() | nil,
          dimensions: Dimensions.t(),
          media: [PolymorphicEmbed.t()]
        }

  @doc "Casts `attrs` and validates the result against `t()`."
  @spec changeset(blank(), map()) :: Ecto.Changeset.t()
  def changeset(product \\ %__MODULE__{}, attrs) do
    product
    |> cast(attrs, [:id, :sku, :name, :price, :status, :tags, :attributes, :released_on])
    |> cast_embed(:dimensions)
    |> cast_polymorphic_embed(:media)
    |> TypeGuard.Ecto.validate()
  end
end
