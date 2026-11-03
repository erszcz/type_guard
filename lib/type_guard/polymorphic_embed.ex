defmodule TypeGuard.PolymorphicEmbed do
  @moduledoc """
  Checks the fields of [PolymorphicEmbed](https://hex.pm/packages/polymorphic_embed)
  against their declared embed modules.

  `PolymorphicEmbed.t()` is `any()`, so a field typed with it would not be
  checked. Each `polymorphic_embeds_one/2` and `polymorphic_embeds_many/2`
  field declares its embed modules, though. When `PolymorphicEmbed` is
  available, `use TypeGuard` replaces `PolymorphicEmbed.t()` in the type of
  such a field with the union of the `t()` types of its declared modules:

      polymorphic_embeds_many :attachments,
        types: [image: Image, video: Video],
        type_field_name: :kind,
        on_type_not_found: :raise,
        on_replace: :delete

      @type t() :: %__MODULE__{attachments: [PolymorphicEmbed.t()]}

  checks each attachment as `Image.t() | Video.t()`. The rest of the field
  type stays, such as `| nil` or the list.

  The integration needs nothing besides the dependency. See the
  [Ecto guide](ecto.md).
  """

  @available Code.ensure_loaded?(PolymorphicEmbed)

  @doc "Returns `true` when the integration is active."
  @spec available?() :: boolean()
  # The value is fixed when TypeGuard compiles, so one build returns only one of the two.
  @dialyzer {:no_extra_return, available?: 0}
  def available?, do: @available

  @doc false
  # Returns the type of `field` in `t()` of `module`, with the declared embed
  # modules in place of `PolymorphicEmbed.t()`. Runs while `module` compiles.
  @spec adjust(module(), atom(), Macro.t()) :: Macro.t()
  if @available do
    def adjust(module, field, type) do
      case declared_modules(module, field) do
        [] ->
          type

        modules ->
          union =
            modules
            |> Enum.map(&quote(do: unquote(&1).t()))
            |> Enum.reduce(&quote(do: unquote(&2) | unquote(&1)))

          Macro.prewalk(type, fn
            {{:., _, [{:__aliases__, _, [:PolymorphicEmbed]}, :t]}, _, []} -> union
            {{:., _, [PolymorphicEmbed, :t]}, _, []} -> union
            other -> other
          end)
      end
    end

    defp declared_modules(module, field) do
      for {^field, type} <- Module.get_attribute(module, :ecto_changeset_fields) || [],
          {:parameterized, {PolymorphicEmbed, %{types_metadata: metadata}}} <- [
            unwrap_array(type)
          ],
          %{module: embed} <- metadata,
          do: embed
    end

    defp unwrap_array({:array, type}), do: type
    defp unwrap_array(type), do: type
  else
    def adjust(_module, _field, type), do: type
  end
end
