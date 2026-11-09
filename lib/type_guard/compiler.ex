defmodule TypeGuard.Compiler do
  @moduledoc false
  # Generates the checks of a module that uses TypeGuard. Each check is a
  # boolean expression built at compile time from the typespec AST.

  alias TypeGuard.Overrides
  alias TypeGuard.Spec

  # How many remote and local type definitions a check expands inline before
  # it trusts the rest.
  @max_depth 6
  @references {__MODULE__, :references}
  @inlined {__MODULE__, :inlined}

  @doc false
  defmacro __before_compile__(env) do
    module = env.module
    uses = module |> Module.get_attribute(:type_guard_uses) |> Enum.reverse()
    locals = local_types(module)
    Process.put(@references, [])
    Process.put(@inlined, MapSet.new())

    base = %{module: module, env: env, locals: locals, seen: [], depth: @max_depth, record?: true}
    v = Macro.var(:value, __MODULE__)
    types = selected_types(module, uses)
    all_struct_fields = struct_fields(module, locals, env)
    struct_fields = if List.keymember?(types, :t, 0), do: all_struct_fields

    field_clauses =
      for {field, type} <- struct_fields || [] do
        quote do
          def __type_guard_field__(unquote(field), unquote(v)),
            do: unquote(check(type, v, %{base | seen: [{:t, 0}]}))
        end
      end

    type_clauses =
      for {name, body} <- types do
        code =
          if name == :t and struct_fields,
            do: struct_check(module, struct_fields, v),
            else: check(body, v, %{base | seen: [{name, 0}]})

        quote do
          def __type_guard__(unquote(name), unquote(v)), do: unquote(code)
        end
      end

    references = @references |> Process.delete() |> Enum.reverse() |> Enum.uniq()

    # A compile-time dependency on each module whose typespec a check inlines,
    # so that a change of that module, such as an upgrade of a dependency,
    # recompiles this one.
    requires =
      for mod <- Enum.sort(Process.delete(@inlined)), do: quote(do: require(unquote(mod)))

    names = for {name, _body} <- types, do: name
    fields = for {field, _type} <- struct_fields || [], do: field

    # A module that selects no type generates no checks: it is not adopted, and
    # its types count as trusted.
    if types == [] do
      blank_type(uses, all_struct_fields)
    else
      generated(
        requires,
        names,
        fields,
        references,
        type_clauses,
        field_clauses,
        uses,
        all_struct_fields
      )
    end
  end

  defp generated(
         requires,
         names,
         fields,
         references,
         type_clauses,
         field_clauses,
         uses,
         all_struct_fields
       ) do
    quote do
      unquote_splicing(requires)

      @doc false
      @spec __type_guard__(:types | :fields | :references) :: [term()]
      def __type_guard__(:types), do: unquote(names)
      def __type_guard__(:fields), do: unquote(fields)
      def __type_guard__(:references), do: unquote(Macro.escape(references))

      @doc false
      @spec __type_guard__(atom(), term()) :: boolean()
      unquote_splicing(type_clauses)
      # A type with parameters, or no such type: not checked.
      def __type_guard__(_type, _value), do: true

      @doc false
      @spec __type_guard_field__(atom(), term()) :: boolean()
      unquote_splicing(field_clauses)
      def __type_guard_field__(_field, _value), do: true

      unquote(blank_type(uses, all_struct_fields))
    end
  end

  # The public types that any `use TypeGuard` of the module selects with its
  # `:only` and `:except` options.
  defp selected_types(module, uses) do
    types = public_types(module)
    names = for {name, _body} <- types, do: name
    selected = uses |> Enum.map(&selection(module, &1, names)) |> Enum.reduce(&MapSet.union/2)
    Enum.filter(types, fn {name, _body} -> MapSet.member?(selected, name) end)
  end

  defp selection(module, opts, names) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    if only && except != [] do
      raise ArgumentError, "use TypeGuard in #{inspect(module)}: give :only or :except, not both"
    end

    unknown = (List.wrap(only) ++ except) -- names

    if unknown != [] and not Keyword.get(opts, :allow_missing, false) do
      raise ArgumentError,
            "use TypeGuard in #{inspect(module)}: no public type without parameters named " <>
              Enum.map_join(unknown, ", ", &"#{&1}/0")
    end

    MapSet.new((only || names) -- except) |> MapSet.intersection(MapSet.new(names))
  end

  # The arguments of a type name. A name without parentheses has `nil` there,
  # or the module of its context when a macro generates it.
  defp type_args(args) when is_list(args), do: args
  defp type_args(args) when is_atom(args), do: []

  # The public types without parameters, with their bodies, in the order of
  # their definitions. The attributes list the newest first.
  defp public_types(module) do
    for kind <- [:type, :opaque],
        {_kind, {:"::", _, [{name, _, args}, body]}, _pos} <-
          Enum.reverse(Module.get_attribute(module, kind) || []),
        type_args(args) == [],
        uniq: true,
        do: {name, body}
  end

  defp local_types(module) do
    for kind <- [:type, :typep, :opaque],
        {_kind, {:"::", _, [{name, _, args}, body]}, _pos} <-
          Module.get_attribute(module, kind) || [],
        into: %{},
        do: {{name, length(type_args(args))}, {kind, body}}
  end

  # The fields of `t()` when it is a struct type of the module, with the
  # field types that the integrations adjust.
  defp struct_fields(module, locals, env) do
    case locals do
      %{{:t, 0} => {_kind, {:%, _, [mod, {:%{}, _, pairs}]}}} ->
        if expand_alias(mod, env) == module do
          for {field, type} <- pairs, is_atom(field), field != :__struct__ do
            {field, TypeGuard.PolymorphicEmbed.adjust(module, field, type)}
          end
        end

      _other ->
        nil
    end
  end

  defp struct_check(module, fields, v) do
    Enum.reduce(fields, quote(do: is_struct(unquote(v), unquote(module))), fn {field, _type},
                                                                              acc ->
      quote do
        unquote(acc) and
          __type_guard_field__(unquote(field), :erlang.map_get(unquote(field), unquote(v)))
      end
    end)
  end

  defp blank_type(uses, struct_fields) do
    if Enum.any?(uses, &Keyword.get(&1, :blank, false)) and struct_fields do
      pairs = for {field, type} <- struct_fields, do: {field, quote(do: unquote(type) | nil)}

      quote do
        @typedoc "`t()` before its fields are set: each field can be `nil`."
        @type blank() :: %__MODULE__{unquote_splicing(pairs)}
      end
    end
  end

  @doc false
  # Records that a check inlines the typespec of `module`.
  @spec inlined(module()) :: :ok
  def inlined(module) do
    Process.put(@inlined, MapSet.put(Process.get(@inlined, MapSet.new()), module))
    :ok
  end

  @doc false
  # Returns the quoted check of `v` against the typespec AST `type`.
  @spec check(Macro.t(), Macro.t(), map()) :: Macro.t()
  def check(type, v, ctx)

  # A part of a compiled typespec, from `TypeGuard.Spec`. Typespec AST cannot
  # hold this tuple: an alias in it is an `:__aliases__` node.
  def check({TypeGuard.Spec, abstract}, v, ctx), do: Spec.part(abstract, v, ctx)
  def check({:"::", _, [_name, type]}, v, ctx), do: check(type, v, ctx)

  def check({:|, _, _} = union, v, ctx) do
    union
    |> union_members()
    |> simplify_union()
    |> Enum.map(&check(&1, v, ctx))
    |> disjunction()
  end

  def check(atom, v, _ctx) when is_atom(atom), do: quote(do: unquote(v) === unquote(atom))
  def check(int, v, _ctx) when is_integer(int), do: quote(do: unquote(v) === unquote(int))

  def check({:-, _, [int]}, v, _ctx) when is_integer(int),
    do: quote(do: unquote(v) === unquote(-int))

  def check({:.., _, [low, high]}, v, _ctx) do
    quote do
      is_integer(unquote(v)) and unquote(v) >= unquote(integer(low)) and
        unquote(v) <= unquote(integer(high))
    end
  end

  # A function type, such as `(integer() -> atom())`, is a list of one `->` in
  # the typespec AST. Only the arity is checked.
  def check([{:->, _, [[{:..., _, _}], _result]}], v, _ctx),
    do: quote(do: is_function(unquote(v)))

  def check([{:->, _, [args, _result]}], v, _ctx) when is_list(args),
    do: quote(do: is_function(unquote(v), unquote(length(args))))

  # Lists: `[]`, `[t]`, `[t, ...]` and keyword lists such as `[a: t, b: u]`.
  def check([], v, _ctx), do: quote(do: unquote(v) === [])
  def check([{:..., _, _}], v, _ctx), do: quote(do: is_list(unquote(v)) and unquote(v) != [])
  def check([elem, {:..., _, _}], v, ctx), do: list(elem, v, ctx, :nonempty)
  def check([elem], v, ctx), do: list(elem, v, ctx, :any)

  def check([_ | _] = elems, v, ctx) do
    union = Enum.reduce(elems, &quote(do: unquote(&2) | unquote(&1)))
    list(union, v, ctx, :any)
  end

  def check({:%{}, _, pairs}, v, ctx) when is_list(pairs), do: map(pairs, v, ctx)

  def check({:%, _, [mod, {:%{}, _, pairs}]}, v, ctx) do
    mod = expand(mod, ctx)

    Enum.reduce(pairs, quote(do: is_struct(unquote(v), unquote(mod))), fn {field, type}, acc ->
      field_check = check(type, quote(do: :erlang.map_get(unquote(field), unquote(v))), ctx)
      quote(do: unquote(acc) and unquote(field_check))
    end)
  end

  def check({:<<>>, _, segments}, v, _ctx) do
    {base, unit} =
      Enum.reduce(segments, {0, 0}, fn
        {:"::", _, [{:_, _, _}, {:*, _, [{:_, _, _}, unit]}]}, {base, _unit} -> {base, unit}
        {:"::", _, [{:_, _, _}, size]}, {_base, unit} when is_integer(size) -> {size, unit}
      end)

    bits(base, unit, v)
  end

  def check({:{}, _, elems}, v, ctx) when is_list(elems), do: tuple(elems, v, ctx)
  def check({left, right}, v, ctx), do: tuple([left, right], v, ctx)

  def check({{:., _, [mod, name]}, _, args}, v, ctx) when is_atom(name) and is_list(args),
    do: remote(expand(mod, ctx), name, args, v, ctx)

  def check({name, _, args}, v, ctx) when is_atom(name) and (is_list(args) or is_atom(args)),
    do: local(name, type_args(args), v, ctx)

  def check(_other, _v, _ctx), do: true

  defp union_members({:|, _, [left, right]}), do: union_members(left) ++ union_members(right)
  defp union_members(type), do: [type]

  # Literals go first: after a broader check such as `is_atom(v)` fails, a
  # comparison of `v` with an atom can never succeed, and Elixir warns about
  # it. A repeated member, such as the second `nil` that some macros add, and
  # a literal or `boolean()` that a member `atom()` covers are dropped.
  defp simplify_union(members) do
    members =
      Enum.uniq_by(
        members,
        &Macro.prewalk(&1, fn node -> Macro.update_meta(node, fn _ -> [] end) end)
      )

    members =
      if Enum.any?(members, &any_atom?/1),
        do:
          Enum.reject(
            members,
            &(is_atom(&1) or match?({:boolean, _, args} when not is_list(args) or args == [], &1))
          ),
        else: members

    {literals, rest} = Enum.split_with(members, &literal?/1)
    literals ++ rest
  end

  defp any_atom?({name, _, args})
       when name in [:atom, :module, :node] and (not is_list(args) or args == []),
       do: true

  defp any_atom?(_type), do: false

  defp literal?(type) when is_atom(type) or is_integer(type), do: true
  defp literal?({:-, _, [int]}) when is_integer(int), do: true
  defp literal?(_type), do: false

  @doc false
  # Joins checks with `or`. A check that is always true makes the whole one true.
  @spec disjunction([Macro.t()]) :: Macro.t()
  def disjunction(checks) do
    case Enum.reject(checks, &(&1 == false)) do
      [] ->
        false

      checks ->
        if true in checks,
          do: true,
          else: Enum.reduce(checks, &quote(do: unquote(&2) or unquote(&1)))
    end
  end

  defp local(name, args, v, ctx) do
    case builtin(name, args, v, ctx) do
      :unknown -> local_type(name, args, v, ctx)
      code -> code
    end
  end

  defp local_type(name, args, v, ctx) do
    key = {name, length(args)}

    cond do
      args != [] ->
        true

      key in ctx.seen ->
        # A recursive type: a public one calls its own check, a private one
        # is not checked.
        case ctx.locals do
          %{^key => {kind, _body}} when kind in [:type, :opaque] ->
            quote(do: __type_guard__(unquote(name), unquote(v)))

          _ ->
            true
        end

      true ->
        case ctx.locals do
          %{^key => {_kind, body}} -> check(body, v, %{ctx | seen: [key | ctx.seen]})
          _ -> true
        end
    end
  end

  @doc false
  # Checks `mod.name(args)`. The overrides come first. A module of the
  # project, or one that uses TypeGuard, gets a runtime call. A module of
  # another application gets its compiled typespec inlined.
  @spec remote(module(), atom(), list(), Macro.t(), map()) :: Macro.t()
  def remote(mod, name, args, v, ctx) do
    arity = length(args)

    {kind, code} =
      cond do
        override = Overrides.check(mod, name, arity, v) ->
          {:override, override}

        mod == ctx.module ->
          {:local, local_type(name, args, v, ctx)}

        arity != 0 ->
          {:trusted, true}

        TypeGuard.adopted?(mod) or not external?(mod) ->
          {:runtime, quote(do: TypeGuard.check(unquote(mod), unquote(name), unquote(v)))}

        ctx.depth == 0 ->
          {:trusted, true}

        true ->
          case Spec.check(mod, name, v, %{ctx | depth: ctx.depth - 1, record?: false}) do
            :error -> {:trusted, true}
            {:ok, code} -> {:spec, code}
          end
      end

    if ctx.record? and kind != :local,
      do: Process.put(@references, [{mod, name, arity, kind} | Process.get(@references, [])])

    code
  end

  # A module whose beam is outside the project being compiled: a dependency,
  # Elixir or Erlang/OTP. Its types do not change while the project runs.
  defp external?(mod) do
    case :code.which(mod) do
      :preloaded ->
        true

      path when is_list(path) and path != [] ->
        case project_ebin() do
          nil -> false
          ebin -> not String.starts_with?(List.to_string(path), ebin)
        end

      _not_found_or_in_memory ->
        false
    end
  end

  defp project_ebin do
    if Code.ensure_loaded?(Mix.Project) and Mix.Project.get() do
      Path.join(Mix.Project.app_path(), "ebin")
    end
  rescue
    _umbrella_root -> nil
  end

  # Built-in types that one guard checks.
  @guards %{
    atom: :is_atom,
    module: :is_atom,
    node: :is_atom,
    boolean: :is_boolean,
    binary: :is_binary,
    bitstring: :is_bitstring,
    integer: :is_integer,
    float: :is_float,
    number: :is_number,
    map: :is_map,
    struct: :is_struct,
    list: :is_list,
    maybe_improper_list: :is_list,
    charlist: :is_list,
    keyword: :is_list,
    iolist: :is_list,
    tuple: :is_tuple,
    pid: :is_pid,
    port: :is_port,
    reference: :is_reference,
    fun: :is_function,
    function: :is_function
  }

  # Built-in integer types that a range checks.
  @ranges %{
    non_neg_integer: {0, nil},
    pos_integer: {1, nil},
    neg_integer: {nil, -1},
    arity: {0, 255},
    byte: {0, 255},
    char: {0, 0x10FFFF}
  }

  @doc false
  # Built-in types, shared with `TypeGuard.Spec`. Returns `:unknown` for a
  # name that is not built in.
  @spec builtin(atom(), list(), Macro.t(), map()) :: Macro.t() | :unknown
  def builtin(name, [], v, _ctx) when is_map_key(@guards, name),
    do: quote(do: Kernel.unquote(Map.fetch!(@guards, name))(unquote(v)))

  def builtin(name, [], v, _ctx) when is_map_key(@ranges, name) do
    {low, high} = Map.fetch!(@ranges, name)
    low = if low, do: quote(do: unquote(v) >= unquote(low)), else: true
    high = if high, do: quote(do: unquote(v) <= unquote(high)), else: true
    conjunction([quote(do: is_integer(unquote(v))), low, high])
  end

  def builtin(name, [], _v, _ctx) when name in [:term, :any], do: true
  def builtin(name, [], _v, _ctx) when name in [:none, :no_return], do: false

  def builtin(name, [], v, _ctx) when name in [:nonempty_list, :nonempty_charlist],
    do: quote(do: is_list(unquote(v)) and unquote(v) != [])

  def builtin(:nonempty_binary, [], v, _ctx),
    do: quote(do: is_binary(unquote(v)) and unquote(v) != "")

  def builtin(:mfa, [], v, _ctx),
    do: quote(do: is_tuple(unquote(v)) and tuple_size(unquote(v)) == 3)

  def builtin(:identifier, [], v, _ctx),
    do: quote(do: is_pid(unquote(v)) or is_port(unquote(v)) or is_reference(unquote(v)))

  def builtin(:timeout, [], v, _ctx),
    do: quote(do: unquote(v) === :infinity or (is_integer(unquote(v)) and unquote(v) >= 0))

  def builtin(:iodata, [], v, _ctx), do: quote(do: is_binary(unquote(v)) or is_list(unquote(v)))

  # The empty list type, `[]` in Elixir, is `nil()` in the Erlang abstract format.
  def builtin(nil, [], v, _ctx), do: quote(do: unquote(v) === [])

  def builtin(:list, [elem], v, ctx), do: list(elem, v, ctx, :any)
  def builtin(:nonempty_list, [elem], v, ctx), do: list(elem, v, ctx, :nonempty)
  def builtin(:as_boolean, [type], v, ctx), do: check(type, v, ctx)

  def builtin(:keyword, [type], v, ctx),
    do: list(quote(do: {atom(), unquote(type)}), v, ctx, :any)

  def builtin(name, _args, v, _ctx)
      when name in [:maybe_improper_list, :nonempty_maybe_improper_list],
      do: quote(do: is_list(unquote(v)))

  def builtin(_name, _args, _v, _ctx), do: :unknown

  defp list(elem, v, ctx, emptiness) do
    x = Macro.unique_var(:x, __MODULE__)
    elem_check = check(elem, x, ctx)

    all =
      if elem_check == true,
        do: true,
        else: quote(do: Enum.all?(unquote(v), fn unquote(x) -> unquote(elem_check) end))

    nonempty = if emptiness == :nonempty, do: quote(do: unquote(v) != []), else: true
    conjunction([quote(do: is_list(unquote(v))), nonempty, all])
  end

  @doc false
  # Maps: Elixir compiles `key: t`, `required(k) => v` and a bare `k => v` to the
  # same `map_field_exact`, so each of them requires an entry. A literal key
  # requires that key. A key type requires at least one entry with a key of
  # that type. Only `optional(k) => v` allows no entry. An entry that matches
  # no declared pair fails the check. A struct is a map with a `:__struct__`
  # entry, and it is not enumerable, so the checks read its list of entries.
  @spec map(list(), Macro.t(), map()) :: Macro.t()
  def map(pairs, v, ctx) do
    pairs = Enum.map(pairs, &map_pair/1)

    exact = for {:literal, key, type} <- pairs, do: {key, type}
    exact_keys = for {key, _type} <- exact, do: key

    exact_checks =
      for {key, type} <- exact do
        quote do
          is_map_key(unquote(v), unquote(key)) and
            unquote(check(type, quote(do: :erlang.map_get(unquote(key), unquote(v))), ctx))
        end
      end

    k = Macro.unique_var(:k, __MODULE__)
    val = Macro.unique_var(:val, __MODULE__)

    entry = fn key_type, value_type ->
      conjunction([check(key_type, k, ctx), check(value_type, val, ctx)])
    end

    required_checks =
      for {:required, key_type, value_type} <- pairs do
        case entry.(key_type, value_type) do
          true ->
            quote(do: map_size(unquote(v)) > 0)

          pair ->
            quote(
              do:
                Enum.any?(Map.to_list(unquote(v)), fn {unquote(k), unquote(val)} ->
                  unquote(pair)
                end)
            )
        end
      end

    entry_checks =
      for {kind, key_type, value_type} <- pairs, kind in [:required, :optional] do
        entry.(key_type, value_type)
      end

    rest =
      case entry_checks do
        [] ->
          quote(do: map_size(unquote(v)) == unquote(length(exact_keys)))

        _ ->
          entry = Enum.reduce(entry_checks, &quote(do: unquote(&2) or unquote(&1)))

          entry =
            if exact_keys == [],
              do: entry,
              else: quote(do: unquote(k) in unquote(exact_keys) or unquote(entry))

          if entry == true,
            do: true,
            else:
              quote(
                do:
                  Enum.all?(Map.to_list(unquote(v)), fn {unquote(k), unquote(val)} ->
                    unquote(entry)
                  end)
              )
      end

    conjunction([quote(do: is_map(unquote(v))) | exact_checks] ++ required_checks ++ [rest])
  end

  defp map_pair({{:required, _, [key]}, type}), do: map_pair({key, type})
  defp map_pair({{:optional, _, [key]}, type}), do: {:optional, key, type}
  defp map_pair({key, type}) when is_atom(key) or is_integer(key), do: {:literal, key, type}
  defp map_pair({key, type}), do: {:required, key, type}

  @doc false
  @spec tuple(list(), Macro.t(), map()) :: Macro.t()
  def tuple(elems, v, ctx) do
    elem_checks =
      for {type, index} <- Enum.with_index(elems),
          do: check(type, quote(do: :erlang.element(unquote(index + 1), unquote(v))), ctx)

    conjunction([
      quote(do: is_tuple(unquote(v)) and tuple_size(unquote(v)) == unquote(length(elems)))
      | elem_checks
    ])
  end

  @doc false
  @spec bits(non_neg_integer(), non_neg_integer(), Macro.t()) :: Macro.t()
  def bits(base, 0, v),
    do: quote(do: is_bitstring(unquote(v)) and bit_size(unquote(v)) == unquote(base))

  def bits(base, unit, v) do
    quote do
      is_bitstring(unquote(v)) and bit_size(unquote(v)) >= unquote(base) and
        rem(bit_size(unquote(v)) - unquote(base), unquote(unit)) == 0
    end
  end

  @doc false
  # Joins checks with `and`, dropping the ones that are always true.
  @spec conjunction([Macro.t()]) :: Macro.t()
  def conjunction(checks) do
    case Enum.reject(checks, &(&1 == true)) do
      [] -> true
      [first | rest] -> Enum.reduce(rest, first, &quote(do: unquote(&2) and unquote(&1)))
    end
  end

  defp integer({:-, _, [int]}) when is_integer(int), do: -int
  defp integer(int) when is_integer(int), do: int

  defp expand(mod, ctx), do: expand_alias(mod, ctx.env)

  # Expands an alias as if inside a function, so that a type that mentions a
  # module gives a runtime reference to it, not a compile-time dependency.
  defp expand_alias(mod, env),
    do: Macro.expand_literals(mod, %{env | function: {:__type_guard__, 2}})
end
