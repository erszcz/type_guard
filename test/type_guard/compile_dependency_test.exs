defmodule TypeGuard.CompileDependencyTest do
  # Sets a compiler option, so it does not run concurrently with other tests.
  use ExUnit.Case, async: false

  defmodule Tracer do
    @moduledoc false
    # Records the references to TypeGuard.Fixtures.Ids that are made outside a
    # function. Mix counts those as compile-time dependencies.
    def trace({kind, _meta, TypeGuard.Fixtures.Ids}, %{function: nil})
        when kind in [:alias_reference, :remote_function, :imported_function, :struct_expansion] do
      send(Process.get(:type_guard_test_pid), {:compile_time_reference, kind})
      :ok
    end

    def trace(_event, _env), do: :ok
  end

  test "a type that names another module adds no compile-time dependency on it" do
    Process.put(:type_guard_test_pid, self())
    Code.put_compiler_option(:tracers, [Tracer])

    try do
      Code.compile_string("""
      defmodule TypeGuard.CompileDependencyTest.User do
        use TypeGuard
        defstruct [:id]
        @type ids() :: [TypeGuard.Fixtures.Ids.id()]
        @type t() :: %__MODULE__{id: TypeGuard.Fixtures.Ids.id()}
      end
      """)
    after
      Code.put_compiler_option(:tracers, [])
    end

    refute_received {:compile_time_reference, _kind}
    assert TypeGuard.check(TypeGuard.CompileDependencyTest.User, :ids, ["a"])
    refute TypeGuard.check(TypeGuard.CompileDependencyTest.User, :ids, [1])
  end
end
