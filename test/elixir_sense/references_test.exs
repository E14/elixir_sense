defmodule ElixirSense.Providers.ReferencesTest do
  use ExUnit.Case

  # doctest References

  test "find references with cursor over a function call" do
    buffer = """
    defmodule Caller do
      def func() do
        ElixirSense.Providers.ReferencesTest.Modules.Callee1.func()
        #                                                     ^
      end
    end
    """

    references = ElixirSense.references(buffer, 3, 59)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 36, column: 60}, end: %{line: 36, column: 64}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 16}, end: %{line: 65, column: 20}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 63}, end: %{line: 65, column: 67}}
             }
           ]
  end

  test "find references with cursor over a function definition" do
    buffer = """
    defmodule ElixirSense.Providers.ReferencesTest.Modules.Callee1 do
      def func() do
        #    ^
        IO.puts ""
      end
      def func(par1) do
        #    ^
        IO.puts par1
      end
    end
    """

    references = ElixirSense.references(buffer, 2, 10)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 36, column: 60}, end: %{line: 36, column: 64}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 16}, end: %{line: 65, column: 20}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 63}, end: %{line: 65, column: 67}}
             }
           ]

    references = ElixirSense.references(buffer, 6, 10)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 42, column: 60}, end: %{line: 42, column: 64}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 79}, end: %{line: 65, column: 83}}
             }
           ]
  end

  test "find references with cursor over a function with arity 1" do
    buffer = """
    defmodule Caller do
      def func() do
        ElixirSense.Providers.ReferencesTest.Modules.Callee1.func("test")
        #                                                     ^
      end
    end
    """

    references = ElixirSense.references(buffer, 3, 59)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 42, column: 60}, end: %{line: 42, column: 64}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 79}, end: %{line: 65, column: 83}}
             }
           ]
  end

  test "find references with cursor over a function with arity 1 called via pipe operator" do
    buffer = """
    defmodule Caller do
      def func() do
        "test"
        |> ElixirSense.Providers.ReferencesTest.Modules.Callee4.func_arg()
        #                                                        ^
      end
    end
    """

    references = ElixirSense.references(buffer, 4, 62)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 49, column: 63}, end: %{line: 49, column: 71}}
             }
           ]
  end

  test "find references with cursor over a function with arity 1 captured" do
    buffer = """
    defmodule Caller do
      def func() do
        Task.start(&ElixirSense.Providers.ReferencesTest.Modules.Callee4.func_arg/1)
        #                                                                  ^
      end
    end
    """

    references = ElixirSense.references(buffer, 3, 72)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 49, column: 63}, end: %{line: 49, column: 71}}
             }
           ]
  end

  test "find references with cursor over a function when caller uses pipe operator" do
    buffer = """
    defmodule Caller do
      def func() do
        ElixirSense.Providers.ReferencesTest.Modules.Callee4.func_arg("test")
        #                                                     ^
      end
    end
    """

    references = ElixirSense.references(buffer, 3, 59)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 49, column: 63}, end: %{line: 49, column: 71}}
             }
           ]
  end

  test "find references with cursor over a function when caller uses capture operator" do
    buffer = """
    defmodule Caller do
      def func() do
        ElixirSense.Providers.ReferencesTest.Modules.Callee4.func_no_arg()
        #                                                     ^
      end
    end
    """

    references = ElixirSense.references(buffer, 3, 59)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 55, column: 72}, end: %{line: 55, column: 83}}
             }
           ]
  end

  test "find references with cursor over a function call from an aliased module" do
    buffer = """
    defmodule Caller do
      def func() do
        alias ElixirSense.Providers.ReferencesTest.Modules.Callee1, as: C
        C.func()
        #  ^
      end
    end
    """

    references = ElixirSense.references(buffer, 4, 8)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 36, column: 60}, end: %{line: 36, column: 64}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 16}, end: %{line: 65, column: 20}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 63}, end: %{line: 65, column: 67}}
             }
           ]
  end

  test "find imported references" do
    buffer = """
    defmodule Caller do
      def func() do
        ElixirSense.Providers.ReferencesTest.Modules.Callee3.func()
        #                                                     ^
      end
    end
    """

    reference = ElixirSense.references(buffer, 3, 59) |> Enum.at(0)

    assert reference == %{
             uri: "test/support/modules_with_references.ex",
             range: %{start: %{line: 65, column: 47}, end: %{line: 65, column: 51}}
           }
  end

  test "find references from remote calls with the function in the next line" do
    buffer = """
    defmodule Caller do
      def func() do
        ElixirSense.Providers.ReferencesTest.Modules.Callee3.func()
        #                                                     ^
      end
    end
    """

    reference = ElixirSense.references(buffer, 3, 59) |> Enum.at(1)

    assert reference == %{
             uri: "test/support/modules_with_references.ex",
             range: %{start: %{line: 69, column: 15}, end: %{line: 69, column: 19}}
           }
  end

  test "find references of variables" do
    buffer = """
    defmodule MyModule do
      def func do
        var1 = 1
        var2 = 2
        var1 = 3
        IO.puts(var1 + var2)
      end
      def func4(ppp) do

      end
    end
    """

    references = ElixirSense.references(buffer, 6, 13)

    assert references == [
             %{uri: nil, range: %{start: %{line: 3, column: 5}, end: %{line: 3, column: 9}}},
             %{uri: nil, range: %{start: %{line: 5, column: 5}, end: %{line: 5, column: 9}}},
             %{uri: nil, range: %{start: %{line: 6, column: 13}, end: %{line: 6, column: 17}}}
           ]
  end

  test "find references with cursor over a module" do
    buffer = """
    defmodule Caller do
      def func() do
        ElixirSense.Providers.ReferencesTest.Modules.Callee1.func()
        #                                               ^
      end
    end
    """

    references = ElixirSense.references(buffer, 3, 53)

    assert references == [
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 36, column: 60}, end: %{line: 36, column: 64}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 42, column: 60}, end: %{line: 42, column: 64}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 16}, end: %{line: 65, column: 20}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 63}, end: %{line: 65, column: 67}}
             },
             %{
               uri: "test/support/modules_with_references.ex",
               range: %{start: %{line: 65, column: 79}, end: %{line: 65, column: 83}}
             }
           ]
  end
end
