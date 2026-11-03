defmodule TypeGuard.ReloadTest do
  # Redefines modules, so it does not run concurrently with other tests.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  defp define(source) do
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_string(source)
  after
    Code.put_compiler_option(:ignore_module_conflict, false)
  end

  test "a reload of the module that defines a type updates the checks that use it" do
    define("""
    defmodule TypeGuard.ReloadTest.Code do
      use TypeGuard
      @type t() :: <<_::32>>
    end

    defmodule TypeGuard.ReloadTest.Item do
      use TypeGuard
      defstruct [:code]
      @type t() :: %__MODULE__{code: TypeGuard.ReloadTest.Code.t()}
    end
    """)

    item = struct(TypeGuard.ReloadTest.Item, code: "abcd")
    assert TypeGuard.valid?(item)
    refute TypeGuard.valid?(%{item | code: "abcdef"})

    # Only the type changes, so the code of `Item` and its md5 stay.
    define("""
    defmodule TypeGuard.ReloadTest.Code do
      use TypeGuard
      @type t() :: <<_::48>>
    end
    """)

    refute TypeGuard.valid?(item)
    assert TypeGuard.valid?(%{item | code: "abcdef"})
  end
end
