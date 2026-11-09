defmodule TypeGuard.Overrides do
  @moduledoc false
  # Remote types whose check is written here instead of being built from
  # their typespec. Each one is a struct or binary type whose full typespec
  # would make a large check for no gain, or an opaque type.

  @overrides %{
    # Elixir
    {String, :t} => :binary,
    {Date, :t} => {:struct, Date},
    {Time, :t} => {:struct, Time},
    {DateTime, :t} => {:struct, DateTime},
    {NaiveDateTime, :t} => {:struct, NaiveDateTime},
    {Duration, :t} => {:struct, Duration},
    {MapSet, :t} => {:struct, MapSet},
    {Range, :t} => {:struct, Range},
    {Regex, :t} => {:struct, Regex},
    {URI, :t} => {:struct, URI},
    {Version, :t} => {:struct, Version},

    # Dependencies
    {Decimal, :t} => {:struct, Decimal},
    {Plug.Upload, :t} => {:struct, Plug.Upload}
  }

  @doc false
  # Returns the check of `v` against `mod.name(...)`, or `nil` when the type
  # has no override. The parameters of a type, such as the element type of
  # `MapSet.t(t)`, are not checked.
  @spec check(module(), atom(), arity(), Macro.t()) :: Macro.t() | nil
  def check(mod, name, _arity, v) do
    case Map.get(@overrides, {mod, name}) do
      nil -> nil
      :binary -> quote(do: is_binary(unquote(v)))
      {:struct, struct} -> quote(do: is_struct(unquote(v), unquote(struct)))
    end
  end

  @doc false
  @spec all() :: %{optional({module(), atom()}) => term()}
  def all, do: @overrides
end
