defmodule PuntTest do
  use ExUnit.Case
  defmodule A, do: defstruct([:a])
  doctest Punt

  describe "parsing" do
    test "get" do
      input = %{"name" => "abc"}
      assert {:ok, "abc"} = Punt.get("name", Punt.string()) |> Punt.parse(input)
    end

    test "get_or_missing" do
      input = %{"name" => "abc"}
      assert {:ok, -1} = Punt.get_or_missing("bogus", -1, Punt.string()) |> Punt.parse(input)
    end

    test "string" do
      input = "abc"
      assert {:ok, input} == Punt.string() |> Punt.parse(input)
    end

    test "float" do
      input = 1.3
      assert {:ok, input} == Punt.float() |> Punt.parse(input)
    end

    test "integer" do
      input = 123
      assert {:ok, input} == Punt.integer() |> Punt.parse(input)
    end

    test "boolean" do
      input = true
      assert {:ok, input} == Punt.boolean() |> Punt.parse(input)
    end

    test "number" do
      input = 123
      assert {:ok, input} == Punt.number() |> Punt.parse(input)

      input = 1.3
      assert {:ok, input} == Punt.number() |> Punt.parse(input)
    end

    test "list" do
      input = ["abc"]
      assert {:ok, input} == Punt.list_of(Punt.string()) |> Punt.parse(input)
    end

    test "not_a_list" do
      input = 123
      assert {:error, :not_a_list} == Punt.list_of(Punt.string()) |> Punt.parse(input)
    end

    test "not a list of strings" do
      input = [123]

      assert {:error, %{details: :not_a_string, failed_element: 123}} ==
               Punt.list_of(Punt.string()) |> Punt.parse(input)
    end

    test "singleton" do
      input = ["abc"]
      assert {:ok, "abc"} == Punt.singleton_of(Punt.string()) |> Punt.parse(input)
    end

    test "not_a_singleton" do
      input = 123
      assert {:error, :not_a_singleton} == Punt.singleton_of(Punt.string()) |> Punt.parse(input)
    end

    test "not a not_a_singleton of strings" do
      input = [123]

      assert {:error, %{details: :not_a_string, failed_element: 123}} ==
               Punt.singleton_of(Punt.string()) |> Punt.parse(input)
    end

    test "index" do
      input = ["abc", "def", "ghi"]
      assert {:ok, "def"} == Punt.index(1, Punt.string()) |> Punt.parse(input)
    end

    test "not_a_index" do
      input = 123
      assert {:error, :not_enumerable} == Punt.index(1, Punt.string()) |> Punt.parse(input)
    end

    test "not a string at index" do
      input = [123]

      assert {:error, :not_a_string} ==
               Punt.index(2, Punt.string()) |> Punt.parse(input)
    end

    test "map string to int" do
      input = "123"
      assert 123 == Punt.map(Punt.string(), &String.to_integer/1) |> Punt.parse(input)
    end

    test "deep map" do
      input = %{a: %{b: 3}}
      assert {:ok, 3} == Punt.get_in([:a, :b], Punt.integer()) |> Punt.parse(input)
    end

    test "map encoders" do
      map_encoders = fn {:ok, results} ->
        {:ok, List.to_tuple(results)}
      end

      assert {:ok, {3, 4}} =
               Punt.map(map_encoders, [
                 Punt.index(0, Punt.integer()),
                 Punt.index(1, Punt.integer())
               ])
               |> Punt.parse([3, 4])
    end

    test "and then" do
      map_encoders = fn {:ok, results} ->
        {:ok, List.to_tuple(results)}
      end

      a = %{"version" => 3, "data" => [1, 2]}
      b = %{"version" => 4, "data" => %{"a" => 3, "b" => 4}}

      decoder =
        Punt.get("version", Punt.integer())
        |> Punt.and_then(fn res ->
          data_decoder =
            case res do
              3 ->
                Punt.pair_of(Punt.integer(), Punt.integer())

              4 ->
                Punt.map(map_encoders, [
                  Punt.get("a", Punt.integer()),
                  Punt.get("b", Punt.integer())
                ])
            end

          Punt.get("data", data_decoder)
        end)

      assert {:ok, {1, 2}} = decoder |> Punt.parse(a)
      assert {:ok, {3, 4}} = decoder |> Punt.parse(b)
    end

    test "fail" do
      assert {:error, "reason"} = Punt.fail("reason") |> Punt.parse("Sf")
    end

    test "one_of" do
      decoder = Punt.one_of([Punt.null(), Punt.integer()])

      assert {:ok, 10} = decoder.parse.(10)

      assert {:ok, nil} = decoder.parse.(nil)
    end
  end

  describe "generating" do
    test "list_of" do
      punt = Punt.list_of(Punt.string())
      output = punt |> Punt.gen() |> Enum.take(10)

      for input <- output do
        {:ok, _} = punt |> Punt.parse(input)
      end
    end

    test "string" do
      output = Punt.string() |> Punt.gen() |> Enum.take(10)

      for input <- output do
        {:ok, _} = Punt.string() |> Punt.parse(input)
      end
    end

    test "integer" do
      output = Punt.integer() |> Punt.gen() |> Enum.take(10)

      for input <- output do
        {:ok, _} = Punt.integer() |> Punt.parse(input)
      end
    end

    test "succeed" do
      output = Punt.succeed("a") |> Punt.gen() |> Enum.take(10)

      for input <- output do
        {:ok, _} = Punt.succeed("a") |> Punt.parse(input)
      end
    end

    test "one_of" do
      punt = Punt.one_of([Punt.integer(), Punt.string()])

      output = punt |> Punt.gen() |> Enum.take(10)

      for input <- output do
        {:ok, _} = punt |> Punt.parse(input)
      end
    end
  end
end
