defmodule World.Skills.Mixing do
  @moduledoc """
  The skill `mixing` of a caster (plan 0006, D6): the place where the
  people of a site with no machine mix the concrete by hand (1974, an
  estimate): a board of timber of 4 by 4 m at `at` (`[x, y]`, m, in the
  frame of the lot), a heap of sand and a heap of gravel next to it, and
  a drum of water. The part is temporary: the stream shows it, the model
  leaves it out.
  """
  @behaviour World.Skill
  alias World.{Part, Shape}
  alias World.Orders.Blueprint
  import Blueprint, only: [option: 3]

  defp options, do: [option("at", :data, default: [0.0, 0.0], check: &point/2)]

  defp point([x, y], _path) when is_number(x) and is_number(y), do: {:ok, [x / 1, y / 1]}
  defp point(_v, path), do: {:error, [{path, "must be a point [x, y] in m"}]}

  @impl true
  def name, do: "mixing"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path) do
    case Blueprint.check_options(options(), data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @impl true
  def estimate(_data, :far), do: 0
  def estimate(_data, _level), do: 200

  @impl true
  def make(data, _inputs, %{name: name}) do
    {:ok, %{"at" => [x, y]}} = Blueprint.check_options(options(), data, "")

    heap = fn dx, r, h, material ->
      Shape.lathe([{0.0, 0.0}, {r, 0.0}, {0.0, h}], material, frame: World.Frame.move({x + dx, y + 3.2, 0.0}))
    end

    shapes = [
      Shape.box({x - 2.0, y - 2.0, 0.0}, {x + 2.0, y + 2.0, 0.06}, :wood),
      heap.(-1.2, 1.3, 1.0, :concrete),
      heap.(1.4, 1.2, 0.9, :gray),
      Shape.lathe([{0.0, 0.0}, {0.3, 0.0}, {0.3, 0.9}, {0.0, 0.9}], :blue, frame: World.Frame.move({x + 2.6, y, 0.0}))
    ]

    {Part.new(name, :part, shapes, [Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]), %{"temporary" => true}, %{}}
  end
end
