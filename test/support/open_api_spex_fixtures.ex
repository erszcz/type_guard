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
