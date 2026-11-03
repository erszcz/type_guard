defmodule Catalog.Dimensions do
  @moduledoc "The size of a product."
  use Ecto.Schema
  use TypeGuard

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:width, :integer)
    field(:height, :integer)
    field(:depth, :integer)
    field(:unit, Ecto.Enum, values: [:mm, :cm, :in], default: :mm)
  end

  @type t() :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          depth: pos_integer() | nil,
          unit: :mm | :cm | :in
        }

  @doc false
  def changeset(dimensions, attrs), do: cast(dimensions, attrs, [:width, :height, :depth, :unit])
end
