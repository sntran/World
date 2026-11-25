defmodule World.Skills.Sculpt do
  @moduledoc """
  The skill `sculpt` of a sculptor (`docs/plans/0008-model-from-edits.md`,
  D9): a part from a list of edits (`docs/format.md`, "A sculpture").

  Its data: `edits` (a list of 1 to 10,000 edits: each with its `shape`
  and its `size`, and `at`, `axis`, `up`, `mode`, `blend`, `material`,
  `color`, its copies: `mirror` and `repeat`, and its `levels`), `groups`
  (a name to a list of edits, that an edit of the shape `group` uses at a
  place and a `scale`; an edit in a group and an edit of the shape
  `group` can have `levels` too),
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

  # The factor of the color of a material whose image or points have the color.
  @white %{"color" => [255, 255, 255]}
  @keys ~w(edits groups details ports sources budget cells bake mipmaps solids look occlusion dirt wear strands bones bone_blend plan gait clips)
  @edit ~w(shape size at axis up mode blend blend_type opacity material color raise finish roughness metal glow surface mirror repeat levels)
  # The finishes with a name: a roughness and a metal.
  @finishes %{
    "plastic" => {0.4, 0.0},
    "shiny" => {0.15, 0.0},
    "rough" => {0.9, 0.0},
    "metal" => {0.4, 1.0},
    "shiny_metal" => {0.15, 1.0},
    "rough_metal" => {0.8, 1.0}
  }
  @use ~w(shape group at axis up scale mirror repeat levels)
  @most 10_000
  # The most times that a sculpture over its budget is made again with larger cells (`in_budget/4`).
  @tries 6

  # The most texels on a side of the maps of a part of a large sculpture (`tiles/4`).
  @tile_side 512
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
      optional(data, "edits", path, &checked(&1, &2, groups)) ++
      optional(data, "ports", path, &Drawing.check_ports/2) ++
      optional(data, "sources", path, &sources/2) ++
      optional(data, "budget", path, &budget/2) ++
      optional(data, "cells", path, &cells/2) ++
      optional(data, "details", path, &details(&1, &2, groups)) ++
      optional(data, "bake", path, &bake(&1, &2, data)) ++
      optional(data, "mipmaps", path, &flag/2) ++
      optional(data, "solids", path, &solids(&1, &2, data, groups)) ++
      optional(data, "look", path, &choice(&1, &2, ~w(flat real))) ++
      optional(data, "occlusion", path, &choice(&1, &2, [true, false, "alpha", "color"])) ++
      optional(data, "dirt", path, &number(&1, &2, 0, 1)) ++
      optional(data, "wear", path, &number(&1, &2, 0, 1)) ++
      optional(data, "strands", path, &strands(&1, &2, groups)) ++
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

  @doc """
  The parts of a sculpture at a level (`World.Elements`, W26): nil when
  the sculpture is one part made at one time, else a list of tiles. A
  tile is a part of its own (`tile/4` makes it); it can be made in some
  steps, each in a process of its own, so that no process holds more
  than `most` faces (`World.Sculpt.model_in_steps/2`).

  The surface of the sculpture comes first, in bricks of larger cells
  (4 times the cells up to 12.5 cm, 2 times up to 25 cm; much less
  work): the faces of each brick, with the faces of each large edit
  thinner than those cells (they lose its surface), an estimate of the faces at the cells
  of the level. A box of bricks is cut in two on its longest axis, again
  and again: into steps of at most `most` faces, and into tiles with a
  budget of `least` triangles or more (the budget of the level in the
  share of the faces of the tile: a part with a small budget has most
  of its points at its borders, and no good shape). A cut is a plane
  between bricks that leaves a quarter of the faces or more on each
  side, and that crosses the fewest soft blends of the edits (an edit
  with a `blend`): a blend in one tile is the blend of one part. Of
  those, the plane nearest to the middle of the faces (with no such
  plane: the plane nearest to the middle of the faces).

  Each tile has its box (m; an outer side of the box goes to the end of
  the space), its share of the faces (a power of 2^(1/4): so an edit in
  one tile changes the budget and the maps of the other tiles only
  seldom, and their keys stay, W27), its faces, and its steps (each a
  box and its share of the faces of the tile). With no budget, each step
  is a tile. A sculpture with bones is one part.
  """
  def tiles(data, level, most, least \\ 1500) do
    with nil <- data["bones"],
         step = step(data, level),
         k = estimate_factor(step),
         edits = all(data, level),
         %{bricks: bricks} <- World.Sculpt.bricks(edits, k * step, each: &brick_faces(&1, k * step), fields: false),
         counts = bricks |> Map.new(&{&1.at, k * k * &1.piece}) |> thin_faces(edits, step, k),
         true <- map_size(counts) >= 2,
         total when total > most <- counts |> Map.values() |> Enum.sum() do
      {lo, hi} = counts |> Map.keys() |> Vec.bounds()
      outer = {lo, Vec.add(hi, {1, 1, 1})}
      size = World.Sculpt.cells() * k * step
      blends = for %{blend: b, box: {l, h}} <- edits, b > 0, do: {Vec.sub(l, {b, b, b}), Vec.add(h, {b, b, b})}
      budget = get_in(data, ["budget", Atom.to_string(level)])
      # The faces of a tile: twice the faces of `least` triangles of the budget, and not less than a step.
      part = if budget, do: max(most, round(2 * least * total / budget)), else: most
      share = fn n -> :math.pow(2, Float.round(4 * :math.log2(max(n, 1) / total)) / 4) end
      box = fn {blo, bhi} -> {meters(blo, elem(outer, 0), size, -1), meters(bhi, elem(outer, 1), size, 1)} end

      for {b, i} <- counts |> cut(outer, part, blends, size) |> Enum.with_index() do
        n = in_box(counts, b)
        steps = for s <- cut(counts, b, most, blends, size), do: {box.(s), in_box(counts, s) / max(n, 1)}
        %{index: i, box: box.(b), share: share.(n), faces: n, steps: steps}
      end
    else
      _ -> nil
    end
  end

  @doc """
  Make one tile of a sculpture (`tiles/3`): `{part, data}` as `make/3`,
  the part with the name `NAME_I` (I: the index of the tile) and the
  meshes of the bricks in the box of the tile, whose points at the
  border of the tile stay where they are (`World.Sculpt.model/2`). The
  data has the maps of the tile.
  """
  def tile(data, tile, inputs, context) do
    context = Map.merge(context, %{name: "#{context.name}_#{tile.index}", tile: tile})
    {part, more, _} = make(data, inputs, context)
    {part, more}
  end

  @doc """
  The data of a tile for its key (`World.Elements`): its box, its share,
  its steps, and the edits of the sculpture and of each detail that can change the
  field in the box, with the data of the sculpture that is not edits.
  An edit far from the tile is not in it: its change does not change
  the key.
  """
  def tile_key(data, tile, level) do
    rest = Map.drop(data, ~w(edits groups details))

    lists =
      for d <- [data | details(data, level)] do
        {edits, step} = {all(d, level), step(d, level)}
        {step, near_tile(edits, tile.box, step)}
      end

    {rest, tile.box, tile.share, tile.steps, lists}
  end

  # The cells of the estimate of the tiles: k times the cells of the
  # level (a brick of the estimate is k³ bricks of the level).
  defp estimate_factor(step) when step <= 0.125, do: 4
  defp estimate_factor(step) when step <= 0.25, do: 2
  defp estimate_factor(_step), do: 1

  # The faces of each edit that adds, is 1 m or more long, and is thinner
  # than the cells of the estimate (a slab of a base, a pane): in those
  # cells its surface goes away. Its faces at the cells of the level (two
  # sides of the two longest sides of its box, two triangles for each
  # cell) go to the bricks of the
  # estimate that its box crosses, in equal parts (a brick keeps its own
  # count when that is more: then its cells have the surface).
  defp thin_faces(counts, edits, step, k) do
    size = World.Sculpt.cells() * k * step

    for %{mode: :add, box: {lo, hi}} = e <- edits,
        Vec.len(Vec.sub(hi, lo)) >= 1.0,
        World.Sculpt.thinnest([e], 0.0) < k * step,
        reduce: counts do
      counts ->
        [_, b, c] = hi |> Vec.sub(lo) |> Tuple.to_list() |> Enum.sort()
        index = fn {x, y, z} -> {floor(x / size), floor(y / size), floor(z / size)} end
        {{i0, j0, l0}, {i1, j1, l1}} = {index.(lo), index.(hi)}
        at = for i <- i0..i1, j <- j0..j1, l <- l0..l1, do: {i, j, l}
        share = round(4 * b * c / (step * step) / length(at))
        Enum.reduce(at, counts, &Map.update(&2, &1, share, fn n -> max(n, share) end))
    end
  end

  @doc """
  An estimate of the faces of a sculpture at a level before the
  collapse to its budget (two faces for each cell of the surface of the
  box of its edits, a bit less for a round shape): the work and the
  memory of one build.
  """
  def faces(data, level) do
    if solids?(data, level), do: World.Sculpt.Solids.count(all(data, level)), else: field_faces(data, level)
  end

  defp field_faces(data, level) do
    case SDF.bounds(all(data, level)) do
      {{x0, y0, z0}, {x1, y1, z1}} ->
        {a, b, c} = {x1 - x0, y1 - y0, z1 - z0}
        step = step(data, level)
        round(1.4 * (a * b + b * c + c * a) / (step * step))

      nil ->
        0
    end
  end

  @doc "The roles of the meshes of a sculpture at a level: the material of each edit (`paint` with none)."
  def roles(data, level) do
    for d <- [data | details(data, level)], e <- all(d, level), uniq: true, do: to_string(e.material || :paint)
  end

  # The faces of a brick at cells of `step` (the piece of the surface,
  # two faces for each quad).
  defp brick_faces(brick, step), do: div(byte_size(World.Sculpt.Surface.piece(brick, step).quads), 17) * 2

  # The faces of the bricks in a box of bricks.
  defp in_box(counts, {{lx, ly, lz}, {hx, hy, hz}}) do
    for {{x, y, z}, n} <- counts, x >= lx and x < hx and y >= ly and y < hy and z >= lz and z < hz, reduce: 0 do
      sum -> sum + n
    end
  end

  # The boxes of bricks (from lo, up to hi) with at most `most` faces
  # each. A cut is a plane between bricks on any axis: a plane that
  # leaves a quarter of the faces or more on each side (the fewest blends
  # that it crosses, then the nearest to the middle, then on the longest
  # axis), else the plane nearest to the middle of the faces.
  defp cut(counts, {lo, hi} = box, most, blends, size) do
    total = in_box(counts, box)
    axes = for a <- 0..2, elem(hi, a) - elem(lo, a) >= 2, do: a

    if total <= most or axes == [] do
      [box]
    else
      plans =
        for a <- axes, at <- (elem(lo, a) + 1)..(elem(hi, a) - 1) do
          left = in_box(counts, {lo, put_elem(hi, a, at)})
          plane = at * size
          crossed = Enum.count(blends, fn {l, h} -> elem(l, a) < plane and elem(h, a) > plane end)
          {a, at, left / total, crossed, elem(lo, a) - elem(hi, a)}
        end

      {a, at, _, _, _} =
        case Enum.filter(plans, fn {_, _, share, _, _} -> share >= 0.25 and share <= 0.75 end) do
          [] -> Enum.min_by(plans, fn {_, _, share, _, long} -> {abs(share - 0.5), long} end)
          fair -> Enum.min_by(fair, fn {_, _, share, n, long} -> {n, abs(share - 0.5), long} end)
        end

      cut(counts, {lo, put_elem(hi, a, at)}, most, blends, size) ++
        cut(counts, {put_elem(lo, a, at), hi}, most, blends, size)
    end
  end

  # The side of a box of bricks in m: an outer side goes to the end of the space.
  defp meters(corner, outer, size, sign) do
    corner
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(outer))
    |> Enum.map(fn {c, o} -> if c == o, do: sign * 1.0e6, else: c * size end)
    |> List.to_tuple()
  end

  # The edits that can change the field in the box of a tile: each edit
  # whose box, grown by its blend, by the limit of the field and by two
  # cells, meets the box of the tile; and each crop (it takes away all
  # that is out of it). In their order.
  defp near_tile(edits, {{lx, ly, lz}, {hx, hy, hz}}, step) do
    reach = World.Sculpt.limit(edits, step) + 2 * step

    for %{box: {{x0, y0, z0}, {x1, y1, z1}}} = e <- edits,
        r = reach + e.blend,
        e.mode == :crop or
          (x0 - r < hx and x1 + r > lx and y0 - r < hy and y1 + r > ly and z0 - r < hz and z1 + r > lz),
        do: e
  end

  # (In the gate of the node: a sculpture gives its work to each
  # scheduler, so only some sculptures work at one time.)
  defp sculpture(data, _inputs, %{level: level, name: name} = context) do
    tile = context[:tile]
    # The flat look has no maps: flat faces, each with one color.
    flat? = data["look"] == "flat"
    side = if flat?, do: nil, else: tile_side(get_in(data, ["bake", Atom.to_string(level)]), tile)

    # The sculpture, then each of its details at this level: each one is
    # a sculpture of its own, with its edits, its cells and its budget.
    # A tile has the edits near its box, the bricks in its box and its
    # part of each budget.
    built =
      for d <- [data | details(data, level)] do
        {edits, step} = {all(d, level), step(d, level)}
        edits = if tile, do: near_tile(edits, tile.box, step), else: edits
        budget = get_in(d, ["budget", Atom.to_string(level)])
        budget = if tile && budget, do: max(round(budget * tile.share), 12), else: budget
        # With maps, the mesh has no relief smaller than its cells: the maps have it. With no maps, the
        # cut keeps the borders of the finish and of the glow (plan 0020, D7); with maps, the maps have
        # them, and the cut stays as it was.
        # (With no maps, a surface of a made thing gives its look to the points: plan 0020, D11.)
        from = fn step -> if side, do: SDF.coarse(edits, step), else: SDF.on_points(edits, step) end
        pins = side == nil

        {meshes, step} =
          cond do
            edits == [] ->
              {[], step}

            # (The sculpture of a tile in steps: the details are small, in one step.)
            tile && d == data && length(tile.steps) > 1 ->
              {World.Sculpt.model_in_steps(from.(step),
                 step: step,
                 budget: budget,
                 within: tile.box,
                 steps: tile.steps,
                 finish_pins: pins
               ), step}

            # (A tile keeps its cells: its borders meet the cells of the next tiles.)
            tile ->
              {World.Sculpt.model(from.(step), step: step, budget: budget, within: tile.box, finish_pins: pins), step}

            # (The solids of the edits: each outline with straight edges, `World.Sculpt.Solids`.)
            solids?(d, level) ->
              {World.Sculpt.Solids.meshes(edits), step}

            true ->
              in_budget(
                &World.Sculpt.model(from.(&1), step: &1, budget: budget, finish_pins: pins),
                step,
                budget,
                if(pins, do: lit(edits))
              )
          end

        edits = if side, do: edits, else: SDF.on_points(edits, step)
        # (A solid has the color of its edit on each of its faces.)
        {if(flat? and not solids?(d, level), do: Enum.map(meshes, &facets(&1, edits)), else: meshes), edits, step}
      end

    # (The images of the maps become PNG files in their own processes,
    # while this one makes the part or the figure.)
    # (A sculpture with no surface has no maps: a crop or a cut can take all of it away.)
    # (The look from the shape: the occlusion unless the data says no, the dirt and the wear. At a
    # level with a budget and no maps, the look of each point, with the occlusion in the alpha of its
    # color or in its color: plan 0020, D5.)
    occlusion = Map.get(data, "occlusion", true)

    look = %{
      occlusion: occlusion != false,
      into: if(occlusion == "color", do: :color, else: :alpha),
      # (A sculpture with bones is a figure: its colors go through the rig, with no alpha and no finish.)
      points: not flat? and data["bones"] == nil and get_in(data, ["budget", Atom.to_string(level)]) != nil,
      mipmaps: data["mipmaps"] == true,
      dirt: Map.get(data, "dirt", 0.0) / 1,
      wear: Map.get(data, "wear", 0.0) / 1,
      # (Strands: the shapes where the hair is thin, as edits.)
      strands:
        side && data["strands"] && %{thin: edits(Map.get(data["strands"], "thin", []), Map.get(data, "groups", %{}))}
    }

    {meshes, materials} = maps(built, if(Enum.any?(built, fn {ms, _, _} -> ms != [] end), do: side), look)
    meshes = if look.strands, do: shells(meshes, data["strands"], level), else: meshes
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

  # The meshes of a sculpture in its budget, and their cells: the
  # collapse stops above the budget when no collapse keeps the mesh closed
  # (a thin ring, a small part of many materials). Then the meshes again,
  # with cells 1.5 times as large, at most #{@tries} times. When the
  # larger cells lose each point of the lights of the edits (a lamp in a
  # recess that the cells close), four cells between the two are tried,
  # and the meshes in the budget with the most points of light are taken
  # (plan 0020, D7).
  defp in_budget(model, step, budget, lit, n \\ 0, over \\ nil) do
    meshes = model.(step)

    cond do
      budget && n < @tries && count(meshes) > budget -> in_budget(model, 1.5 * step, budget, lit, n + 1, step)
      over && lit && lit.(meshes) == 0 -> between(model, over, step, budget, lit, {meshes, step})
      true -> {meshes, step}
    end
  end

  defp between(model, over, step, budget, lit, found) do
    tries =
      for k <- 1..4,
          cells = over * :math.pow(step / over, k / 5),
          meshes = model.(cells),
          count(meshes) <= budget,
          points = lit.(meshes),
          points > 0,
          do: {points, -cells, meshes}

    case Enum.max(tries, fn -> nil end) do
      nil -> found
      {_, cells, meshes} -> {meshes, -cells}
    end
  end

  defp count(meshes), do: meshes |> Enum.map(&length(&1.faces)) |> Enum.sum()

  # The count of the points of the meshes where an edit glows, or nil when no edit glows.
  defp lit(edits) do
    if Enum.any?(edits, &((&1.glow || 0.0) > 0.0)),
      do: fn meshes -> Enum.count(for(m <- meshes, p <- m.points, do: p), &(elem(SDF.finish(edits, &1), 2) > 0.0)) end
  end

  # A mesh for the flat look (`"look": "flat"`; plan 0012, D5): each face
  # has its own three points, the normal of the face, and one color, the
  # color of the edits at its middle. So a face is flat in each light,
  # and the model needs no image.
  defp facets(%World.Mesh{points: points, faces: faces} = mesh, edits) do
    at = List.to_tuple(points)
    colors? = Enum.any?(edits, & &1.color) or SDF.made?(edits)
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

  # The finish of each role of the palette, for an edit with no finish of its own.
  defp finishes,
    do: Map.new(GLB.palette(), fn {role, spec} -> {GLB.role(role), {spec["roughness"] / 1, spec["metalness"] / 1}} end)

  # The side of the maps of a tile: at most the texels on each m² of the
  # maps of all of the sculpture (a power of 2, from 64 to #{512}: the bake
  # of 1,024 × 1,024 texels takes about 150 MB, more than the edge has).
  defp tile_side(side, nil), do: side
  defp tile_side(nil, _tile), do: nil

  defp tile_side(side, tile),
    do: min(min(side, @tile_side), max(64, round(:math.pow(2, floor(:math.log2(side * :math.sqrt(tile.share)))))))

  # With `bake` for the level: the meshes with their UVs, and the maps of
  # each of their materials (`World.Sculpt.Bake`) as the data of the node,
  # for the materials of the model (`World.Drawing.assemble/3`). The
  # check makes sure that the image has a place for the triangles of the
  # budget.
  defp maps(built, nil, %{points: true} = look) do
    defaults = finishes()

    meshes = for {ms, edits, step} <- built, m <- World.Sculpt.Shade.meshes(ms, edits, step, defaults, look), do: m
    {meshes, fn -> white(meshes) end}
  end

  defp maps(built, nil, _look) do
    meshes = Enum.flat_map(built, &elem(&1, 0))
    {meshes, fn -> white(meshes) end}
  end

  defp maps(built, side, look) do
    defaults = finishes()

    # (The bake in a process of its own, which sweeps its garbage often: a
    # bake makes much garbage, and only its meshes and images come back.)
    {meshes, maps} = World.Detail.apart(fn -> World.Sculpt.Bake.maps(built, side, defaults, look) end, sweep: 2)
    png = fn rows, channels -> {"image/png", World.PNG.encode(rows, channels)} end

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
          # (With strands, the image of the colors has the cover of each place as its alpha.)
          channels = if(key == "image" and maps.alpha, do: 4, else: 3),
          do: Task.async(fn -> {key, png.(rows, channels)} end)

    {meshes,
     fn ->
       spec =
         files
         |> Task.await_many(:infinity)
         |> Map.new()
         |> Map.merge(%{"atlas" => true, "occlusion" => look.occlusion})
         # (The image has the color: the factor is white.)
         |> Map.merge(@white)
         |> Map.merge(if(look.mipmaps, do: %{"mipmaps" => true}, else: %{}))
         |> Map.merge(if(maps.alpha, do: %{"alpha_mode" => "MASK", "double_sided" => true}, else: %{}))

       %{"materials" => Map.new(meshes, &{Atom.to_string(&1.material), spec})}
     end}
  end

  # The color of a sculpture is at the points of its meshes (or in its image): the factor of the color of
  # each of their materials is white, not the color of the role in the palette, which would multiply the
  # color a second time.
  defp white(meshes),
    do: %{"materials" => Map.new(for(m <- meshes, m.colors != nil, do: {Atom.to_string(m.material), @white}))}

  # The shells of a sculpture with strands: copies of each mesh, out
  # along its normals, each with less alpha at its points. The alpha of
  # the image is the height of the strand of a place, so a shell shows
  # only the strands that are higher than its part of the way out: single
  # strands at the outline and at the line of the hair. All the shells at
  # near, one at mid, none at far.
  defp shells(meshes, strands, level) do
    count = %{near: Map.get(strands, "shells", 3), mid: 1, far: 0}[level]
    long = Map.get(strands, "length", 0.006) / 1

    meshes ++
      for k <- 1..count//1, m <- meshes do
        out = long * k / count
        # The shell shows a strand that is higher than this part.
        alpha = 0.5 / (0.5 + 0.5 * (k / (count + 1) + 0.05))

        %{
          m
          | points: for({p, n} <- Enum.zip(m.points, m.normals), do: Vec.add(p, Vec.scale(n, out))),
            colors: List.duplicate({255, 255, 255, alpha}, length(m.points))
        }
      end
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

  @doc "The limit of a point and of a size of an edit, in meters: also the limit of the place of a node of a drawing."
  def size, do: @size

  @impl true
  def estimate(data, level) do
    with [] <- check(data, ""),
         {{x0, y0, z0}, {x1, y1, z1}} <- SDF.bounds(all(data, level)) do
      {a, b, c} = {x1 - x0, y1 - y0, z1 - z0}
      step = step(data, level)
      # Two faces for each cell of the surface of the box round it, a bit less for a round shape.
      faces = round(1.4 * (a * b + b * c + c * a) / (step * step))
      min(faces, get_in(data, ["budget", Atom.to_string(level)]) || faces)
    else
      _ -> 0
    end
  end

  @doc """
  The warnings of the data of a sculpture (issue #49), with no build:
  each edit that adds or takes away and that is thinner than two cells
  of a level, `{path, level, message}` (the path from the data: `edits.3`,
  `details.0.edits.1`). Such an edit can go or tear at that level. The
  order is still good.
  """
  def warnings(data) do
    groups = Map.get(data, "groups", %{})
    details = if is_list(data["details"]), do: Enum.with_index(data["details"]), else: []

    for {part, prefix} <- [{data, ""} | for({d, k} <- details, do: {Map.put(d, "groups", groups), "details.#{k}."})],
        level <- [:near, :mid, :far],
        prefix == "" or Atom.to_string(level) in Map.get(part, "levels", ~w(near mid far)),
        step = step(part, level),
        {e, i} <- Enum.with_index(part["edits"]),
        thin = World.Sculpt.thinnest(edits([e], groups, level), 0.0),
        thin != nil and thin < 2 * step do
      l = Atom.to_string(level)

      {"#{prefix}edits.#{i}", l,
       "is #{r3(thin)} m thin, and the cells of #{l} are #{r3(step)} m: the edit can go or tear. " <>
         "Give cells of #{Float.floor(thin / 2, 3)} m or less, or put the edit in a detail."}
    end
  end

  @doc """
  The estimate of the memory of the build of a sculpture at a level, or
  of one of its tiles (`tiles/4`: a map with `share` and `faces`), in MB,
  with no build: 15 MB, 160 MB for each million texels of its maps (the
  side of the bake of the level, or of the tile, squared), and 0.15 MB
  for each thousand faces at its cells. The maps take the most: at the
  local edge (2026-11-22, the memory of WebAssembly in use), the body of a
  fridge of 3,323 faces with maps of 512 took 54.5 MB, the roof of a
  village house of 76,836 faces with maps of 512 took 31 MB, and parts
  with maps of 256 or 128 took 14 to 16 MB. No part was over this
  estimate. `World.Labour.fits?/1` compares it with the room of the edge.
  """
  def memory(data, level, tile \\ nil) do
    side = if data["look"] == "flat", do: nil, else: tile_side(get_in(data, ["bake", Atom.to_string(level)]), tile)
    texels = if side, do: side * side, else: 0
    faces = if tile, do: tile.faces, else: faces(data, level)
    Float.round(15 + 160 * texels / 1.0e6 + 0.15 * faces / 1000, 1)
  end

  @doc "The estimate of the faces of a sculpture at each level (`faces/2`, as `tile.faces` of a parts list), with no build."
  def faces(data), do: Map.new(~w(near mid far), &{&1, faces(data, String.to_existing_atom(&1))})

  defp r3(v), do: Float.round(v / 1, 3)

  # The size of the cells of a level: from the data; else, with a budget,
  # the cells that fit the budget and the thinnest edit; else the cells of
  # the level.
  defp step(data, level) do
    l = Atom.to_string(level)

    cond do
      cells = get_in(data, ["cells", l]) -> cells
      budget = get_in(data, ["budget", l]) -> World.Sculpt.fit(all(data, level), budget) || World.Sculpt.step(level)
      true -> World.Sculpt.step(level)
    end
  end

  # The edits of a sculpture at a level: an edit with `levels` is only
  # in the list at those levels (the inside of a large model at near).
  defp all(data, level), do: edits(data["edits"], Map.get(data, "groups", %{}), level)

  @doc """
  The edits of a sculpture from its data (`World.SDF.edit/3`): each edit
  with its copies (`mirror`, `repeat`), and the edits of each group that
  an edit of the shape `group` uses, at its place and its scale.

  With a level (`:near`, `:mid` or `:far`), only the edits at that
  level: an edit with `levels` is only at those levels. This is true for
  an edit at the top, for an edit in a group, and for an edit of the
  shape `group` (all the edits of the group). With no level, all the
  edits.
  """
  def edits(list, groups \\ %{}, level \\ nil),
    do: list |> Enum.filter(&here?(&1, level)) |> Enum.flat_map(&specs(&1, groups, level)) |> Enum.map(&to_edit/1)

  # True when an edit of the data is at the level (each edit with no level).
  defp here?(_e, nil), do: true
  defp here?(e, level), do: Atom.to_string(level) in Map.get(e, "levels", ~w(near mid far))

  # The plain edits of an edit of the data: a shape, its sizes, its frame.
  # The edits of a group that are not at the level stay out.
  defp specs(%{"shape" => "group"} = e, groups, level) do
    {place, k} = {frame(e), Map.get(e, "scale", 1) / 1}

    group =
      groups[e["group"]]
      |> Enum.filter(&here?(&1, level))
      |> Enum.flat_map(&specs(&1, %{}, level))
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

  defp specs(e, _groups, _level) do
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
      surface: surface(e["surface"], @atoms[e["shape"]], size(e["shape"], e["size"]))
    }

    for copy <- copies(e), do: copy.(spec)
  end

  defp to_edit(s), do: SDF.edit(s.shape, s.size, Keyword.new(Map.drop(s, [:shape, :size])))

  # The surface of an edit: the name of a kind (with the scale of the
  # kind), or a kind with a scale (m). A kind of a made thing has its
  # data, and the panes of `windows` fit the faces of a box.
  defp surface(nil, _shape, _size), do: nil
  defp surface(name, _shape, _size) when is_binary(name), do: Texture.kind(name)

  defp surface(%{"kind" => name} = s, shape, size) do
    {kind, scale} = Texture.kind(name)
    scale = Map.get(s, "scale", scale) / 1

    case kind do
      {_, _} ->
        box = if shape in [:box, :round_box], do: {elem(size, 0) / scale, elem(size, 1) / scale, elem(size, 2) / scale}
        {Texture.made(name, s, box), scale}

      kind ->
        {kind, scale}
    end
  end

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

  # The strands of a sculpture of hair: the count of its shells, how far
  # the last one is out, and the shapes where the hair is thin.
  defp strands(v, path, groups) when is_map(v) do
    World.Skill.keys(v, path, ~w(shells length thin), []) ++
      optional(v, "shells", path, fn n, p ->
        if is_integer(n) and n in 1..8, do: [], else: [{p, "must be a count of shells from 1 to 8"}]
      end) ++
      optional(v, "length", path, &number(&1, &2, 0.0005, 0.05)) ++
      optional(v, "thin", path, &checked(&1, &2, groups))
  end

  defp strands(_v, path, _groups), do: [{path, "must be {\"shells\": n, \"length\": m, \"thin\": [edits]}"}]

  # The check of a list of edits (each error with its path).
  defp checked(v, path, groups) when is_list(v) and v != [] and length(v) <= @most do
    errors = v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> edit(e, "#{path}.#{i}", groups) end)
    # With no error, the count of the edits with their copies.
    total = if errors == [], do: v |> Enum.map(&count(&1, groups)) |> Enum.sum(), else: 0
    if total > @most, do: [{path, "has #{total} edits with their copies: at most #{@most}"}], else: errors
  end

  defp checked(_v, path, _groups), do: [{path, "must be a list of 1 to #{@most} edits"}]

  # The groups: a name to a list of edits (no group in a group).
  defp groups(v, path) when is_map(v) and map_size(v) <= 64 do
    Enum.flat_map(Enum.sort(v), fn {name, list} ->
      p = "#{path}.#{name}"

      cond do
        not (name =~ ~r/^[a-z0-9_]{1,40}$/) -> [{p, "must have a name of 1 to 40 letters a-z, digits or _"}]
        is_list(list) and list != [] and length(list) <= 1_000 -> checked(list, p, nil)
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
      optional(e, "levels", path, &levels/2) ++
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
      optional(e, "levels", path, &levels/2) ++
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

  # The levels of a detail or of an edit: some of near, mid and far.
  defp levels(l, path) do
    if is_list(l) and l != [] and l -- ~w(near mid far) == [] and l == Enum.uniq(l),
      do: [],
      else: [{path, "must be a list of near, mid and far"}]
  end

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

  defp surface(%{"kind" => name} = s, path) when is_binary(name) do
    choice(name, "#{path}.kind", Texture.kinds()) ++
      optional(s, "scale", path, &number(&1, &2, 0.0005, 10)) ++
      if name in Texture.made_kinds(),
        do: Texture.check(name, s, path),
        else: for(k <- Map.keys(s) -- ~w(kind scale), do: {"#{path}.#{k}", "is not a word of a surface"})
  end

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
      Enum.flat_map(Enum.sort(v), fn {k, n} -> number(n, "#{path}.#{k}", 0.001, 10) end)
  end

  defp cells(_v, path), do: [{path, "must be an object of near, mid and far"}]

  # The side of the image of the maps at each level: a power of 2, with
  # a place for the triangles of the budget of the level.
  defp bake(v, path, data) when is_map(v) do
    World.Skill.keys(v, path, ~w(near mid far)) ++
      for {k, n} <- Enum.sort(v), k in ~w(near mid far), e <- side(n, "#{path}.#{k}", triangles(data, k)), do: e
  end

  defp bake(_v, path, _data), do: [{path, "must be an object of near, mid and far"}]

  # True when the mesh of a level is the solids of the edits.
  defp solids?(data, level), do: is_list(data["solids"]) and Atom.to_string(level) in data["solids"]

  # The levels whose mesh is the solids of the edits (`World.Sculpt.Solids`): each edit at the level has a
  # solid (or paints), and their triangles are in the budget of the level.
  defp solids(v, path, data, groups) do
    cond do
      levels(v, path) != [] ->
        levels(v, path)

      # (An edit that is not right has its own error.)
      checked(data["edits"], path, groups) != [] ->
        []

      true ->
        for level <- v,
            edits = edits(data["edits"], groups, String.to_existing_atom(level)),
            message <-
              Enum.uniq(for(e <- edits, m = World.Sculpt.Solids.error(e), do: "at #{level}: #{m}")) ++
                over(World.Sculpt.Solids.count(edits), get_in(data, ["budget", level]), level),
            do: {path, message}
    end
  end

  defp over(count, budget, level) when is_integer(budget) and count > budget,
    do: ["at #{level} the solids have #{count} triangles, more than the budget of #{budget}"]

  defp over(_count, _budget, _level), do: []

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
          optional(d, "edits", p, &checked(&1, &2, groups)) ++
          optional(d, "cells", p, &cells/2) ++
          optional(d, "budget", p, &budget/2) ++
          optional(d, "levels", p, &levels/2)
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
