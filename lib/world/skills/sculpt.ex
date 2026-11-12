defmodule World.Skills.Sculpt do
  @moduledoc """
  The skill `sculpt` of a sculptor (`docs/plans/0008-model-from-edits.md`,
  D9): a part from a list of edits (`docs/format.md`, "A sculpture").

  Its data: `edits` (a list of 1 to 10,000 edits: each with its `shape`
  and its `size`, and `at`, `axis`, `up`, `mode`, `blend`, `material`),
  and `ports`, `sources`, `budget` (the most triangles at `near`, `mid`
  and `far`) and `cells` (the size of the cells at `near`, `mid` and
  `far`, m: for a small model, smaller cells than the cells of the
  levels, `World.Sculpt.step/1`). The sculptor makes the part with the tree of the
  bricks of the edits (`World.Sculpt.model/2`) in its hand: the tree is
  the crew of the hand, so a stop of the person stops it (D4).
  """
  @behaviour World.Skill

  alias World.{Drawing, GLB, Part, Port, SDF, Vec}

  @keys ~w(edits ports sources budget cells)
  @edit ~w(shape size at axis up mode blend material)
  @most 10_000
  @size 1_000
  # The atoms of the names of the shapes and of the modes.
  @atoms Map.new(SDF.shapes() ++ SDF.modes(), &{Atom.to_string(&1), &1})

  # The count of the sizes of each shape (the tube has points and radii).
  @sizes %{
    "ball" => 1,
    "box" => 3,
    "round_box" => 4,
    "capsule" => 2,
    "cylinder" => 2,
    "cone" => 3,
    "ring" => 2,
    "ellipsoid" => 3,
    "superellipsoid" => 4
  }

  @impl true
  def name, do: "sculpt"

  @impl true
  def trade, do: :sculptor

  @impl true
  def check(data, path) when is_map(data) do
    World.Skill.keys(data, path, @keys, ~w(edits)) ++
      optional(data, "edits", path, &edits/2) ++
      optional(data, "ports", path, &Drawing.check_ports/2) ++
      optional(data, "sources", path, &sources/2) ++
      optional(data, "budget", path, &budget/2) ++
      optional(data, "cells", path, &cells/2)
  end

  def check(_data, path), do: [{path, "must be an object"}]

  @impl true
  def make(data, _inputs, %{level: level, name: name}) do
    edits = edits(data["edits"])
    budget = get_in(data, ["budget", Atom.to_string(level)])
    meshes = World.Sculpt.model(edits, step: step(data, level), budget: budget)
    ports = Drawing.ports(Map.get(data, "ports", %{}))
    {Part.new(name, :part, meshes, ports, sources: Map.get(data, "sources", [])), %{}, %{}}
  end

  @impl true
  def estimate(data, level) do
    with [] <- check(data, ""),
         {{x0, y0, z0}, {x1, y1, z1}} <- SDF.bounds(edits(data["edits"])) do
      {a, b, c} = {x1 - x0, y1 - y0, z1 - z0}
      step = step(data, level)
      # Two faces for each cell of the surface of the box round it, a bit less for a round shape.
      faces = round(1.4 * (a * b + b * c + c * a) / (step * step))
      min(faces, get_in(data, ["budget", Atom.to_string(level)]) || faces)
    else
      _ -> 0
    end
  end

  # The size of the cells of a level: from the data, else of the level.
  defp step(data, level), do: get_in(data, ["cells", Atom.to_string(level)]) || World.Sculpt.step(level)

  @doc "The edits of a sculpture from its data (`World.SDF.edit/3`)."
  def edits(list), do: Enum.map(list, &edit/1)

  defp edit(e) do
    # The axes of the sculpture by default: z up and y to the front (z
    # up when the axis is along y).
    axis = Map.get(e, "axis", [0, 0, 1])
    along_y = Vec.len(Vec.cross(Vec.float(List.to_tuple(axis)), {0.0, 1.0, 0.0})) < 1.0e-6

    frame = %{
      "at" => Map.get(e, "at", [0, 0, 0]),
      "axis" => axis,
      "up" => e["up"] || if(along_y, do: [0, 0, 1], else: [0, 1, 0])
    }

    [port] = Drawing.ports(%{"edit" => frame})

    SDF.edit(@atoms[e["shape"]], size(e["shape"], e["size"]),
      frame: Port.frame(port),
      mode: @atoms[Map.get(e, "mode", "add")],
      blend: Map.get(e, "blend", 0),
      material: e["material"] && GLB.role(e["material"])
    )
  end

  defp size("tube", %{"points" => points, "radii" => radii}), do: {Enum.map(points, &List.to_tuple/1), radii}
  defp size(_shape, size), do: List.to_tuple(size)

  # The checks of the data.

  defp optional(data, key, path, check),
    do: if(Map.has_key?(data, key), do: check.(data[key], "#{path}.#{key}"), else: [])

  defp edits(v, path) when is_list(v) and v != [] and length(v) <= @most do
    v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> edit(e, "#{path}.#{i}") end)
  end

  defp edits(_v, path), do: [{path, "must be a list of 1 to #{@most} edits"}]

  defp edit(e, path) when is_map(e) do
    World.Skill.keys(e, path, @edit, ~w(shape size)) ++
      shape(e, path) ++
      optional(e, "at", path, &point/2) ++
      optional(e, "axis", path, &direction/2) ++
      optional(e, "up", path, &direction/2) ++
      optional(e, "mode", path, &choice(&1, &2, ~w(add subtract paint))) ++
      optional(e, "blend", path, &number(&1, &2, 0, 10)) ++
      optional(e, "material", path, &choice(&1, &2, GLB.palette() |> Map.keys() |> Enum.sort()))
  end

  defp edit(_e, path), do: [{path, "must be an object"}]

  defp shape(%{"shape" => shape} = e, path) when is_map_key(@sizes, shape) or shape == "tube",
    do: optional(e, "size", path, &sizes(shape, &1, &2))

  defp shape(%{"shape" => _}, path),
    do: [{"#{path}.shape", "must be one of: #{Enum.join(Enum.sort(["tube" | Map.keys(@sizes)]), ", ")}"}]

  defp shape(_e, _path), do: []

  defp sizes("tube", %{"points" => points, "radii" => radii}, path)
       when is_list(points) and is_list(radii) and length(points) in 2..256 and length(points) == length(radii) do
    (points |> Enum.with_index() |> Enum.flat_map(fn {p, i} -> point(p, "#{path}.points.#{i}") end)) ++
      (radii |> Enum.with_index() |> Enum.flat_map(fn {r, i} -> number(r, "#{path}.radii.#{i}", 0.0001, @size) end))
  end

  defp sizes("tube", _v, path),
    do: [{path, "must be {\"points\": [[x, y, z], ...], \"radii\": [r, ...]}: 2 to 256 points, a radius for each"}]

  defp sizes(shape, v, path) do
    n = @sizes[shape]

    if is_list(v) and length(v) == n and Enum.all?(v, &(is_number(&1) and &1 >= 0 and &1 <= @size)) do
      extra(shape, v, path)
    else
      [{path, "must be a list of #{n} sizes in meters, from 0 to #{@size} m (docs/format.md, \"A sculpture\")"}]
    end
  end

  # The rules of the sizes of some shapes.
  defp extra("round_box", [x, y, z, r], path) do
    if r <= Enum.min([x, y, z]), do: [], else: [{path, "the radius of the edges must be at most the least half size"}]
  end

  defp extra("superellipsoid", [_, _, _, e], path) do
    if e >= 2 and e <= 64, do: [], else: [{path, "the power must be from 2 to 64"}]
  end

  defp extra("cone", [r1, r2, h], path) do
    if h > 0 and max(r1, r2) > 0, do: [], else: [{path, "the cone must have a height and a radius more than 0"}]
  end

  defp extra(_shape, v, path) do
    if Enum.all?(v, &(&1 > 0)), do: [], else: [{path, "each size must be more than 0"}]
  end

  defp point(v, path) do
    if match?([_, _, _], v) and Enum.all?(v, &(is_number(&1) and abs(&1) <= @size)),
      do: [],
      else: [{path, "must be a point [x, y, z] in meters, at most #{@size} m"}]
  end

  defp direction(v, path) do
    case point(v, path) do
      [] -> if Vec.len(Vec.float(List.to_tuple(v))) > 1.0e-6, do: [], else: [{path, "must not be zero"}]
      errors -> errors
    end
  end

  defp number(v, path, lo, hi),
    do: if(is_number(v) and v >= lo and v <= hi, do: [], else: [{path, "must be a number from #{lo} to #{hi}"}])

  defp choice(v, path, values),
    do: if(v in values, do: [], else: [{path, "must be one of: #{Enum.join(values, ", ")}"}])

  defp sources(v, path) do
    if is_list(v) and length(v) <= 16 and Enum.all?(v, &(is_binary(&1) and byte_size(&1) <= 500)),
      do: [],
      else: [{path, "must be a list of at most 16 texts of at most 500 bytes"}]
  end

  defp budget(v, path) when is_map(v) do
    World.Skill.keys(v, path, ~w(near mid far)) ++
      Enum.flat_map(Enum.sort(v), fn {k, n} ->
        if is_integer(n) and n >= 12 and n <= 1_000_000,
          do: [],
          else: [{"#{path}.#{k}", "must be a count of triangles from 12 to 1000000"}]
      end)
  end

  defp budget(_v, path), do: [{path, "must be an object of near, mid and far"}]

  defp cells(v, path) when is_map(v) do
    World.Skill.keys(v, path, ~w(near mid far)) ++
      Enum.flat_map(Enum.sort(v), fn {k, n} -> number(n, "#{path}.#{k}", 0.001, 1) end)
  end

  defp cells(_v, path), do: [{path, "must be an object of near, mid and far"}]
end
