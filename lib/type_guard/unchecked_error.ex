defmodule TypeGuard.UncheckedError do
  @moduledoc """
  A module that uses TypeGuard with `unchecked: :raise` meets a type that it
  cannot check.

  The error comes at compile time for a part of a type that the module itself
  cannot check, such as a type with parameters. It comes at run time for a type
  of another project module that does not check it, because that module can
  compile later.
  """

  defexception [:message]
end
