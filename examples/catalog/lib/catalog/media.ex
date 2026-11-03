defmodule Catalog.Image do
  @moduledoc "An image of a product."
  use Ecto.Schema
  use TypeGuard

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:url, :string)
    field(:alt, :string)
  end

  @type t() :: %__MODULE__{url: String.t(), alt: String.t() | nil}

  @doc false
  def changeset(image, attrs), do: cast(image, attrs, [:url, :alt])
end

defmodule Catalog.Video do
  @moduledoc "A video of a product."
  use Ecto.Schema
  use TypeGuard

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:url, :string)
    field(:seconds, :integer)
  end

  @type t() :: %__MODULE__{url: String.t(), seconds: pos_integer()}

  @doc false
  def changeset(video, attrs), do: cast(video, attrs, [:url, :seconds])
end
