defmodule World.References do
  @moduledoc """
  The references of World (plan 0003, D1; `priv/references/NAME.json`,
  `docs/references.md`): real things with their published numbers, and
  the order that builds each in World. `run/2` has the people of the node
  build the order, measures the model as the standard of each number
  defines it (`World.Measure`), and gives each number with its value, the
  value of the model, the error and the tolerance. The test of the
  references asserts that each number is in its tolerance (D3: no gaps).

  A reference: `name`, `title`, `sources` (each with its `name`, `url`,
  and `license`: `facts` for the numbers of a document that is not in the
  repository), `order` (an order of World), `level` (`near` by default),
  and `numbers`, each with its `name`, `value`, `unit`, `tolerance` (a
  part of the value: 0.01 is 1%; or `abs` in the unit of the value), the
  index of its `source`, its `standard`, and its `measure`:

  - `{"size": "length" | "width" | "height", "without": [nodes]}`;
  - `{"wheelbase": true}`, `{"track": "front" | "rear"}`;
  - `{"ground_clearance": {"without": [nodes]}}`;
  - `{"top": node, "span": [y0, y1]}`: the most z of a node (of its
    points in the span of y, if the span is given);
  - `{"seat": node, "span": [y0, y1]}`: the seat height of a
    two-wheeler, the lowest point of the top of its seat in the span;
  - `{"along": "x" | "y" | "z", "from": [node, port], "to": [node, port]}`:
    the distance between two ports along an axis (the stack of a frame);
  - `{"distance": [[node, port], [node, port]]}`;
  - `{"angle": [node, port]}`: the angle of the axis of a port from the
    ground, in degrees (the head angle of a frame);
  - `{"mass": true}`, in kg;
  - `{"takeoff": material}`: the count of a material of the bill of
    quantities of the drawing.
  """
  alias World.{Measure, Orders, Vec}

  @root Path.expand("../../priv/references", __DIR__)
  @paths Path.wildcard(Path.join(@root, "*.json"))
  for p <- @paths, do: @external_resource(p)
  @all Enum.map(@paths, &(&1 |> File.read!() |> JSON.decode!()))
  @hash :erlang.md5(Enum.join(@paths))

  @doc false
  def __mix_recompile__?, do: :erlang.md5(Enum.join(Path.wildcard(Path.join(@root, "*.json")))) != @hash

  @doc "The references, in the order of their names."
  def all, do: Enum.sort_by(@all, & &1["name"])

  @doc "A reference by its name: `{:ok, reference}` or `:error`."
  def fetch(name) do
    case Enum.find(all(), &(&1["name"] == name)) do
      nil -> :error
      r -> {:ok, r}
    end
  end

  @doc """
  Build a reference with the people of the node (`World.build/1`, with
  `workers`, 16 by default) and compare its numbers: a list of
  `%{"name", "value", "model", "error", "tolerance", "ok"}`, one for each
  number. The error is a part of the value (or the difference, for a
  number with `abs`).
  """
  def run(ref, opts \\ []) do
    level = Map.get(ref, "level", "near")
    {:ok, job} = Orders.job(ref["order"], level)
    {:ok, id} = World.build(Map.put(job, :budget, %{"workers" => Keyword.get(opts, :workers, 16)}))
    {:ok, _} = World.await(id, :infinity)
    m = Measure.of(job.item.(job.level), job.level)
    for n <- ref["numbers"], do: compare(n, value(n["measure"], m, job.drawing))
  end

  defp compare(n, model) do
    {error, tolerance} =
      case n["tolerance"] do
        %{"abs" => t} -> {model - n["value"], t}
        t -> {(model - n["value"]) / n["value"], t || 0.01}
      end

    %{
      "name" => n["name"],
      "value" => n["value"],
      "model" => model,
      "error" => error,
      "tolerance" => tolerance,
      "ok" => abs(error) <= tolerance
    }
  end

  @doc "The value of a measure of a model (`World.Measure.of/2`) and its drawing (`references` of this module)."
  def value(%{"size" => axis} = d, m, _),
    do:
      Measure.size(
        m,
        Map.fetch!(%{"length" => :length, "width" => :width, "height" => :height}, axis),
        Map.get(d, "without", [])
      )

  def value(%{"wheelbase" => true}, m, _), do: Measure.wheelbase(m)
  def value(%{"track" => which}, m, _), do: Measure.track(m, Map.fetch!(%{"front" => :front, "rear" => :rear}, which))
  def value(%{"ground_clearance" => d}, m, _), do: Measure.ground_clearance(m, Map.get(d, "without", []))
  def value(%{"top" => node} = d, m, _), do: Measure.top(m, node, d["span"] && List.to_tuple(d["span"]))

  def value(%{"seat" => node, "span" => [y0, y1]}, m, _), do: Measure.seat(m, node, {y0, y1})

  def value(%{"along" => axis, "from" => [n0, p0], "to" => [n1, p1]}, m, _) do
    i = Map.fetch!(%{"x" => 0, "y" => 1, "z" => 2}, axis)
    {a, _} = Measure.port(m, n0, p0)
    {b, _} = Measure.port(m, n1, p1)
    elem(b, i) - elem(a, i)
  end

  def value(%{"distance" => [[n0, p0], [n1, p1]]}, m, _),
    do: Vec.len(Vec.sub(elem(Measure.port(m, n1, p1), 0), elem(Measure.port(m, n0, p0), 0)))

  def value(%{"angle" => [node, port]}, m, _) do
    {_, {_, y, z}} = Measure.port(m, node, port)
    :math.atan2(abs(z), abs(y)) * 180 / :math.pi()
  end

  def value(%{"mass" => true}, m, _), do: Measure.mass(m)
  def value(%{"takeoff" => material}, _m, drawing), do: Map.get(Measure.takeoff(drawing), material, 0)
end
