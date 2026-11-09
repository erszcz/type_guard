defmodule TypeGuard.Fixtures.Ids do
  @moduledoc false
  use TypeGuard

  @type id() :: String.t()
  @type count() :: non_neg_integer()
  @type maybe_id() :: id() | nil
end

defmodule TypeGuard.Fixtures.Shapes do
  @moduledoc false
  use TypeGuard

  alias TypeGuard.Fixtures.Ids

  @type color() :: :red | :green | :blue
  @type level() :: 1..10
  @type offset() :: -5..5
  @type pair() :: {atom(), integer()}
  @type triple() :: {integer(), integer(), integer()}
  @type tags() :: [String.t()]
  @type nonempty_tags() :: [String.t(), ...]
  @type options() :: [verbose: boolean(), depth: non_neg_integer()]
  @type counts() :: %{optional(String.t()) => non_neg_integer()}
  @type required_key() :: %{required(:id) => String.t(), optional(:note) => String.t()}
  @type required_integer_key() :: %{required(1) => String.t()}
  @type required_key_type() :: %{required(String.t()) => integer()}
  @type bare_key_type() :: %{String.t() => integer()}
  @type required_any_entry() :: %{required(atom()) => term()}
  @type changeset_types() :: Ecto.Changeset.types()
  @type point() :: %{x: number(), y: number()}
  @type empty() :: %{}
  @type digest() :: <<_::256>>
  @type bytes() :: <<_::_*8>>
  @type tree() :: %{value: integer(), children: [tree()]}
  @type id_list() :: [Ids.id()]
  @type price() :: Decimal.t()
  @type uuid() :: UUIDv7.t()
  @type when_() :: DateTime.t()
  @type calendar_unit() :: System.time_unit()
  @type parameterized(a) :: [a]
  @type timeout_() :: timeout()
  @type mfa_() :: mfa()
  @type keyword_() :: keyword(integer())
  @type list_() :: list(atom())
  @type flag() :: as_boolean(boolean())
  @type char_() :: char()
  @type name() :: nonempty_binary()
  @type handle() :: identifier()
  @type data() :: iodata()
  @type nothing() :: none()
  @type maybe_atom() :: atom() | nil
  @type flag_or_atom() :: boolean() | :unknown | atom()
  @type maybe_count() :: integer() | 0 | nil
  @type maybe_unit() :: System.time_unit() | nil
  @type twice_nil() :: non_neg_integer() | nil | nil
  @type callback() :: (integer(), atom() -> boolean())
  @type thunk() :: (-> atom())
  @type any_arity() :: (... -> atom())
  @type marked() :: TypeGuard.unchecked()
  @type uses_private() :: secret()
  @typep secret() :: :hidden | :shown
end

defmodule TypeGuard.Fixtures.Line do
  @moduledoc false
  use TypeGuard, blank: true

  defstruct [:sku, :quantity, :note]

  @type t() :: %__MODULE__{
          sku: TypeGuard.Fixtures.Ids.id(),
          quantity: pos_integer(),
          note: String.t() | nil
        }
end

defmodule TypeGuard.Fixtures.Order do
  @moduledoc false
  use TypeGuard

  alias TypeGuard.Fixtures.Line

  defstruct [:id, :status, lines: []]

  @type status() :: :open | :paid
  @type t() :: %__MODULE__{
          id: TypeGuard.Fixtures.Ids.id(),
          status: status(),
          lines: [Line.t()]
        }
end

defmodule TypeGuard.Fixtures.OnlyId do
  @moduledoc false
  use TypeGuard, only: [:id]

  defstruct [:id, :name]

  @type id() :: code()
  @type name() :: String.t()
  @type t() :: %__MODULE__{id: id(), name: name()}
  @typep code() :: <<_::64>>
end

defmodule TypeGuard.Fixtures.ExceptT do
  @moduledoc false
  use TypeGuard, except: [:t], blank: true

  defstruct [:id]

  @type id() :: String.t()
  @type t() :: %__MODULE__{id: id()}
end

defmodule TypeGuard.Fixtures.UsesOnlyId do
  @moduledoc false
  use TypeGuard

  @type ids() :: [TypeGuard.Fixtures.OnlyId.id()]
  @type names() :: [TypeGuard.Fixtures.OnlyId.name()]
end

defmodule TypeGuard.Fixtures.MergedUses do
  @moduledoc false
  use TypeGuard, only: [:id]
  use TypeGuard, only: [:status, :missing], allow_missing: true

  @type id() :: String.t()
  @type status() :: :on | :off
  @type note() :: String.t()
end

defmodule TypeGuard.Fixtures.MergedWithAll do
  @moduledoc false
  use TypeGuard, only: [:id]
  use TypeGuard

  @type id() :: String.t()
  @type note() :: String.t()
end

defmodule TypeGuard.Fixtures.TypeMacro do
  @moduledoc false
  # Defines types the way a library macro does: inside a quote, a name
  # without parentheses carries the context module of the macro.
  defmacro __using__(_opts) do
    quote do
      @type kind :: :one | :two
      @type t :: %{kind: kind}
    end
  end
end

defmodule TypeGuard.Fixtures.MacroTypes do
  @moduledoc false
  use TypeGuard
  use TypeGuard.Fixtures.TypeMacro
end

defmodule TypeGuard.Fixtures.SelectsNothing do
  @moduledoc false
  use TypeGuard, only: [:id], allow_missing: true

  @type name() :: String.t()
end

defmodule TypeGuard.Fixtures.Plain do
  @moduledoc false
  # Does not use TypeGuard: its types are trusted.
  @type t() :: integer()
end

defmodule TypeGuard.Fixtures.UsesPlain do
  @moduledoc false
  use TypeGuard

  @type t() :: TypeGuard.Fixtures.Plain.t()
end

defmodule TypeGuard.Fixtures.Strict do
  @moduledoc false
  # Its checks raise where they meet a type that is not checked.
  use TypeGuard, unchecked: :raise

  alias TypeGuard.Fixtures.{Ids, OnlyId, Plain}

  @type id() :: OnlyId.id()
  @type name() :: OnlyId.name()
  @type plain() :: Plain.t()
  @type missing() :: Ids.no_such_type()
  @type tree() :: %{value: integer(), children: [tree()]}
  @type queue() :: :queue.queue()
end

defmodule TypeGuard.Fixtures.StrictInOneUse do
  @moduledoc false
  use TypeGuard
  use TypeGuard, only: [:t], unchecked: :raise

  @type t() :: TypeGuard.Fixtures.Plain.t()
end
