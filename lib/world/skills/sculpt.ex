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
  bricks of the edits (`World.Sculpt.model/2`) in its hand. The hand is
  a site: the workers of its crew do its jobs (`World.Crew`), and a stop
  of the person stops them at once (D4).

  With `bones`, the sculptor makes a figure in place of a part
  (`World.Sculpt.Bones`, plan 0009, D6): one skinned mesh that follows
  the bones. `bones` is a list of bones, parents first (each a `name`, a
  `head`, a `tail` and, but for the first, a `parent`); `bone_blend` the
  width of the blend of the weights of two bones (m); `plan` the name of
  a body plan, which gives its clips (`gait`: its numbers); `clips` a
  list of clips from keys (a `name`, a `length` and `keys`, each key a
  time `at` and a `pose`: a bone to its `flex`, `spread` and `twist` in
  degrees).
  """
  @behaviour World.Skill

  alias World.{Drawing, Frame, GLB, Part, Port, SDF, Vec}
  alias World.Sculpt.{Bones, Texture}

  @keys ~w(edits groups details ports sources budget cells bake look occlusion dirt wear bones bone_blend plan gait clips)
  @edit ~w(shape size at axis up mode blend blend_type opacity material color raise finish roughness metal glow surface mirror repeat)
  # The finishes with a name: a roughness and a metal.
  @finishes %{
    "plastic" => {0.4, 0.0},
    "shiny" => {0.15, 0.0},
    "rough" => {0.9, 0.0},
    "metal" => {0.4, 1.0},
    "shiny_metal" => {0.15, 1.0},
    "rough_metal" => {0.8, 1.0}
  }
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
    "superellipsoid" => 4,
    "wedge" => 3,
    "prism" => 3,
    "pyramid" => 3
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
      optional(data, "cells", path, &cells/2) ++
      optional(data, "details", path, &details(&1, &2, groups)) ++
      optional(data, "bake", path, &bake(&1, &2, data)) ++
      optional(data, "look", path, &choice(&1, &2, ~w(flat real))) ++
      optional(data, "occlusion", path, &flag/2) ++
      optional(data, "dirt", path, &number(&1, &2, 0, 1)) ++
      optional(data, "wear", path, &number(&1, &2, 0, 1)) ++
      optional(data, "bones", path, &bones/2) ++
      optional(data, "bone_blend", path, &number(&1, &2, 0.001, 10)) ++
      optional(data, "plan", path, &plan(&1, &2, data["bones"])) ++
      optional(data, "gait", path, &gait(&1, &2, data["plan"])) ++
      optional(data, "clips", path, &clips(&1, &2, data["bones"], data["plan"])) ++
      if Map.has_key?(data, "bones"),
        do: [],
        else: for(k <- ~w(bone_blend clips gait plan), Map.has_key?(data, k), do: {"#{path}.#{k}", "needs bones"})
  end

  def check(_data, path), do: [{path, "must be an object"}]

  @impl true
  def make(data, inputs, context), do: World.Sculpt.Gate.with(fn -> sculpture(data, inputs, context) end)

  # (In the gate of the node: a sculpture gives its work to each
  # scheduler, so only some sculptures work at one time.)
  defp sculpture(data, _inputs, %{level: level, name: name}) do
    # The flat look has no maps: flat faces, each with one color.
    flat? = data["look"] == "flat"
    side = if flat?, do: nil, else: get_in(data, ["bake", Atom.to_string(level)])

    # The sculpture, then each of its details at this level: each one is
    # a sculpture of its own, with its edits, its cells and its budget.
    built =
      for d <- [data | details(data, level)] do
        {edits, step} = {all(d), step(d, level)}
        # With maps, the mesh has no relief smaller than its cells: the maps have it.
        from = if side, do: SDF.coarse(edits, step), else: edits
        meshes = World.Sculpt.model(from, step: step, budget: get_in(d, ["budget", Atom.to_string(level)]))
        {if(flat?, do: Enum.map(meshes, &facets(&1, edits)), else: meshes), edits, step}
      end

    # (The images of the maps become PNG files in their own processes,
    # while this one makes the part or the figure.)
    # (A sculpture with no surface has no maps: a crop or a cut can take all of it away.)
    # (The look from the shape: the occlusion unless the data says no, the dirt and the wear.)
    look = %{
      occlusion: Map.get(data, "occlusion", true),
      dirt: Map.get(data, "dirt", 0.0) / 1,
      wear: Map.get(data, "wear", 0.0) / 1
    }

    {meshes, materials} = maps(built, if(Enum.any?(built, fn {ms, _, _} -> ms != [] end), do: side), look)
    ports = Drawing.ports(Map.get(data, "ports", %{}))
    sources = Map.get(data, "sources", [])

    made =
      case data["bones"] do
        nil ->
          Part.new(name, :part, meshes, ports, sources: sources)

        bones ->
          # The edits of each mesh: the bones of a point come from the edit of its surface.
          edits = for {ms, edits, _} <- built, _ <- ms, do: edits
          figure(name, meshes, bones, [ports: ports, sources: sources, edits: edits], data)
      end

    {made, materials.(), %{}}
  end

  # A mesh for the flat look (`"look": "flat"`; plan 0012, D5): each face
  # has its own three points, the normal of the face, and one color, the
  # color of the edits at its middle. So a face is flat in each light,
  # and the model needs no image.
  defp facets(%World.Mesh{points: points, faces: faces} = mesh, edits) do
    at = List.to_tuple(points)
    colors? = Enum.any?(edits, & &1.color)
    corners = for [a, b, c] <- faces, do: {elem(at, a), elem(at, b), elem(at, c)}

    colors =
      if colors? do
        for {p, q, r} <- corners,
            color = SDF.color(edits, Vec.scale(Vec.add(Vec.add(p, q), r), 1 / 3)),
            _ <- 1..3,
            do: color
      end

    %{
      mesh
      | points: for({p, q, r} <- corners, point <- [p, q, r], do: point),
        faces: for(i <- 0..(length(faces) - 1)//1, do: [3 * i, 3 * i + 1, 3 * i + 2]),
        normals: nil,
        colors: colors,
        angle: 0.0
    }
  end

  # With `bake` for the level: the meshes with their UVs, and the maps of
  # each of their materials (`World.Sculpt.Bake`) as the data of the node,
  # for the materials of the model (`World.Drawing.assemble/3`). The
  # check makes sure that the image has a place for the triangles of the
  # budget.
  defp maps(built, nil, _look), do: {Enum.flat_map(built, &elem(&1, 0)), fn -> %{} end}

  defp maps(built, side, look) do
    # The finish of each role of the palette, for an edit with no finish of its own.
    defaults =
      Map.new(GLB.palette(), fn {role, spec} -> {GLB.role(role), {spec["roughness"] / 1, spec["metalness"] / 1}} end)

    {meshes, maps} = World.Sculpt.Bake.maps(built, side, defaults, look)
    png = fn rows -> {"image/png", World.PNG.encode(rows, 3)} end

    # Each image becomes a PNG file in a process of its own; the function
    # waits for them.
    files =
      for {key, rows} <- [
            {"normal_image", maps.normal},
            {"image", maps.color},
            {"finish_image", maps.finish},
            {"glow_image", maps.glow}
          ],
          rows != nil,
          do: Task.async(fn -> {key, png.(rows)} end)

    {meshes,
     fn ->
       spec =
         files
         |> Task.await_many(:infinity)
         |> Map.new()
         |> Map.merge(%{"atlas" => true, "occlusion" => look.occlusion})

       %{"materials" => Map.new(meshes, &{Atom.to_string(&1.material), spec})}
     end}
  end

  # The details of a sculpture at a level, each as the data of a
  # sculpture (with the groups of the sculpture).
  defp details(data, level) do
    for d <- Map.get(data, "details", []), Atom.to_string(level) in Map.get(d, "levels", ~w(near mid far)) do
      Map.put(d, "groups", Map.get(data, "groups", %{}))
    end
  end

  # The figure of a sculpture with bones.
  defp figure(name, meshes, bones, opts, data) do
    point = fn [x, y, z] -> {x, y, z} end

    Bones.figure(
      name,
      meshes,
      for(b <- bones, do: %{name: b["name"], parent: b["parent"], head: point.(b["head"]), tail: point.(b["tail"])}),
      opts ++
        [
          plan: data["plan"],
          gait: Map.get(data, "gait", %{}),
          blend: data["bone_blend"],
          clips:
            for c <- Map.get(data, "clips", []) do
              %{name: c["name"], length: c["length"], keys: for(k <- c["keys"], do: {k["at"], k["pose"]})}
            end
        ]
    )
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

        %{
          s
          | frame: Frame.compose(place, at),
            size: scaled(s.shape, s.size, k),
            blend: s.blend * k,
            raise: s.raise * k,
            surface: s.surface && {elem(s.surface, 0), elem(s.surface, 1) * k}
        }
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
      hard: e["blend_type"] == "hard",
      opacity: Map.get(e, "opacity", 1) / 1,
      material: e["material"] && GLB.role(e["material"]),
      color: e["color"] && rgb(e["color"]),
      raise: Map.get(e, "raise", 0) / 1,
      # The finish of the edit: its own numbers, or the numbers of its finish with a name.
      roughness: e["roughness"] || elem(Map.get(@finishes, e["finish"], {nil, nil}), 0),
      metal: e["metal"] || elem(Map.get(@finishes, e["finish"], {nil, nil}), 1),
      glow: e["glow"],
      surface: surface(e["surface"])
    }

    for copy <- copies(e), do: copy.(spec)
  end

  defp to_edit(s), do: SDF.edit(s.shape, s.size, Keyword.new(Map.drop(s, [:shape, :size])))

  # The surface of an edit: the name of a kind (with the scale of the
  # kind), or a kind with a scale (m).
  defp surface(nil), do: nil
  defp surface(name) when is_binary(name), do: Texture.kind(name)

  defp surface(%{"kind" => name} = s),
    do: {elem(Texture.kind(name), 0), Map.get(s, "scale", elem(Texture.kind(name), 1)) / 1}

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
  defp scaled(:extrude, {points, h, r}, k), do: {for({x, y} <- points, do: {x * k, y * k}), h * k, r * k}
  defp scaled(:revolve, {points}, k), do: {for({x, y} <- points, do: {x * k, y * k})}
  defp scaled(:superellipsoid, {x, y, z, e}, k), do: {x * k, y * k, z * k, e}
  defp scaled(:prism, {r, h, n}, k), do: {r * k, h * k, n}
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
  # copy has the right hand again, so its x is the other way: most shapes
  # are the same across their x. The points of a tube and of the outline
  # of an extrude turn theirs. A prism with an odd count of sides is not
  # the same across its x, but it is across its y: its frame has its y the
  # other way.
  defp mirror(%{frame: f} = s, plane) do
    flip = fn {x, y, z} -> %{"x" => {-x, y, z}, "y" => {x, -y, z}, "z" => {x, y, -z}}[plane] end

    {size, up} =
      case {s.shape, s.size} do
        {:tube, {points, radii}} -> {{Enum.map(points, fn {x, y, z} -> {-x, y, z} end), radii}, flip.(f.y)}
        {:extrude, {points, h, r}} -> {{Enum.map(points, fn {x, y} -> {-x, y} end), h, r}, flip.(f.y)}
        {:prism, size} -> {size, Vec.scale(flip.(f.y), -1)}
        {_, size} -> {size, flip.(f.y)}
      end

    %{s | frame: Frame.new(flip.(f.at), flip.(f.z), up), size: size}
  end

  # The count of the plain edits of an edit of the data.
  defp count(e, groups) do
    base = if e["shape"] == "group", do: groups[e["group"]] |> Enum.map(&count(&1, %{})) |> Enum.sum(), else: 1
    base * (get_in(e, ["repeat", "count"]) || 1) * 2 ** length(List.wrap(e["mirror"]))
  end

  defp size("tube", %{"points" => points, "radii" => radii}), do: {Enum.map(points, &List.to_tuple/1), radii}

  # An outline with a depth: the half depth, and the radius of its edges.
  defp size("extrude", %{"outline" => points, "depth" => depth} = s),
    do: {curve(points, Map.get(s, "smooth", 0)), depth / 2, Map.get(s, "round", 0)}

  defp size("revolve", %{"profile" => points} = s), do: {curve(points, Map.get(s, "smooth", 0))}
  defp size(_shape, size), do: List.to_tuple(size)

  # The points of an outline, with its corners cut `times` times (each
  # side gives the points at a quarter and at three quarters of it): a
  # few points make a smooth curve.
  defp curve(points, 0), do: Enum.map(points, &List.to_tuple/1)

  defp curve(points, times) do
    cut =
      for {[ax, ay], [bx, by]} <- Enum.zip(points, tl(points) ++ [hd(points)]),
          p <- [[0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by], [0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by]],
          do: p

    curve(cut, times - 1)
  end

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
      optional(e, "mode", path, &choice(&1, &2, ~w(add subtract paint crop))) ++
      optional(e, "blend", path, &number(&1, &2, 0, 10)) ++
      optional(e, "blend_type", path, &choice(&1, &2, ~w(soft hard))) ++
      optional(e, "opacity", path, fn v, p ->
        cond do
          number(v, p, 0, 1) != [] -> number(v, p, 0, 1)
          e["mode"] != "paint" -> [{p, "is for an edit of the mode paint"}]
          true -> []
        end
      end) ++
      optional(e, "material", path, &choice(&1, &2, GLB.palette() |> Map.keys() |> Enum.sort())) ++
      optional(e, "color", path, &color/2) ++
      optional(e, "finish", path, &choice(&1, &2, @finishes |> Map.keys() |> Enum.sort())) ++
      optional(e, "roughness", path, &number(&1, &2, 0, 1)) ++
      optional(e, "metal", path, &number(&1, &2, 0, 1)) ++
      optional(e, "glow", path, &number(&1, &2, 0, 1)) ++
      optional(e, "surface", path, &surface/2) ++
      optional(e, "raise", path, &lift(&1, &2, e))
  end

  defp edit(_e, path, _groups), do: [{path, "must be an object"}]

  # The raise of an edit that paints: at most its blend, so the border
  # of the relief is a slope, not a step.
  defp lift(v, path, e) do
    blend = if is_number(e["blend"]), do: e["blend"], else: 0

    cond do
      number(v, path, -0.1, 0.1) != [] -> number(v, path, -0.1, 0.1)
      e["mode"] != "paint" -> [{path, "is for an edit of the mode paint"}]
      abs(v) > blend -> [{path, "must be at most the blend of the edit (#{blend})"}]
      true -> []
    end
  end

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

  defp shape(%{"shape" => shape} = e, path) when is_map_key(@sizes, shape) or shape in ~w(tube extrude revolve),
    do: optional(e, "size", path, &sizes(shape, &1, &2))

  defp shape(%{"shape" => _}, path) do
    names = Enum.sort(~w(tube extrude revolve group) ++ Map.keys(@sizes))
    [{"#{path}.shape", "must be one of: #{Enum.join(names, ", ")}"}]
  end

  defp shape(_e, _path), do: []

  defp sizes("tube", %{"points" => points, "radii" => radii}, path)
       when is_list(points) and is_list(radii) and length(points) in 2..256 and length(points) == length(radii) do
    errors =
      (points |> Enum.with_index() |> Enum.flat_map(fn {p, i} -> point(p, "#{path}.points.#{i}") end)) ++
        (radii |> Enum.with_index() |> Enum.flat_map(fn {r, i} -> number(r, "#{path}.radii.#{i}", 0.0001, @size) end))

    if errors == [], do: twins(points, "#{path}.points"), else: errors
  end

  defp sizes("tube", _v, path),
    do: [{path, "must be {\"points\": [[x, y, z], ...], \"radii\": [r, ...]}: 2 to 256 points, a radius for each"}]

  defp sizes("extrude", %{"outline" => points, "depth" => depth} = v, path) when is_list(points) do
    World.Skill.keys(v, path, ~w(outline depth round smooth), ~w(outline depth)) ++
      outline(points, "#{path}.outline", -@size) ++
      number(depth, "#{path}.depth", 0.0002, @size) ++
      optional(v, "smooth", path, &whole(&1, &2, 0, 3)) ++
      optional(v, "round", path, fn r, at ->
        if is_number(r) and is_number(depth) and r >= 0 and r <= depth / 2,
          do: [],
          else: [{at, "must be a radius from 0 to half of the depth"}]
      end)
  end

  defp sizes("extrude", _v, path),
    do: [{path, "must be {\"outline\": [[x, y], ...], \"depth\": d}: 3 to 256 points; and round, smooth"}]

  # (The profile is on one side of the axis: no r less than 0.)
  defp sizes("revolve", %{"profile" => points} = v, path) when is_list(points) do
    World.Skill.keys(v, path, ~w(profile smooth), ~w(profile)) ++
      outline(points, "#{path}.profile", 0) ++ optional(v, "smooth", path, &whole(&1, &2, 0, 3))
  end

  defp sizes("revolve", _v, path),
    do: [{path, "must be {\"profile\": [[r, z], ...]}: 3 to 256 points, each r of 0 or more; and smooth"}]

  defp sizes(shape, v, path) do
    n = @sizes[shape]

    if is_list(v) and length(v) == n and Enum.all?(v, &(is_number(&1) and &1 >= 0 and &1 <= @size)) do
      extra(shape, v, path)
    else
      [{path, "must be a list of #{n} sizes in meters, from 0 to #{@size} m (docs/format.md, \"A sculpture\")"}]
    end
  end

  # Two points of a tube next to each other are not at one place: a cone between them needs a length.
  defp twins(points, path) do
    for {[a, b], i} <- points |> Enum.chunk_every(2, 1, :discard) |> Enum.with_index(1),
        Enum.map(a, &(&1 / 1)) == Enum.map(b, &(&1 / 1)),
        do: {"#{path}.#{i}", "must not be at the place of the point before it"}
  end

  # The points of an outline: 3 to 256 points of two numbers, the first from `least`.
  defp outline(points, path, least) when length(points) in 3..256 do
    points
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {[a, b], _} when is_number(a) and is_number(b) and a >= least and a <= @size and abs(b) <= @size -> []
      {_, i} -> [{"#{path}.#{i}", "must be two numbers in meters (the first from #{least}), at most #{@size} m"}]
    end)
  end

  defp outline(_points, path, _least), do: [{path, "must be a list of 3 to 256 points"}]

  defp whole(v, path, lo, hi),
    do: if(is_integer(v) and v >= lo and v <= hi, do: [], else: [{path, "must be a whole number from #{lo} to #{hi}"}])

  # The rules of the sizes of some shapes.
  defp extra("round_box", [x, y, z, r], path) do
    if r <= Enum.min([x, y, z]), do: [], else: [{path, "the radius of the edges must be at most the least half size"}]
  end

  defp extra("superellipsoid", [_, _, _, e], path) do
    if e >= 2 and e <= 64, do: [], else: [{path, "the power must be from 2 to 64"}]
  end

  defp extra("prism", [_, _, n], path) do
    if n == round(n) and n >= 3 and n <= 12, do: [], else: [{"#{path}.2", "must be a count of sides from 3 to 12"}]
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

  defp surface(name, path) when is_binary(name), do: choice(name, path, Texture.kinds())

  defp surface(%{"kind" => name} = s, path) when is_binary(name),
    do:
      choice(name, "#{path}.kind", Texture.kinds()) ++
        optional(s, "scale", path, &number(&1, &2, 0.0005, 10)) ++
        for(k <- Map.keys(s) -- ~w(kind scale), do: {"#{path}.#{k}", "is not a word of a surface"})

  defp surface(_v, path), do: [{path, "must be the name of a kind, or an object with a kind and a scale"}]

  defp flag(v, _path) when is_boolean(v), do: []
  defp flag(_v, path), do: [{path, "must be true or false"}]

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

  # The side of the image of the maps at each level: a power of 2, with
  # a place for the triangles of the budget of the level.
  defp bake(v, path, data) when is_map(v) do
    World.Skill.keys(v, path, ~w(near mid far)) ++
      for {k, n} <- Enum.sort(v), k in ~w(near mid far), e <- side(n, "#{path}.#{k}", triangles(data, k)), do: e
  end

  defp bake(_v, path, _data), do: [{path, "must be an object of near, mid and far"}]

  # The budget of a level with its details: a count, or nil when the
  # sculpture or one of its details at the level has none.
  defp triangles(data, level) do
    details = if is_list(data["details"]), do: Enum.filter(data["details"], &is_map/1), else: []
    here = for d <- details, level in if(is_list(d["levels"]), do: d["levels"], else: ~w(near mid far)), do: d
    budgets = for d <- [data | here], do: is_map(d["budget"]) && d["budget"][level]
    if Enum.all?(budgets, &is_integer/1), do: Enum.sum(budgets)
  end

  # The details: each one a sculpture of its own.
  defp details(v, path, groups) when is_list(v) and length(v) <= 16 do
    v
    |> Enum.with_index()
    |> Enum.flat_map(fn {d, i} ->
      p = "#{path}.#{i}"

      if is_map(d) do
        World.Skill.keys(d, p, ~w(edits cells budget levels), ~w(edits)) ++
          optional(d, "edits", p, &edits(&1, &2, groups)) ++
          optional(d, "cells", p, &cells/2) ++
          optional(d, "budget", p, &budget/2) ++
          optional(d, "levels", p, fn l, lp ->
            if is_list(l) and l != [] and l -- ~w(near mid far) == [] and l == Enum.uniq(l),
              do: [],
              else: [{lp, "must be a list of near, mid and far"}]
          end)
      else
        [{p, "must be an object"}]
      end
    end)
  end

  defp details(_v, path, _groups), do: [{path, "must be a list of at most 16 details"}]

  defp side(n, path, budget) do
    cond do
      n not in [64, 128, 256, 512, 1024, 2048, 4096] ->
        [{path, "must be a side of an image: 64, 128, 256, 512, 1024, 2048 or 4096"}]

      not is_integer(budget) ->
        [{path, "needs a budget at this level, for the sculpture and for each of its details"}]

      n < World.Sculpt.Bake.least(budget) ->
        [{path, "is too small for the budget: #{World.Sculpt.Bake.least(budget)} texels or more"}]

      true ->
        []
    end
  end

  # The bones: parents first, the first is the root.
  defp bones(v, path) when is_list(v) and v != [] and length(v) <= 64 do
    {errors, _} =
      v
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {b, i}, {errors, names} ->
        {errors ++ bone(b, "#{path}.#{i}", names),
         if(is_map(b) and is_binary(b["name"]), do: [b["name"] | names], else: names)}
      end)

    errors
  end

  defp bones(_v, path), do: [{path, "must be a list of 1 to 64 bones"}]

  defp bone(b, path, names) when is_map(b) do
    name =
      cond do
        not (is_binary(b["name"]) and b["name"] =~ ~r/^[a-z][a-z0-9_]{0,31}$/) ->
          [{"#{path}.name", "must be a name of small letters, digits and _"}]

        b["name"] in names ->
          [{"#{path}.name", "is the name of a bone before it"}]

        true ->
          []
      end

    parent =
      cond do
        names == [] and Map.has_key?(b, "parent") ->
          [{"#{path}.parent", "the first bone is the root: it has no parent"}]

        names == [] or b["parent"] in names ->
          []

        true ->
          [{"#{path}.parent", "must be the name of a bone before it"}]
      end

    ends = Enum.flat_map(~w(head tail), &point(b[&1], "#{path}.#{&1}"))
    short = if ends == [] and b["head"] == b["tail"], do: [{"#{path}.tail", "must not be the head"}], else: []
    World.Skill.keys(b, path, ~w(name parent head tail), ~w(name head tail)) ++ name ++ parent ++ ends ++ short
  end

  defp bone(_b, path, _names), do: [{path, "must be an object"}]

  defp names(bones), do: if(is_list(bones), do: for(%{"name" => n} <- bones, do: n), else: [])

  # The body plan: its name, and each of its bones in the bones.
  defp plan(v, path, bones) do
    with [] <- choice(v, path, Bones.plans()),
         [] <- if(is_list(bones), do: Bones.bones(v) -- names(bones), else: []) do
      []
    else
      [{_, _} | _] = errors -> errors
      missing -> [{path, "needs the bones: #{Enum.join(missing, ", ")}"}]
    end
  end

  defp gait(v, path, plan) when is_map(v) and is_binary(plan) do
    World.Skill.keys(v, path, ~w(period stride lift)) ++
      optional(v, "period", path, &number(&1, &2, 0.1, 10)) ++
      optional(v, "stride", path, &number(&1, &2, 0, 5)) ++ optional(v, "lift", path, &number(&1, &2, 0, 1))
  end

  defp gait(_v, path, _plan), do: [{path, "must be an object of period, stride and lift, with a plan"}]

  # The clips from keys.
  defp clips(v, path, bones, plan) when is_list(v) and length(v) <= 16 do
    bones = names(bones)
    errors = v |> Enum.with_index() |> Enum.flat_map(fn {c, i} -> clip(c, "#{path}.#{i}", bones) end)
    # The names of the clips with the names of the animations of the plan: each one time.
    names = for(%{"name" => n} <- v, do: n) ++ if(plan in Bones.plans(), do: Bones.animations(plan), else: [])
    if errors == [] and names != Enum.uniq(names), do: [{path, "has two clips of one name"}], else: errors
  end

  defp clips(_v, path, _bones, _plan), do: [{path, "must be a list of at most 16 clips"}]

  defp clip(c, path, bones) when is_map(c) do
    # The keys of a clip with a wrong length are checked to the longest length.
    length = if number(c["length"], path, 0.1, 60) == [], do: c["length"], else: 60

    World.Skill.keys(c, path, ~w(name length keys), ~w(name length keys)) ++
      optional(c, "name", path, fn v, p ->
        if is_binary(v) and v =~ ~r/^[a-z][a-z0-9_]{0,31}$/,
          do: [],
          else: [{p, "must be a name of small letters, digits and _"}]
      end) ++
      optional(c, "length", path, &number(&1, &2, 0.1, 60)) ++
      optional(c, "keys", path, fn v, p ->
        if is_list(v) and v != [] and length(v) <= 64,
          do: v |> Enum.with_index() |> Enum.flat_map(fn {k, i} -> key(k, "#{p}.#{i}", length, bones) end),
          else: [{p, "must be a list of 1 to 64 keys"}]
      end)
  end

  defp clip(_c, path, _bones), do: [{path, "must be an object"}]

  defp key(k, path, length, bones) when is_map(k) do
    World.Skill.keys(k, path, ~w(at pose), ~w(at pose)) ++
      optional(k, "at", path, &number(&1, &2, 0, length)) ++
      optional(k, "pose", path, fn v, p ->
        if is_map(v),
          do: Enum.flat_map(Enum.sort(v), fn {bone, turns} -> turns(bone, turns, "#{p}.#{bone}", bones) end),
          else: [{p, "must be an object: a bone to its turns"}]
      end)
  end

  defp key(_k, path, _length, _bones), do: [{path, "must be an object"}]

  defp turns(bone, turns, path, bones) do
    cond do
      bone not in bones ->
        [{path, "is not a bone of the sculpture"}]

      not is_map(turns) ->
        [{path, "must be an object of #{Enum.join(Bones.turns(), ", ")}"}]

      true ->
        World.Skill.keys(turns, path, Bones.turns()) ++
          for {k, v} <- Enum.sort(turns), k in Bones.turns(), e <- number(v, "#{path}.#{k}", -180, 180), do: e
    end
  end
end
