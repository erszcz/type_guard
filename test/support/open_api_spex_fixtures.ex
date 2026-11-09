defmodule TypeGuard.Fixtures.OpenApiSpex.Order do
  @moduledoc false
  use TypeGuard

  alias OpenApiSpex.Schema

  @schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string},
      note: %Schema{type: :string},
      placed_at: %Schema{type: :string, format: :"date-time"},
      status: %Schema{type: :string, enum: [:open, :paid], default: :open}
    },
    required: [:id, :placed_at],
    additionalProperties: false,
    "x-struct": __MODULE__
  }

  defstruct [:id, :note, :placed_at, :status]

  def schema, do: @schema

  @type t() :: unquote(TypeGuard.OpenApiSpex.type(@schema, __MODULE__))
end

defmodule TypeGuard.Fixtures.OpenApiSpex.Search do
  @moduledoc false
  use TypeGuard

  alias OpenApiSpex.Schema

  @schema %Schema{
    type: :object,
    properties: %{
      limit: %Schema{type: :integer, default: 10},
      tag: %Schema{type: :string},
      tags: %Schema{type: :array, items: %Schema{type: :string}, minItems: 1},
      term: %Schema{type: :string}
    },
    required: [:term],
    additionalProperties: false
  }

  def schema, do: @schema

  @type t() :: unquote(TypeGuard.OpenApiSpex.type(@schema, __MODULE__))
end

# A filter is a leaf or a group of filters, so the check of a nested group goes through the two
# modules in turn.
defmodule TypeGuard.Fixtures.OpenApiSpex.Leaf do
  @moduledoc false
  use TypeGuard, unchecked: :raise

  alias OpenApiSpex.Schema

  @schema %Schema{
    title: "Leaf",
    type: :object,
    properties: %{
      name: %Schema{type: :string, enum: [:any_of, :none_of]},
      values: %Schema{type: :array, items: %Schema{type: :string}, minItems: 1}
    },
    required: [:name, :values],
    additionalProperties: false,
    "x-struct": __MODULE__
  }

  defstruct [:name, :values]

  def schema, do: @schema

  @type t() :: unquote(TypeGuard.OpenApiSpex.type(@schema, __MODULE__))
end

defmodule TypeGuard.Fixtures.OpenApiSpex.Group do
  @moduledoc false
  use TypeGuard, unchecked: :raise

  alias OpenApiSpex.Schema
  alias TypeGuard.Fixtures.OpenApiSpex.Leaf

  @schema %Schema{
    title: "Group",
    type: :object,
    properties: %{
      conjunction: %Schema{type: :string, enum: [:and, :or]},
      filters: %Schema{type: :array, items: %Schema{oneOf: [Leaf, __MODULE__]}}
    },
    required: [:conjunction, :filters],
    additionalProperties: false,
    "x-struct": __MODULE__
  }

  defstruct [:conjunction, :filters]

  def schema, do: @schema

  @type t() :: unquote(TypeGuard.OpenApiSpex.type(@schema, __MODULE__))
end
