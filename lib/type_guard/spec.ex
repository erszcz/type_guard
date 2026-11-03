defmodule TypeGuard.Spec do
  @moduledoc false
  # Builds checks from the compiled typespecs of a module of another
  # application, such as a dependency or Elixir itself. The typespecs are in
  # the Erlang abstract format.

  alias TypeGuard.Compiler

  @doc false
  # Returns the check of `v` against `module.name()`, or `:error` when the
  # module has no such type.
  @spec check(module(), atom(), Macro.t(), map()) :: {:ok, Macro.t()} | :error
  def check(module, name, v, ctx) do
    with {:ok, types} <- fetch_types(module),
         {kind, {^name, body, []}} <- Enum.find(types, &match?({_, {^name, _, []}}, &1)) do
      Compiler.inlined(module)
      ctx = %{ctx | module: module, locals: %{}, seen: [{module, name}]}
      {:ok, if(kind == :opaque, do: opaque(body, v), else: to_check(body, v, ctx))}
    else
      _ -> :error
    end
  end

  defp fetch_types(module) do
    key = {__MODULE__, module}

    case Process.get(key) do
      nil ->
        types = Code.Typespec.fetch_types(module)
        Process.put(key, types)
        types

      types ->
        types
    end
  end

  # An opaque type hides its structure: only a struct type is checked, by its
  # module.
  defp opaque({:type, _, :map, fields}, v) do
    struct =
      Enum.find_value(fields, fn
        {:type, _, :map_field_exact, [{:atom, _, :__struct__}, {:atom, _, mod}]} -> mod
        _ -> nil
      end)

    if struct, do: quote(do: is_struct(unquote(v), unquote(struct))), else: true
  end

  defp opaque(_body, _v), do: true

  defp to_check({:ann_type, _, [_var, type]}, v, ctx), do: to_check(type, v, ctx)
  defp to_check({:paren_type, _, [type]}, v, ctx), do: to_check(type, v, ctx)
  defp to_check({:atom, _, atom}, v, _ctx), do: quote(do: unquote(v) === unquote(atom))
  defp to_check({:integer, _, int}, v, _ctx), do: quote(do: unquote(v) === unquote(int))

  defp to_check({:op, _, :-, {:integer, _, int}}, v, _ctx),
    do: quote(do: unquote(v) === unquote(-int))

  # Literals go first and the ones that `atom()` covers are dropped, as in
  # `TypeGuard.Compiler.check/3`.
  defp to_check({:type, _, :union, types}, v, ctx) do
    types = Enum.uniq_by(types, &:erl_parse.map_anno(fn _anno -> 0 end, &1))

    types =
      if Enum.any?(types, &match?({:type, _, name, []} when name in [:atom, :module, :node], &1)),
        do:
          Enum.reject(types, &(match?({:atom, _, _}, &1) or match?({:type, _, :boolean, []}, &1))),
        else: types

    {literals, rest} = Enum.split_with(types, &(elem(&1, 0) in [:atom, :integer, :op]))
    (literals ++ rest) |> Enum.map(&to_check(&1, v, ctx)) |> Compiler.disjunction()
  end

  defp to_check({:type, _, :range, [low, high]}, v, _ctx) do
    quote do
      is_integer(unquote(v)) and unquote(v) >= unquote(integer(low)) and
        unquote(v) <= unquote(integer(high))
    end
  end

  defp to_check({:type, _, :binary, [{:integer, _, base}, {:integer, _, unit}]}, v, _ctx),
    do: Compiler.bits(base, unit, v)

  defp to_check({:type, _, kind, [elem]}, v, ctx) when kind in [:list, :nonempty_list] do
    x = Macro.unique_var(:x, __MODULE__)
    elem_check = to_check(elem, x, ctx)
    nonempty = if kind == :nonempty_list, do: quote(do: unquote(v) != []), else: true

    all =
      if elem_check == true,
        do: true,
        else: quote(do: Enum.all?(unquote(v), fn unquote(x) -> unquote(elem_check) end))

    Compiler.conjunction([quote(do: is_list(unquote(v))), nonempty, all])
  end

  defp to_check({:type, _, :map, :any}, v, _ctx), do: quote(do: is_map(unquote(v)))

  defp to_check({:type, _, :map, fields}, v, ctx) do
    pairs =
      for {:type, _, kind, [key, value]} <- fields do
        case {kind, key} do
          {:map_field_exact, {:atom, _, atom}} -> {atom, {__MODULE__, value}}
          {_kind, key} -> {{:optional, [], [{__MODULE__, key}]}, {__MODULE__, value}}
        end
      end

    Compiler.map(pairs, v, ctx)
  end

  defp to_check({:type, _, :tuple, :any}, v, _ctx), do: quote(do: is_tuple(unquote(v)))

  defp to_check({:type, _, :tuple, elems}, v, ctx),
    do: Compiler.tuple(Enum.map(elems, &{__MODULE__, &1}), v, ctx)

  defp to_check({:type, _, :fun, _args}, v, _ctx), do: quote(do: is_function(unquote(v)))

  defp to_check({:remote_type, _, [{:atom, _, mod}, {:atom, _, name}, args]}, v, ctx),
    do: Compiler.remote(mod, name, args, v, ctx)

  defp to_check({:user_type, _, name, []}, v, ctx) do
    key = {ctx.module, name}

    cond do
      key in ctx.seen or ctx.depth == 0 ->
        true

      true ->
        with {:ok, types} <- fetch_types(ctx.module),
             {kind, {^name, body, []}} <- Enum.find(types, &match?({_, {^name, _, []}}, &1)) do
          ctx = %{ctx | seen: [key | ctx.seen], depth: ctx.depth - 1}
          if kind == :opaque, do: opaque(body, v), else: to_check(body, v, ctx)
        else
          _ -> true
        end
    end
  end

  defp to_check({:type, _, name, []}, v, ctx) do
    case Compiler.builtin(name, [], v, ctx) do
      :unknown -> true
      code -> code
    end
  end

  defp to_check(_other, _v, _ctx), do: true

  @doc false
  # Checks a part of an abstract type that `TypeGuard.Compiler.map/3` or
  # `tuple/3` passes back as `{TypeGuard.Spec, abstract}`.
  @spec part(term(), Macro.t(), map()) :: Macro.t()
  def part(abstract, v, ctx), do: to_check(abstract, v, ctx)

  defp integer({:integer, _, int}), do: int
  defp integer({:op, _, :-, {:integer, _, int}}), do: -int
end
