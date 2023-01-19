defmodule Punt do
  @moduledoc """
  Documentation for `Punt`.
  """
  defstruct [:parse, :gen]

  def parse(punt, input) do
    punt.parse.(input)
  end

  def to_parser(fun) do
    build(parse: fun)
  end

  def gen(punt) do
    punt.gen
  end

  def build(opts) do
    struct!(__MODULE__, opts)
  end

  @doc """
  Parse into a map or struct

  ## Example
      iex> Punt.new([a: Punt.get(:b, Punt.string)], %{b: "foo"})
      {:ok, %{a: "foo"}}
  """
  def new(map, input, module \\ nil) do
    result =
      Enum.reduce(map, {:ok, []}, fn
        {key, value}, {:ok, acc} ->
          case value.parse.(input) do
            {:ok, res} -> {:ok, [{key, res} | acc]}
            {:error, error} -> {:error, error}
          end

        _, {:error, error} ->
          {:error, error}
      end)

    case result do
      {:ok, result} ->
        if module do
          {:ok, struct!(module, result)}
        else
          {:ok, Map.new(result)}
        end

      error ->
        error
    end
  end

  @doc """
  Parse into a map

  ## Example
      iex> Punt.of_map([a: Punt.get(:b, Punt.string)]) |> Punt.parse(%{b: "foo"})
      {:ok, %{a: "foo"}}
  """
  def of_map(map) do
    parse = fn input ->
      new(map, input)
    end

    gen_map =
      Map.new(map, fn {key, value} ->
        {key, value.gen}
      end)

    gen = StreamData.fixed_map(gen_map)

    build(parse: parse, gen: gen)
  end

  @doc """
  Parse into a struct

  ## Example
      iex> Punt.of_struct([a: Punt.get(:b, Punt.string)], A) |> Punt.parse(%{b: "foo"})
      {:ok, %PuntTest.A{a: "foo"}}
  """
  def of_struct(map, module) do
    parse = fn input ->
      new(map, input, module)
    end

    gen_map =
      Map.new(map, fn {key, value} ->
        {key, value.gen}
      end)

    gen = StreamData.fixed_map(gen_map)

    build(parse: parse, gen: gen)
  end

  @doc """
  Parse a map key

  ## Example

      iex> Punt.get(:name, Punt.string) |> Punt.parse(%{name: "foo"})
      {:ok, "foo"}

      iex> Punt.get(:name, Punt.string) |> Punt.parse(%{bar: "foo"})
      {:error, %{code: :no_such_get, field: :name, input: %{bar: "foo"}}}
  """
  def get(name, p) do
    parse = fn input ->
      case Map.fetch(input, name) do
        {:ok, value} -> p.parse.(value)
        :error -> {:error, %{code: :no_such_get, input: input, field: name}}
      end
    end

    map =
      %{}
      |> Map.put(name, p.gen)

    build(parse: parse, gen: StreamData.fixed_map(map))
  end

  @doc """
  Parse a map, fallback to default

  ## Example

      iex> Punt.get_or_missing(:name, "default", Punt.string) |> Punt.parse(%{name: "foo"})
      {:ok, "foo"}

      iex> Punt.get_or_missing(:name, "default", Punt.string) |> Punt.parse(%{bar: "foo"})
      {:ok, "default"}
  """
  def get_or_missing(name, default, p) do
    parse = fn input ->
      case Map.fetch(input, name) do
        {:ok, value} -> p.parse.(value)
        :error -> {:ok, default}
      end
    end

    build(parse: parse)
  end

  @doc """
  Parse a pair

  ## Example

      iex> Punt.singleton_of(Punt.string) |> Punt.parse(["foo"])
      {:ok, "foo"}
  """
  def singleton_of(p) do
    parse = fn
      [el] ->
        case p.parse.(el) do
          {:ok, parsed} ->
            {:ok, parsed}

          {:error, why} ->
            {:error, %{failed_element: el, details: why}}
        end

      _other ->
        {:error, :not_a_singleton}
    end

    build(parse: parse)
  end

  @doc """
  Parse a pair

  ## Example

      iex> Punt.pair_of(Punt.string, Punt.string) |> Punt.parse(["foo", "bar"])
      {:ok, {"foo", "bar"}}
  """
  def pair_of(p1, p2) do
    convert_pair = fn a, b ->
      case p1.parse.(a) do
        {:ok, p1_res} ->
          case p2.parse.(b) do
            {:ok, p2_res} ->
              {:ok, {p1_res, p2_res}}

            {:error, why} ->
              {:error, %{failed_element: a, details: why}}
          end

        {:error, why} ->
          {:error, %{failed_element: b, details: why}}
      end
    end

    parse = fn
      {a, b} ->
        convert_pair.(a, b)

      [a, b] ->
        convert_pair.(a, b)

      _other ->
        {:error, :not_a_pair}
    end

    build(parse: parse)
  end

  @doc """
  Parse a list

  ## Example

      iex> Punt.list_of(Punt.string) |> Punt.parse(["foo", "bar"])
      {:ok, ["foo", "bar"]}

      iex> Punt.list_of(Punt.string) |> Punt.parse(["foo", 1])
      {:error, %{details: :not_a_string, failed_element: 1}}
  """
  def list_of(p, opts \\ []) do
    parse = fn
      xs when is_list(xs) ->
        Enum.reduce(xs, {:ok, []}, fn
          el, {:ok, acc} ->
            case p.parse.(el) do
              {:ok, parsed} ->
                {:ok, [parsed | acc]}

              {:error, why} ->
                {:error, %{failed_element: el, details: why}}
            end

          _el, error ->
            error
        end)
        |> case do
          {:ok, res} -> {:ok, Enum.reverse(res)}
          error -> error
        end

      _other ->
        {:error, :not_a_list}
    end

    build(parse: parse, gen: opts[:gen] || StreamData.list_of(p.gen))
  end

  @doc """
  Parse a string

  ## Example

      iex> Punt.string() |> Punt.parse("foo")
      {:ok, "foo"}

      iex> Punt.string() |> Punt.parse(3.4)
      {:error, :not_a_string}

      iex> Punt.string() |> Punt.parse(3)
      {:error, :not_a_string}
  """
  def string(opts \\ []) do
    parse = Punt.Parser.string()
    build(parse: parse, gen: opts[:gen] || StreamData.string(:printable))
  end

  @doc """
  Parse a integer

  ## Example

      iex> Punt.integer() |> Punt.parse(3)
      {:ok, 3}

      iex> Punt.integer() |> Punt.parse(3.4)
      {:error, :not_an_integer}

      iex> Punt.integer() |> Punt.parse("foo")
      {:error, :not_an_integer}
  """
  def integer(opts \\ []) do
    parse = Punt.Parser.integer()
    build(parse: parse, gen: opts[:gen] || StreamData.integer())
  end

  @doc """
  Parse a float

  ## Example

      iex> Punt.float() |> Punt.parse(3.4)
      {:ok, 3.4}

      iex> Punt.float() |> Punt.parse(3)
      {:error, :not_a_float}

      iex> Punt.float() |> Punt.parse("foo")
      {:error, :not_a_float}
  """
  def float() do
    parse = fn
      s when is_float(s) -> {:ok, s}
      _other -> {:error, :not_a_float}
    end

    build(parse: parse)
  end

  @doc """
  Parse a number

  ## Example

      iex> Punt.number() |> Punt.parse(3.4)
      {:ok, 3.4}

      iex> Punt.number() |> Punt.parse(3)
      {:ok, 3}

      iex> Punt.number() |> Punt.parse("foo")
      {:error, :not_a_number}
  """
  def number() do
    parse = fn
      s when is_number(s) -> {:ok, s}
      _other -> {:error, :not_a_number}
    end

    build(parse: parse)
  end

  @doc """
  Parse a boolean

  ## Example

      iex> Punt.boolean() |> Punt.parse(true)
      {:ok, true}

      iex> Punt.boolean() |> Punt.parse(false)
      {:ok, false}

      iex> Punt.boolean() |> Punt.parse("foo")
      {:error, :not_a_boolean}
  """
  def boolean() do
    parse = fn
      s when is_boolean(s) -> {:ok, s}
      _other -> {:error, :not_a_boolean}
    end

    build(parse: parse)
  end

  @doc """
  Parse a nil

  ## Example

      iex> Punt.null() |> Punt.parse(nil)
      {:ok, nil}

      iex> Punt.null() |> Punt.parse("foo")
      {:error, :not_a_null}
  """
  def null() do
    parse = fn
      s when is_nil(s) -> {:ok, s}
      _other -> {:error, :not_a_null}
    end

    build(parse: parse)
  end

  @doc """
  Parse a value at index

  ## Example

      iex> Punt.index(2, Punt.number) |> Punt.parse([1,2,3])
      {:ok, 3}

      iex> Punt.index(10, Punt.number) |> Punt.parse([1,2,3])
      {:error, :not_a_number}
  """
  def index(i, p) do
    parse = fn
      xs ->
        if Enumerable.impl_for(xs) do
          p.parse.(Enum.at(xs, i))
        else
          {:error, :not_enumerable}
        end
    end

    build(parse: parse, gen: StreamData.list_of(p.gen, length: i))
  end

  def map(result_fun, decoders) when is_function(result_fun) and is_list(decoders) do
    parse = fn input ->
      results =
        Enum.reduce(decoders, {:ok, []}, fn
          decoder, {:ok, acc} ->
            case decoder.parse.(input) do
              {:ok, res} -> {:ok, [res | acc]}
              error -> error
            end

          _el, error ->
            error
        end)
        |> case do
          {:ok, res} -> {:ok, Enum.reverse(res)}
          error -> error
        end

      result_fun.(results)
    end

    build(parse: parse)
  end

  @doc """
  Apply parser and map over result

  ## Example

      iex> Punt.map(Punt.string(), &String.to_integer(&1)) |> Punt.parse("123")
  """
  def map(p, map_fun, gen_fun \\ nil) do
    parse = fn input ->
      case p.parse.(input) do
        {:ok, res} -> map_fun.(res)
        {:error, error} -> {:error, error}
      end
    end

    build(parse: parse, gen: gen_fun)
  end

  @doc """
  Apply parser, and then decide what to do

  Useful for conditional parsing based on result of previous parse
  """
  def and_then(p, fun) do
    punt = build(parse: fun)

    parse = fn input ->
      case p.parse.(input) do
        {:ok, res} -> punt.parse.(res) |> Punt.parse(input)
        {:error, error} -> {:error, error}
      end
    end

    build(parse: parse)
  end

  @doc """
  Always failing parser
  """
  def fail(reason) do
    parse = fn _ ->
      {:error, reason}
    end

    build(parse: parse)
  end

  @doc """
  Always succeeding parser
  """
  def succeed(value) do
    parse = fn _ ->
      {:ok, value}
    end

    build(parse: parse, gen: StreamData.constant(value))
  end

  @doc """
  Returns value you put in

  ## Example

      iex> Punt.value() |> Punt.parse("123")
      {:ok, "123"}
  """
  def value() do
    parse = fn input ->
      {:ok, input}
    end

    build(parse: parse, gen: StreamData.term())
  end

  @doc """
  Chooses one of the given parser

  ## Example

      iex> Punt.one_of([Punt.null(), Punt.integer()]) |> Punt.parse(123)
      {:ok, 123}

      iex> Punt.one_of([Punt.null(), Punt.integer()]) |> Punt.parse(nil)
      {:ok, nil}
  """
  def one_of(decoders) do
    parse = fn input ->
      Enum.reduce(decoders, {:error, []}, fn
        decoder, {:error, acc} ->
          case decoder.parse.(input) do
            {:error, error} -> {:error, [error | acc]}
            {:ok, res} -> {:ok, res}
          end

        _decoder, {:ok, res} ->
          {:ok, res}
      end)
      |> case do
        {:ok, res} ->
          {:ok, res}

        {:error, error} ->
          {:error, %{input: input, errors: error, reason: :one_of_failed, decoders: decoders}}
      end
    end

    build(parse: parse, gen: decoders |> Enum.map(& &1.gen) |> StreamData.one_of())
  end

  @doc """
  Check whether a value holds for the input

  ## Example

      iex> Punt.predicate(& &1 == 123) |> Punt.parse(123)
      {:ok, 123}

      iex> Punt.predicate(& &1 != 123) |> Punt.parse(123)
      {:error, %{context: [], input: 123, reason: :predicate_failed}}
  """
  def predicate(fun, context \\ []) do
    parse = fn input ->
      if fun.(input) == true do
        {:ok, input}
      else
        {:error, %{input: input, reason: :predicate_failed, context: context}}
      end
    end

    build(parse: parse)
  end


  @doc """
  Gets a nested value from nested maps

  ## Example

      iex> Punt.get_in([:a, :b], Punt.number()) |> Punt.parse(%{a: %{b: 123}})
      {:ok, 123}
  """
  def get_in(names, p) do
    parse = fn input ->
        deep_value = names
        |> Enum.reduce(input, fn
          name, {:error, _} ->
            {:error, %{code: :no_such_get, input: input, field: name}}

          name, input ->
            case Map.fetch(input, name) do
              {:ok, value} -> value
              :error -> {:error, %{code: :no_such_get, input: input, field: name}}
            end
        end)

        p.parse.(deep_value)
    end


    Punt.build(parse: parse)
  end
end
