defmodule World.Skills.Sculpt do
  @moduledoc """
  The skill `sculpt` of a sculptor (`docs/plans/0008-model-from-edits.md`,
  D9): a part from a list of edits (`docs/format.md`, "A sculpture").

  Its data: `edits` (a list of 1 to 10,000 edits: each with its `shape`
  and its `size`, and `at`, `axis`, `up`, `mode`, `blend`, `material`,
  `color`, and its copies: `mirror` and `repeat`), `groups` (a name to
  a list of edits, that an edit of the shape `group` uses at a place and
  a `scale`),
  and `ports`, `sources`, `budget` (the most triangles at `near`, `mid`
  and `far`) and `cells` (the size of the cells at `near`, `mid` and
  `far`, m). With no `cells` for a level and a budget, the cells fit the
  budget and the thinnest edit (`World.Sculpt.fit/2`); with neither, the
  cells of the level (`World.Sculpt.step/1`). The sculptor makes the part with the tree of the
  bricks of the edits (`World.Sculpt.model/2`) in its hand: the tree is
  the crew of the hand, so a stop of the person stops it (D4).
  """
  @behaviour World.Skill

  alias World.{Drawing, Frame, GLB, Part, Port, SDF, Vec}

  @keys ~w(edits groups ports sources budget cells)
  @edit ~w(shape size at axis up mode blend material color mirror repeat)
  @use ~w(shape group at axis up scale mirror repeat)
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
    groups = if is_map(data["groups"]), do: data["groups"], else: %{}

    World.Skill.keys(data, path, @keys, ~w(edits)) ++
      optional(data, "groups", path, &groups/2) ++
      optional(data, "edits", path, &edits(&1, &2, groups)) ++
      optional(data, "ports", path, &Drawing.check_ports/2) ++
      optional(data, "sources", path, &sources/2) ++
      optional(data, "budget", path, &budget/2) ++
      optional(data, "cells", path, &cells/2)
  end

  def check(_data, path), do: [{path, "must be an object"}]

  @impl true
  def make(data, _inputs, %{level: level, name: name}) do
    edits = all(data)
    budget = get_in(data, ["budget", Atom.to_string(level)])
    meshes = World.Sculpt.model(edits, step: step(data, level), budget: budget)
    ports = Drawing.ports(Map.get(data, "ports", %{}))
    {Part.new(name, :part, meshes, ports, sources: Map.get(data, "sources", [])), %{}, %{}}
  end

  @impl true
  def estimate(data, level) do
    with [] <- check(data, ""),
         {{x0, y0, z0}, {x1, y1, z1}} <- SDF.bounds(all(data)) do
      {a, b, c} = {x1 - x0, y1 - y0, z1 - z0}
      step = step(data, level)
      # Two faces for each cell of the surface of the box round it, a bit less for a round shape.
      faces = round(1.4 * (a * b + b * c + c * a) / (step * step))
      min(faces, get_in(data, ["budget", Atom.to_string(level)]) || faces)
    else
      _ -> 0
    end
  end

  # The size of the cells of a level: from the data; else, with a budget,
  # the cells that fit the budget and the thinnest edit; else the cells of
  # the level.
  defp step(data, level) do
    l = Atom.to_string(level)

    cond do
      cells = get_in(data, ["cells", l]) -> cells
      budget = get_in(data, ["budget", l]) -> World.Sculpt.fit(all(data), budget) || World.Sculpt.step(level)
      true -> World.Sculpt.step(level)
    end
  end

  defp all(data), do: edits(data["edits"], Map.get(data, "groups", %{}))

  @doc """
  The edits of a sculpture from its data (`World.SDF.edit/3`): each edit
  with its copies (`mirror`, `repeat`), and the edits of each group that
  an edit of the shape `group` uses, at its place and its scale.
  """
  def edits(list, groups \\ %{}), do: list |> Enum.flat_map(&specs(&1, groups)) |> Enum.map(&to_edit/1)

  # The plain edits of an edit of the data: a shape, its sizes, its frame.
  defp specs(%{"shape" => "group"} = e, groups) do
    {place, k} = {frame(e), Map.get(e, "scale", 1) / 1}

    group =
      groups[e["group"]]
      |> Enum.flat_map(&specs(&1, %{}))
      |> Enum.map(fn s ->
        at = %{s.frame | at: Vec.scale(s.frame.at, k)}
        %{s | frame: Frame.compose(place, at), size: scaled(s.shape, s.size, k), blend: s.blend * k}
      end)

    # Each copy is the whole group, in the order of its edits.
    for copy <- copies(e), s <- group, do: copy.(s)
  end

  defp specs(e, _groups) do
    spec = %{
      shape: @atoms[e["shape"]],
      size: size(e["shape"], e["size"]),
      frame: frame(e),
      mode: @atoms[Map.get(e, "mode", "add")],
      blend: Map.get(e, "blend", 0) / 1,
      material: e["material"] && GLB.role(e["material"]),
      color: e["color"] && rgb(e["color"])
    }

    for copy <- copies(e), do: copy.(spec)
  end

  defp to_edit(s), do: SDF.edit(s.shape, s.size, Keyword.new(Map.drop(s, [:shape, :size])))

  # The frame of an edit: the axes of the sculpture by default, z up and
  # y to the front (z up when the axis is along y).
  defp frame(e) do
    axis = Map.get(e, "axis", [0, 0, 1])
    along_y = Vec.len(Vec.cross(Vec.float(List.to_tuple(axis)), {0.0, 1.0, 0.0})) < 1.0e-6

    frame = %{
      "at" => Map.get(e, "at", [0, 0, 0]),
      "axis" => axis,
      "up" => e["up"] || if(along_y, do: [0, 0, 1], else: [0, 1, 0])
    }

    [port] = Drawing.ports(%{"edit" => frame})
    Port.frame(port)
  end

  # The sizes of a shape at a scale (the power of a superellipsoid stays).
  defp scaled(:tube, {points, radii}, k), do: {Enum.map(points, &Vec.scale(&1, k)), Enum.map(radii, &(&1 * k))}
  defp scaled(:superellipsoid, {x, y, z, e}, k), do: {x * k, y * k, z * k, e}
  defp scaled(_shape, size, k), do: size |> Tuple.to_list() |> Enum.map(&(&1 * k)) |> List.to_tuple()

  # The copies of an edit of the data, each as a function of a plain edit:
  # its repeat, then its mirrors.
  defp copies(e), do: for(r <- repeats(e["repeat"]), m <- mirrors(List.wrap(e["mirror"])), do: &m.(r.(&1)))

  defp repeats(nil), do: [& &1]

  defp repeats(%{"count" => n} = r) do
    axis = List.to_tuple(Map.get(r, "axis", [0, 0, 1]))
    center = Vec.float(List.to_tuple(Map.get(r, "center", [0, 0, 0])))
    move = Vec.float(List.to_tuple(Map.get(r, "move", [0, 0, 0])))
    # A ring of copies by default; with a move and no angle, a row.
    angle = Map.get(r, "angle", if(Map.has_key?(r, "move"), do: 0, else: 360 / n))

    for k <- 0..(n - 1) do
      place = Frame.compose(Frame.move(Vec.scale(move, k)), Frame.turn(axis, k * angle, center))
      fn s -> %{s | frame: Frame.compose(place, s.frame)} end
    end
  end

  defp mirrors([]), do: [& &1]
  defp mirrors([plane | rest]), do: for(a <- [& &1, &mirror(&1, plane)], b <- mirrors(rest), do: &b.(a.(&1)))

  # The copy of an edit across a plane of the sculpture. The frame of the
  # copy has the right hand again, so its x is the other way: each shape
  # is the same across its x, but the points of a tube turn theirs.
  defp mirror(%{frame: f} = s, plane) do
    flip = fn {x, y, z} -> %{"x" => {-x, y, z}, "y" => {x, -y, z}, "z" => {x, y, -z}}[plane] end

    size =
      with {points, radii} when is_list(points) <- s.size, do: {Enum.map(points, fn {x, y, z} -> {-x, y, z} end), radii}

    %{s | frame: Frame.new(flip.(f.at), flip.(f.z), flip.(f.y)), size: size}
  end

  # The count of the plain edits of an edit of the data.
  defp count(e, groups) do
    base = if e["shape"] == "group", do: groups[e["group"]] |> Enum.map(&count(&1, %{})) |> Enum.sum(), else: 1
    base * (get_in(e, ["repeat", "count"]) || 1) * 2 ** length(List.wrap(e["mirror"]))
  end

  defp size("tube", %{"points" => points, "radii" => radii}), do: {Enum.map(points, &List.to_tuple/1), radii}
  defp size(_shape, size), do: List.to_tuple(size)

  # The checks of the data.

  defp optional(data, key, path, check),
    do: if(Map.has_key?(data, key), do: check.(data[key], "#{path}.#{key}"), else: [])

  defp edits(v, path, groups) when is_list(v) and v != [] and length(v) <= @most do
    errors = v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> edit(e, "#{path}.#{i}", groups) end)
    # With no error, the count of the edits with their copies.
    total = if errors == [], do: v |> Enum.map(&count(&1, groups)) |> Enum.sum(), else: 0
    if total > @most, do: [{path, "has #{total} edits with their copies: at most #{@most}"}], else: errors
  end

  defp edits(_v, path, _groups), do: [{path, "must be a list of 1 to #{@most} edits"}]

  # The groups: a name to a list of edits (no group in a group).
  defp groups(v, path) when is_map(v) and map_size(v) <= 64 do
    Enum.flat_map(Enum.sort(v), fn {name, list} ->
      p = "#{path}.#{name}"

      cond do
        not (name =~ ~r/^[a-z0-9_]{1,40}$/) -> [{p, "must have a name of 1 to 40 letters a-z, digits or _"}]
        is_list(list) and list != [] and length(list) <= 1_000 -> edits(list, p, nil)
        true -> [{p, "must be a list of 1 to 1000 edits"}]
      end
    end)
  end

  defp groups(_v, path), do: [{path, "must be an object of at most 64 groups"}]

  # An edit that uses a group, at a place and a scale.
  defp edit(%{"shape" => "group"} = e, path, groups) when is_map(groups) do
    World.Skill.keys(e, path, @use, ~w(group)) ++
      optional(e, "group", path, &choice(&1, &2, groups |> Map.keys() |> Enum.sort())) ++
      optional(e, "scale", path, &number(&1, &2, 0.001, 1_000)) ++
      placed(e, path)
  end

  defp edit(%{"shape" => "group"}, path, nil),
    do: [{"#{path}.shape", "must not be a group: a group has no group in it"}]

  defp edit(e, path, _groups) when is_map(e) do
    World.Skill.keys(e, path, @edit, ~w(shape size)) ++
      shape(e, path) ++
      placed(e, path) ++
      optional(e, "mode", path, &choice(&1, &2, ~w(add subtract paint))) ++
      optional(e, "blend", path, &number(&1, &2, 0, 10)) ++
      optional(e, "material", path, &choice(&1, &2, GLB.palette() |> Map.keys() |> Enum.sort())) ++
      optional(e, "color", path, &color/2)
  end

  defp edit(_e, path, _groups), do: [{path, "must be an object"}]

  # The place of an edit, and its copies.
  defp placed(e, path) do
    optional(e, "at", path, &point/2) ++
      optional(e, "axis", path, &direction/2) ++
      optional(e, "up", path, &direction/2) ++
      optional(e, "mirror", path, &mirror_check/2) ++
      optional(e, "repeat", path, &repeat/2)
  end

  defp mirror_check(v, path) do
    planes = List.wrap(v)

    if planes != [] and planes == Enum.uniq(planes) and Enum.all?(planes, &(&1 in ~w(x y z))),
      do: [],
      else: [{path, "must be x, y or z, or a list of them, each once"}]
  end

  defp repeat(v, path) when is_map(v) do
    World.Skill.keys(v, path, ~w(count axis angle move center), ~w(count)) ++
      optional(v, "count", path, fn n, p ->
        if is_integer(n) and n >= 2 and n <= 1_000, do: [], else: [{p, "must be a count from 2 to 1000"}]
      end) ++
      optional(v, "axis", path, &direction/2) ++
      optional(v, "angle", path, &number(&1, &2, -360, 360)) ++
      optional(v, "move", path, &point/2) ++
      optional(v, "center", path, &point/2)
  end

  defp repeat(_v, path), do: [{path, "must be an object: count, and axis, angle, move, center"}]

  defp shape(%{"shape" => shape} = e, path) when is_map_key(@sizes, shape) or shape == "tube",
    do: optional(e, "size", path, &sizes(shape, &1, &2))

  defp shape(%{"shape" => _}, path),
    do: [{"#{path}.shape", "must be one of: #{Enum.join(Enum.sort(["tube", "group" | Map.keys(@sizes)]), ", ")}"}]

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

  defp color(v, path),
    do: if(is_binary(v) and v =~ ~r/^#[0-9a-fA-F]{6}$/, do: [], else: [{path, "must be a color #rrggbb"}])

  defp rgb("#" <> hex), do: for(<<c::binary-size(2) <- hex>>, do: String.to_integer(c, 16)) |> List.to_tuple()

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
