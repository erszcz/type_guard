defmodule TypeGuard do
  @moduledoc """
  Checks values at runtime against the plain typespecs of a module.

  `use TypeGuard` in a module makes the module generate a check for each of
  its public types without parameters. The types stay ordinary `@type`
  definitions, so Dialyzer and other static tools read them as before.

      defmodule Shop.Order do
        use TypeGuard

        defstruct [:id, :lines, :status]

        @type status() :: :open | :paid | :shipped
        @type t() :: %__MODULE__{
                id: String.t(),
                lines: [Shop.Line.t()],
                status: status()
              }
      end

      TypeGuard.check(Shop.Order, :status, :paid)
      #=> true

      TypeGuard.invalid_fields(%Shop.Order{id: "o-1", lines: [], status: :lost})
      #=> [:status]

  The [conventions guide](conventions.md) describes what a module generates
  and which types the checks cover. The [remote types guide](remote_types.md)
  describes how a type of another module is checked.

  ## Options

    * `:only` - the names of the public types to check, such as
      `only: [:id]`. The other types are not checked: `check/3` returns `true`
      for them, and the coverage report counts their uses as trusted. A local
      type that a checked type uses is still expanded into its check.
    * `:except` - the names of the public types not to check. Give `:only`
      or `:except`, not both. A name that is not a public type without
      parameters raises `ArgumentError` at compile time.
    * `:allow_missing` - when `true`, a name in `:only` or `:except` that
      the module does not define is ignored instead. For a macro that adds
      `use TypeGuard` to modules that may lack some of the types. Defaults to
      `false`.
    * `:blank` - when `true` and `t()` is a struct type, also defines
      `@type blank()`: the same struct type with `nil` allowed in each field.
      A struct built with `%__MODULE__{}` before its fields are set has this
      type. Defaults to `false`.
    * `:unchecked` - what a check does with a part of a type that it cannot
      check. `:trust` (the default) lets any value pass that part. `:raise`
      makes it an error: a part that is known at compile time stops the
      compilation, and a type of a project module that the module does not
      check raises `TypeGuard.UncheckedError` when a check calls it. The
      typespecs of other applications are still trusted where they cannot be
      checked. A module with several uses raises when any of them gives
      `:raise`. See [Unchecked types](remote_types.md#unchecked-types).

  A module whose uses select no type generates no checks, and
  `adopted?/1` returns `false` for it.

  A module can `use TypeGuard` more than once, for example when several
  macros that it uses add it. The module then checks each type that any of
  the uses selects, and `:blank` applies when any of them gives it.
  """

  @typedoc "The name of a type without parameters, such as `:t` for `t()`."
  @type type_name() :: atom()

  @typedoc """
  A value that a check does not check: `term()` for static tools.

  A type can name it where a precise type is not known, for example in
  generated code. A module that uses TypeGuard with `unchecked: :raise` fails
  to compile when one of its checked types uses it.
  """
  @type unchecked() :: term()

  @options [:only, :except, :allow_missing, :blank, :unchecked]

  @doc false
  defmacro __using__(opts) do
    module = __CALLER__.module
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    unless Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in @options)) do
      raise ArgumentError,
            "use TypeGuard in #{inspect(module)}: the options are #{inspect(@options)}, got: #{inspect(opts)}"
    end

    unless Keyword.get(opts, :unchecked, :trust) in [:trust, :raise] do
      raise ArgumentError,
            "use TypeGuard in #{inspect(module)}: :unchecked is :trust or :raise, got: " <>
              inspect(Keyword.get(opts, :unchecked))
    end

    first? = not Module.has_attribute?(module, :type_guard_uses)

    if first?, do: Module.register_attribute(module, :type_guard_uses, accumulate: true)
    Module.put_attribute(module, :type_guard_uses, opts)

    if first? do
      quote do
        @before_compile TypeGuard.Compiler
      end
    end
  end

  @doc """
  Returns `true` if `value` conforms to `module.type()`.

  A module that does not `use TypeGuard`, a type with parameters and a type
  that the module does not define are not checked: the function returns
  `true` for them. `checked_types/1` lists the types that a module checks.
  """
  @spec check(module(), type_name(), term()) :: boolean()
  def check(module, type, value) when is_atom(module) and is_atom(type) do
    if adopted?(module), do: module.__type_guard__(type, value), else: true
  end

  @doc false
  # The check of a type of another module in a module that uses TypeGuard with
  # `unchecked: :raise`.
  @spec __check_strict__(module(), type_name(), term(), module()) :: boolean()
  def __check_strict__(module, type, value, referrer) do
    cond do
      not adopted?(module) ->
        raise TypeGuard.UncheckedError,
              unchecked_message(
                referrer,
                module,
                type,
                "#{inspect(module)} does not use TypeGuard"
              )

      type not in module.__type_guard__(:types) ->
        raise TypeGuard.UncheckedError,
              unchecked_message(referrer, module, type, "#{inspect(module)} does not check it")

      true ->
        module.__type_guard__(type, value)
    end
  end

  defp unchecked_message(referrer, module, type, reason) do
    "#{inspect(referrer)} uses TypeGuard with unchecked: :raise and checks a value " <>
      "against #{inspect(module)}.#{type}(), but #{reason}"
  end

  @doc "Returns `true` if `module` is loaded and uses `TypeGuard`."
  @spec adopted?(module()) :: boolean()
  def adopted?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__type_guard__, 2)
  end

  @doc "Returns the types of `module` that `check/3` checks, in the order of their definitions."
  @spec checked_types(module()) :: [type_name()]
  def checked_types(module) when is_atom(module) do
    if adopted?(module), do: module.__type_guard__(:types), else: []
  end

  @doc """
  Returns the fields of the struct type `module.t()`.

  Returns `[]` when `t()` is not a struct type or `module` does not use
  `TypeGuard`.
  """
  @spec fields(module()) :: [atom()]
  def fields(module) when is_atom(module) do
    if adopted?(module), do: module.__type_guard__(:fields), else: []
  end

  @doc """
  Returns `true` if `value` conforms to the type of `field` in `module.t()`.

  Returns `true` for a field that `t()` does not list.
  """
  @spec check_field(module(), atom(), term()) :: boolean()
  def check_field(module, field, value) when is_atom(module) and is_atom(field) do
    if adopted?(module), do: module.__type_guard_field__(field, value), else: true
  end

  @doc "Returns `true` if `struct` conforms to the `t()` of its module."
  @spec valid?(struct()) :: boolean()
  def valid?(%module{} = struct), do: check(module, :t, struct)

  @doc """
  Returns the fields of `struct` whose values do not conform to their types
  in the `t()` of its module, in the order of `t()`.
  """
  @spec invalid_fields(struct()) :: [atom()]
  def invalid_fields(%module{} = struct) do
    for field <- fields(module),
        not module.__type_guard_field__(field, Map.get(struct, field)),
        do: field
  end

  @doc """
  Returns the fields of `module.t()` whose types do not admit `nil`.

  A field is required exactly when the check of its type rejects `nil`. A
  field whose type is not checked is not required.
  """
  @spec required_fields(module()) :: [atom()]
  def required_fields(module) when is_atom(module) do
    for field <- fields(module), not module.__type_guard_field__(field, nil), do: field
  end

  @doc """
  Returns the required fields of `struct` that hold `nil`.

  See `required_fields/1`.
  """
  @spec nil_fields(struct()) :: [atom()]
  def nil_fields(%module{} = struct) do
    for field <- fields(module),
        is_nil(Map.get(struct, field)),
        not module.__type_guard_field__(field, nil),
        do: field
  end
end
