defmodule Punt do
  @moduledoc """
  Documentation for `Punt`.
  """
  defstruct [:parse, :gen]

  defmacro defparse(name, combinator) do
    quote do
      def unquote(name)(input) do
        # combinator |> dbg
        # |> Macro.escape() |> IO.inspect()
        unquote(combinator).parse.(input)
      end
    end
  end

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
          {:ok, struct(module, result)}
        else
          {:ok, Map.new(result)}
        end

      error ->
        error
    end
  end

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

  def get_or_missing(name, default, p) do
    parse = fn input ->
      case Map.fetch(input, name) do
        {:ok, value} -> p.(value)
        :error -> {:ok, default}
      end
    end

    build(parse: parse)
  end

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

  def string(opts \\ []) do
    parse = Punt.Parser.string()
    build(parse: parse, gen: opts[:gen] || StreamData.string(:printable))
  end

  def integer(opts \\ []) do
    parse = Punt.Parser.integer()
    build(parse: parse, gen: opts[:gen] || StreamData.integer())
  end

  def float() do
    parse = fn
      s when is_float(s) -> {:ok, s}
      _other -> {:error, :not_a_float}
    end

    build(parse: parse)
  end

  def number() do
    parse = fn
      s when is_number(s) -> {:ok, s}
      _other -> {:error, :not_a_number}
    end

    build(parse: parse)
  end

  def boolean() do
    parse = fn
      s when is_boolean(s) -> {:ok, s}
      _other -> {:error, :not_a_boolean}
    end

    build(parse: parse)
  end

  def null() do
    parse = fn
      s when is_nil(s) -> {:ok, s}
      _other -> {:error, :not_a_null}
    end

    build(parse: parse)
  end

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

  def map(p, map_fun, gen_fun \\ nil) do
    parse = fn input ->
      case p.parse.(input) do
        {:ok, res} -> map_fun.(res)
        {:error, error} -> {:error, error}
      end
    end

    build(parse: parse, gen: gen_fun)
  end

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

  def fail(reason) do
    parse = fn _ ->
      {:error, reason}
    end

    build(parse: parse)
  end

  def succeed(value) do
    parse = fn _ ->
      {:ok, value}
    end

    build(parse: parse, gen: StreamData.constant(value))
  end

  def value() do
    parse = fn input ->
      {:ok, input}
    end

    build(parse: parse, gen: StreamData.term())
  end

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
end
