defmodule TypeGuard.Fixtures.Address do
  @moduledoc false
  use Ecto.Schema
  use TypeGuard
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:street, :string)
    field(:postcode, :string)
  end

  @type t() :: %__MODULE__{street: String.t(), postcode: String.t() | nil}

  def changeset(address, attrs), do: cast(address, attrs, [:street, :postcode])
end

defmodule TypeGuard.Fixtures.Settings do
  @moduledoc false
  use TypeGuard

  defstruct [:theme]
  @type t() :: %__MODULE__{theme: :light | :dark}
end

defmodule TypeGuard.Fixtures.Customer do
  @moduledoc false
  use Ecto.Schema
  use TypeGuard
  import Ecto.Changeset

  alias TypeGuard.Fixtures.{Address, Settings}

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:email, :string)
    # Ecto casts any map here, but `t()` wants a `Settings` struct.
    field(:settings, :map)
    field(:labels, {:map, :integer}, default: %{})
    embeds_one(:address, Address)
    embeds_many(:previous_addresses, Address, on_replace: :delete)
  end

  @type t() :: %__MODULE__{
          name: String.t(),
          email: String.t() | nil,
          settings: Settings.t() | nil,
          labels: %{optional(String.t()) => non_neg_integer()},
          address: Address.t(),
          previous_addresses: [Address.t()]
        }

  def changeset(customer \\ %__MODULE__{}, attrs) do
    customer
    |> cast(attrs, [:name, :email, :settings, :labels])
    |> cast_embed(:address)
    |> cast_embed(:previous_addresses)
  end
end

defmodule TypeGuard.Fixtures.Image do
  @moduledoc false
  use Ecto.Schema
  use TypeGuard
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:url, :string)
    field(:width, :integer)
  end

  @type t() :: %__MODULE__{url: String.t(), width: pos_integer()}

  def changeset(image, attrs), do: cast(image, attrs, [:url, :width])
end

defmodule TypeGuard.Fixtures.Video do
  @moduledoc false
  use Ecto.Schema
  use TypeGuard
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:url, :string)
    field(:seconds, :integer)
  end

  @type t() :: %__MODULE__{url: String.t(), seconds: non_neg_integer()}

  def changeset(video, attrs), do: cast(video, attrs, [:url, :seconds])
end

defmodule TypeGuard.Fixtures.Post do
  @moduledoc false
  use Ecto.Schema
  use TypeGuard
  import Ecto.Changeset
  import PolymorphicEmbed

  alias TypeGuard.Fixtures.{Image, Video}

  @primary_key false
  embedded_schema do
    field(:title, :string)

    polymorphic_embeds_one(:cover,
      types: [image: Image, video: Video],
      type_field_name: :kind,
      on_type_not_found: :raise,
      on_replace: :update
    )

    polymorphic_embeds_many(:attachments,
      types: [image: Image, video: Video],
      type_field_name: :kind,
      on_type_not_found: :raise,
      on_replace: :delete
    )
  end

  @type t() :: %__MODULE__{
          title: String.t(),
          cover: PolymorphicEmbed.t() | nil,
          attachments: [PolymorphicEmbed.t()]
        }

  def changeset(post \\ %__MODULE__{}, attrs) do
    post
    |> cast(attrs, [:title])
    |> cast_polymorphic_embed(:cover)
    |> cast_polymorphic_embed(:attachments)
  end
end
