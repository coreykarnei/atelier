# Dense Elixir fixture for the hlcheck harness.
defmodule Atelier.Fixture do
  @moduledoc """
  A module exercising every construct the highlight query should tag.
  """

  use GenServer
  import Enum, only: [map: 2, reduce: 3]
  alias Atelier.Fixture.{Helper, Other}
  require Logger

  @behaviour GenServer
  @default_limit 42
  @tag :fixture
  @compile {:inline, small: 1}

  defstruct name: "anon", count: 0, tags: []

  @type t :: %__MODULE__{name: String.t(), count: non_neg_integer(), tags: [atom()]}
  @typedoc "An option keyword list"
  @type opts :: keyword()

  @spec new(String.t(), non_neg_integer()) :: t()
  def new(name, count \\ 0) when is_binary(name) and count >= 0 do
    %__MODULE__{name: name, count: count}
  end

  @doc """
  Sums the struct's count with `extra`.
  """
  @spec total(t(), integer()) :: integer()
  def total(%__MODULE__{count: count} = fixture, extra) do
    _unused = fixture.name
    count + extra
  end

  defp helper(x), do: x * 2

  defmacro double(expr) do
    quote do
      unquote(expr) * 2
    end
  end

  defguard is_even(n) when is_integer(n) and rem(n, 2) == 0

  def classify(value) do
    cond do
      value in [1, 2, 3] -> :small
      value > 100 -> :large
      true -> :medium
    end
  end

  def control(list, map) do
    if length(list) > 0 do
      IO.puts("non-empty")
    else
      IO.puts("empty")
    end

    unless map == %{}, do: :ok

    case Map.fetch(map, :key) do
      {:ok, value} -> value
      :error -> nil
    end

    for x <- list, y <- 1..3, x != y, into: %{} do
      {x, y}
    end

    with {:ok, a} <- Helper.fetch(1),
         {:ok, b} <- Other.fetch(a) do
      a + b
    else
      _ -> :error
    end

    try do
      raise ArgumentError, message: "boom"
    rescue
      e in ArgumentError -> Logger.error(e.message)
    catch
      :throw, val -> val
    after
      IO.puts("done")
    end

    receive do
      {:msg, payload} -> payload
    after
      1_000 -> :timeout
    end
  end

  def numbers do
    ints = [42, 1_000_000, 0xFF, 0o755, 0b1010]
    floats = [3.14, 1.0e10, 2.5e-3]
    chars = [?a, ?\n]
    {ints, floats, chars}
  end

  def strings(name) do
    plain = "hello \"world\"\n\t"
    interp = "Hello, #{name}! Count: #{1 + 2}"
    charlist = 'abc\n'
    regex = ~r/^\d+(?<word>\w+)$/iu
    sigil_s = ~s(string sigil with #{name})
    words = ~w(alpha beta gamma)a
    heredoc = """
    multi-line #{plain}
    """
    {plain, interp, charlist, regex, sigil_s, words, heredoc}
  end

  def operators(a, b) do
    a |> helper() |> Helper.transform(b)
    x = a + b - a * b / 2
    y = a <> "suffix"
    z = [a | [b]] ++ [1, 2] -- [1]
    ok = a == b && a != b || not (a === b) and (a <= b or a >= b)
    ptr = &helper/1
    remote = &Enum.map/2
    anon = fn n -> n + 1 end
    short = &(&1 * 2)
    pin = ^a
    <<head::binary-size(2), rest::binary>> = "abcdef"
    {x, y, z, ok, ptr, remote, anon, short, pin, head, rest}
  end

  def atoms_and_keywords(opts) do
    opts = Keyword.put(opts, :limit, @default_limit)
    quoted = :"quoted atom"
    kw = [foo: 1, "bar baz": 2, nil: nil]
    mod = :erlang.system_time(:millisecond)
    bool = true and false
    {opts, quoted, kw, mod, bool, __MODULE__, __ENV__.line}
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state.count, %{state | count: state.count + 1}}
  end
end

defprotocol Atelier.Describable do
  @doc "Describe a value."
  def describe(value)
end

defimpl Atelier.Describable, for: Atelier.Fixture do
  def describe(%Atelier.Fixture{name: name}), do: "fixture #{name}"
end
