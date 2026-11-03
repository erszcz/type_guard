defmodule Catalog.Sku do
  @moduledoc "Stock keeping units."
  use TypeGuard

  @typedoc "A stock keeping unit, such as `\"KB-1042\"`."
  @type t() :: String.t()
end
