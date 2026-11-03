defmodule TypeGuard.Coverage do
  @moduledoc """
  Reports which remote types the checks of a module cover.

  A check of a remote type is one of:

    * `:override` - an inline check from the table of known types, such as
      `is_struct(value, DateTime)` for `DateTime.t()`.
    * `:spec` - an inline check built at compile time from the compiled
      typespec of a module of another application.
    * `:runtime` - a call to `TypeGuard.check/3` at runtime. It is `:checked`
      when the module uses `TypeGuard` and checks the type, and `:trusted`
      otherwise.
    * `:trusted` - not checked: a type with parameters, a type that a
      typespec does not define, or a type deeper than the expansion limit.

  See the [remote types guide](remote_types.md).
  """

  @typedoc "A remote type reference and how its check works."
  @type ref() :: %{
          module: module(),
          type: atom(),
          arity: arity(),
          check: :override | :spec | :checked | :trusted
        }

  @doc "Returns the remote type references in the types of `module`."
  @spec references(module()) :: [ref()]
  def references(module) when is_atom(module) do
    if TypeGuard.adopted?(module) do
      for {mod, type, arity, kind} <- module.__type_guard__(:references) do
        %{module: mod, type: type, arity: arity, check: resolve(kind, mod, type)}
      end
    else
      []
    end
  end

  @doc """
  Returns the references of `modules` that are not checked, with how often
  each appears.
  """
  @spec trusted([module()]) :: %{optional({module(), atom(), arity()}) => pos_integer()}
  def trusted(modules) when is_list(modules) do
    for module <- modules,
        %{check: :trusted} = ref <- references(module),
        reduce: %{} do
      acc -> Map.update(acc, {ref.module, ref.type, ref.arity}, 1, &(&1 + 1))
    end
  end

  defp resolve(:runtime, mod, type) do
    if type in TypeGuard.checked_types(mod), do: :checked, else: :trusted
  end

  defp resolve(kind, _mod, _type), do: kind
end
