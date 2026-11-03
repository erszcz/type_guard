if Code.ensure_loaded?(Ecto.Changeset) do
  defmodule TypeGuard.Ecto do
    @moduledoc """
    Changeset validations from the `t()` of a schema that uses `TypeGuard`.

    Ecto casts a field by its Ecto type, which can be wider than its type in
    `t()`. A `:map` field typed as a struct, a field that `t()` types as
    non-nil but that the changeset does not require, and a value that a
    custom changeset function sets directly are examples. These validations
    check the changeset against `t()`:

        def changeset(struct \\\\ %__MODULE__{}, attrs) do
          struct
          |> cast(attrs, [:name, :settings])
          |> cast_embed(:address)
          |> TypeGuard.Ecto.validate()
        end

    Both validations go into the nested changesets of embeds and
    associations, except the ones that replace or delete an embed. A
    polymorphic embed has no nested changeset, so its errors are reported on
    its field. A field
    that already has an error keeps it, and gets no second one. See the
    [Ecto guide](ecto.md).
    """

    import Ecto.Changeset, only: [add_error: 4, get_field: 2]

    @doc """
    Runs `validate_non_nil/1` and then `validate_type/1`.
    """
    @spec validate(Ecto.Changeset.t(data)) :: Ecto.Changeset.t(data) when data: var
    def validate(changeset), do: changeset |> validate_non_nil() |> validate_type()

    @doc """
    Adds `{"can't be blank", validation: :required}` to each field that is
    `nil` and whose type in `t()` rejects `nil`.

    The error is the one `Ecto.Changeset.validate_required/3` adds, but the
    check accepts an empty string.
    """
    @spec validate_non_nil(Ecto.Changeset.t(data)) :: Ecto.Changeset.t(data) when data: var
    def validate_non_nil(changeset) do
      each_level(changeset, fn changeset, module ->
        Enum.reduce(TypeGuard.required_fields(module), changeset, fn field, changeset ->
          if is_nil(get_field(changeset, field)) and not has_error?(changeset, field),
            do: add_error(changeset, field, "can't be blank", validation: :required),
            else: changeset
        end)
      end)
    end

    @doc """
    Adds `{"is invalid", validation: :type}` to each field whose value does
    not conform to its type in `t()`.

    A field with a nested changeset is validated inside that changeset
    instead. Run `validate_non_nil/1` first to get "can't be blank" for a
    `nil` in a required field: this validation reports it as invalid.
    """
    @spec validate_type(Ecto.Changeset.t(data)) :: Ecto.Changeset.t(data) when data: var
    def validate_type(changeset) do
      each_level(changeset, fn changeset, module ->
        nested = for {field, value} <- changeset.changes, nested?(value), do: field

        Enum.reduce(TypeGuard.fields(module) -- nested, changeset, fn field, changeset ->
          if has_error?(changeset, field) or
               module.__type_guard_field__(field, get_field(changeset, field)),
             do: changeset,
             else: add_error(changeset, field, "is invalid", validation: :type)
        end)
      end)
    end

    # Applies `fun` to the changeset and to each nested changeset of a schema
    # that uses TypeGuard, and keeps `valid?` in step.
    defp each_level(%Ecto.Changeset{data: %module{}} = changeset, fun) do
      changeset =
        if TypeGuard.adopted?(module), do: fun.(changeset, module), else: changeset

      {changes, nested_valid?} =
        Enum.map_reduce(changeset.changes, true, fn
          {field, %Ecto.Changeset{} = nested}, valid? ->
            nested = applied(nested, fun)
            {{field, nested}, valid? and nested.valid?}

          {field, [%Ecto.Changeset{} | _] = nested}, valid? ->
            nested = Enum.map(nested, &applied(&1, fun))
            {{field, nested}, valid? and Enum.all?(nested, & &1.valid?)}

          change, valid? ->
            {change, valid?}
        end)

      %{changeset | changes: Map.new(changes), valid?: changeset.valid? and nested_valid?}
    end

    defp each_level(changeset, _fun), do: changeset

    # A nested changeset that replaces or deletes an embed is not applied.
    defp applied(%Ecto.Changeset{action: action} = changeset, _fun)
         when action in [:replace, :delete],
         do: changeset

    defp applied(changeset, fun), do: each_level(changeset, fun)

    defp nested?(%Ecto.Changeset{}), do: true
    defp nested?([%Ecto.Changeset{} | _]), do: true
    defp nested?(_value), do: false

    defp has_error?(changeset, field), do: Keyword.has_key?(changeset.errors, field)
  end
end
