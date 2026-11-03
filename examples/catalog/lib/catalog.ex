defmodule Catalog do
  @moduledoc "Builds products from untrusted attributes."

  alias Catalog.Product

  @doc "Returns a product that conforms to `Catalog.Product.t()`, or the changeset errors."
  @spec new_product(map()) :: {:ok, Product.t()} | {:error, Ecto.Changeset.t()}
  def new_product(attrs) do
    attrs
    |> Product.changeset()
    |> Ecto.Changeset.apply_action(:insert)
  end
end
