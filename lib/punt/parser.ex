defmodule Punt.Parser do
  def string() do
    fn
      s when is_binary(s) -> {:ok, s}
      _other -> {:error, :not_a_string}
    end
  end

  def integer() do
    fn
      s when is_integer(s) -> {:ok, s}
      _other -> {:error, :not_an_integer}
    end
  end
end
