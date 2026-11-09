defmodule World.Skills.Base do
  @moduledoc """
  The skill `base` of a mason: the base and the plinth of a statue. The
  base is a block with round corners (`corner`); at near and mid it has
  bands at its foot and its top and a frame round each panel, the panels
  in a recess of 0.15 m, with the figures in relief at near (`reliefs`:
  a `side`, a count of `figures` that stand in a row, and a `title`). The
  plinth is round with a curved top. The part `be` (nil with no base and
  no plinth) has the sources of the model.

  The base on Núi Nhỏ (plan 0005, the frames of the drone video): with
  `base_plan` curved, its front and its back are straight and its two
  sides curve in by `base_curve` m, with a pilaster at each corner (its
  windows tall slots), two small windows under each panel and a door at
  the back; `relief_metal` makes the figures of the panels of bronze.
  With `relief_photos`, each panel is of its own role (`relief_front`,
  `relief_back`, `relief_left`, `relief_right`), for the photo of its
  relief (a texture of the drawing, `World.Textures`), and has no figures
  of lofts.
  With `base_room`, the base is a room (its walls 0.3 m, its floor on the
  foot band, its ceiling the top band) and the plinth is hollow, with a
  round opening of `well` m and 1.6 m round it for the stair. With
  `terrace`, a round platform of three steps of that radius is round the
  base.
  """
  @behaviour World.Skill
  alias World.{Detail, Frame, Mesh, Part, Shape, Vec}
  alias World.Skills.Statue

  @names ~w(material base_width base_depth base_height corner reliefs plinth_radius plinth_height plinth_top plinth_sides
             base_plan base_curve base_room relief_metal relief_photos terrace well)

  @photo_roles %{front: :relief_front, back: :relief_back, left: :relief_left, right: :relief_right}

  @impl true
  def name, do: "base"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # The prisms of the block and the lathe of the plinth, and the figures
  # in relief at near.
  @impl true
  def estimate(_data, :far), do: 100
  def estimate(_data, :mid), do: 1_500
  def estimate(data, :near), do: 2_500 + 120 * Enum.sum(for r <- Map.get(data, "reliefs", []), do: r["figures"] || 3)

  @impl true
  def make(data, _inputs, %{sources: sources}) do
    o = Statue.o(data, @names)
    part = base_part(o, sources)
    {if(part.shapes != [], do: part), %{}, %{}}
  end

  # The outline of the base, in order round it (counterclockwise from +z):
  # a rectangle with round corners, or the curved plan of Núi Nhỏ.
  defp outline(%{base_plan: "curved"} = o, inset) do
    n = %{near: 12, mid: 6, far: 3}[Detail.level()]
    {hw, hd, c} = {o.base_width / 2 - inset, o.base_depth / 2 - inset, o.base_curve}
    side = fn sx -> for k <- 0..n, t = -1 + 2 * k / n, do: {sx * (hw - c * (1 - t * t)), sx * hd * t} end
    side.(1.0) ++ side.(-1.0)
  end

  defp outline(o, inset), do: outline(o.base_width, o.base_depth, o.corner, inset)

  defp outline(w, d, rc, inset) do
    n = %{near: 4, mid: 2, far: 1}[Detail.level()]
    {hw, hd, r} = {w / 2 - inset, d / 2 - inset, max(rc - inset, 0.01)}

    for {cx, cy, a0} <- [
          {hw - r, hd - r, 0.0},
          {-hw + r, hd - r, 90.0},
          {-hw + r, -hd + r, 180.0},
          {hw - r, -hd + r, 270.0}
        ],
        k <- 0..n do
      a = (a0 + 90.0 * k / n) * :math.pi() / 180
      {cx + r * :math.cos(a), cy + r * :math.sin(a)}
    end
  end

  defp base_part(o, sources) do
    level = Detail.level()
    {look, matter} = Statue.material(o.material)
    h = o.base_height

    block =
      cond do
        h <= 0 ->
          []

        level == :far ->
          [Shape.prism(outline(o, 0.0), h, look)]

        true ->
          [Shape.prism(outline(o, 0.0), 0.6, look)] ++
            walls(o, h, look) ++
            frames(o, look) ++
            terrace(o, look) ++ if(level == :near, do: openings(o) ++ panels(o) ++ reliefs(o, look), else: [])
      end

    plinth =
      if o.plinth_height > 0 do
        [plinth(o, h, look) |> Mesh.matter(matter)]
      else
        []
      end

    shapes = Enum.map(block ++ steps(o, level), &if(&1.matter, do: &1, else: Mesh.matter(&1, matter)))
    Part.new("be", :statue, shapes ++ plinth, [Statue.port()], sources: sources)
  end

  # The wall of the base between its two bands: a solid block, or with
  # `base_room` a wall of 0.3 m round a room, and the top band with the
  # opening of the stair.
  defp walls(%{base_room: true} = o, h, look) do
    ri = o.well / 2 + 1.6
    # The opening of the stair: a circle, a point at the angle of each
    # point of the outline.
    hole = for {x, y} <- outline(o, 0.0), a = :math.atan2(y, x), do: {ri * :math.cos(a), ri * :math.sin(a)}

    [
      tube(outline(o, 0.15), outline(o, 0.45), 0.6, h - 1.1, look),
      tube(outline(o, 0.0), hole, h - 0.5, 0.5, look)
    ]
  end

  defp walls(o, h, look) do
    [
      Shape.prism(outline(o, 0.15), h - 1.1, look, frame: Frame.move({0.0, 0.0, 0.6})),
      Shape.prism(outline(o, 0.0), 0.5, look, frame: Frame.move({0.0, 0.0, h - 0.5}))
    ]
  end

  # A solid between two outlines of the same count, from z0 for h m: its
  # outside, its inside (facing in), and the rings at its ends.
  defp tube(outer, inner, z0, h, look) do
    n = length(outer)
    ring = fn loop, z -> for {x, y} <- loop, do: {x / 1, y / 1, z / 1} end
    points = ring.(outer, z0) ++ ring.(outer, z0 + h) ++ ring.(inner, z0) ++ ring.(inner, z0 + h)
    {ob, ot, ib, it} = {0, n, 2 * n, 3 * n}

    faces =
      Enum.flat_map(0..(n - 1), fn i ->
        j = rem(i + 1, n)

        [
          [ob + i, ob + j, ot + j, ot + i],
          [ib + j, ib + i, it + i, it + j],
          [ob + j, ob + i, ib + i, ib + j],
          [ot + i, ot + j, it + j, it + i]
        ]
      end)

    Mesh.new(points, faces, look)
  end

  # The round platform of three steps of 0.15 m round the base.
  defp terrace(%{terrace: r}, _look) when r == 0, do: []

  defp terrace(%{terrace: r}, look) do
    profile = [
      {0.0, 0.0},
      {r, 0.0},
      {r, 0.15},
      {r - 0.35, 0.15},
      {r - 0.35, 0.3},
      {r - 0.7, 0.3},
      {r - 0.7, 0.45},
      {0.0, 0.45}
    ]

    [Shape.lathe(profile, look, sides: 48)]
  end

  # The plinth: round with a curved top, or with `plinth_top` (the radius
  # of its top, under the hem) a dome of `plinth_sides` facets, a face to
  # the front (the plinth on Núi Nhỏ: 8 facets, plan 0005).
  defp plinth(%{base_room: true} = o, h, look) do
    {r, t, ph} = {o.plinth_radius, o.plinth_top || 0.7 * o.plinth_radius, o.plinth_height}
    ri = o.well / 2 + 1.6
    # The ring of the plinth round the opening of the stair.
    curve = for f <- [0.0, 0.08, 0.33, 0.6, 0.84, 1.0], do: {t + (r - t) * :math.sqrt(1 - f * f), f * ph}
    a = :math.pi() / o.plinth_sides

    Shape.lathe([{ri, 0.0} | curve] ++ [{ri, ph}], look,
      kind: :ring,
      sides: o.plinth_sides,
      frame: Frame.new({0.0, 0.0, h}, {0.0, 0.0, 1.0}, {-:math.sin(a), :math.cos(a), 0.0})
    )
  end

  defp plinth(%{plinth_top: nil} = o, h, look) do
    {r, ph} = {o.plinth_radius, o.plinth_height}
    profile = [{0.0, 0.0}, {r, 0.0}, {r, 0.75 * ph}, {0.92 * r, 0.93 * ph}, {0.7 * r, ph}, {0.0, ph}]
    Shape.lathe(profile, look, sides: o.plinth_sides, frame: Frame.move({0.0, 0.0, h}))
  end

  defp plinth(o, h, look) do
    {r, t, ph} = {o.plinth_radius, o.plinth_top, o.plinth_height}
    # The profile of a dome from r at the foot to t at the top.
    curve = for f <- [0.0, 0.08, 0.33, 0.6, 0.84, 1.0], do: {t + (r - t) * :math.sqrt(1 - f * f), f * ph}
    profile = [{0.0, 0.0} | curve] ++ [{0.0, ph}]
    a = :math.pi() / o.plinth_sides

    Shape.lathe(profile, look,
      sides: o.plinth_sides,
      frame: Frame.new({0.0, 0.0, h}, {0.0, 0.0, 1.0}, {-:math.sin(a), :math.cos(a), 0.0})
    )
  end

  # The four sides of the base: their normal, their width, and where
  # their middle is.
  defp sides(o) do
    {hw, hd} = {o.base_width / 2, o.base_depth / 2}
    hw_side = if o.base_plan == "curved", do: hw - o.base_curve, else: hw

    %{
      "front" => {{0.0, 1.0, 0.0}, o.base_width, {0.0, hd, 0.0}},
      "back" => {{0.0, -1.0, 0.0}, o.base_width, {0.0, -hd, 0.0}},
      "left" => {{-1.0, 0.0, 0.0}, o.base_depth, {-hw_side, 0.0, 0.0}},
      "right" => {{1.0, 0.0, 0.0}, o.base_depth, {hw_side, 0.0, 0.0}}
    }
  end

  # The frame of the panel of each side: a pilaster at each end of the
  # panel, in the recess of the middle of the base; on the curved plan a
  # pilaster of 1.2 m at each corner.
  defp frames(%{base_plan: "curved"} = o, look) do
    {hw, hd, h} = {o.base_width / 2, o.base_depth / 2, o.base_height}

    for sx <- [-1.0, 1.0], sy <- [-1.0, 1.0] do
      {{x0, y0, _}, {x1, y1, _}} = Vec.bounds([{sx * hw, sy * hd, 0.0}, {sx * (hw - 1.2), sy * (hd - 1.2), 0.0}])
      Shape.box({x0, y0, 0.6}, {x1, y1, h - 0.5}, look)
    end
  end

  defp frames(o, look) do
    for {_, {n, width, mid}} <- sides(o), sign <- [-1.0, 1.0] do
      along = Vec.cross({0.0, 0.0, 1.0}, n)
      half = width / 2 - o.corner
      c = Vec.add(mid, Vec.scale(along, sign * (half - 0.5)))
      box_on(c, n, along, {0.5, 0.15, o.base_height - 1.1}, 0.6, look)
    end
  end

  # A box of `{half along, depth in from the face, height}` on a face of
  # the base: its outer face on the face, from the height `z`.
  defp box_on(c, n, along, {ha, depth, h}, z, look) do
    p0 = Vec.add(Vec.add(c, Vec.scale(along, -ha)), Vec.scale(n, -depth))
    p1 = Vec.add(c, Vec.scale(along, ha))
    {{x0, y0, _}, {x1, y1, _}} = Vec.bounds([p0, p1])
    Shape.box({x0, y0, z}, {x1, y1, z + h}, look)
  end

  # The dark of the openings on the curved plan: the door in the middle of
  # the back, two small windows under each panel, and three tall slots on
  # each face of each pilaster. Each 0.02 m out of its face.
  defp openings(%{base_plan: "curved"} = o) do
    {hw, hd, h} = {o.base_width / 2, o.base_depth / 2, o.base_height}
    dark = fn {x0, y0, z0}, {x1, y1, z1} -> Shape.box({x0, y0, z0}, {x1, y1, z1}, :dark) |> Mesh.matter(:concrete) end
    door = dark.({-0.7, -hd + 0.13, 0.6}, {0.7, -hd + 0.17, 3.0})

    small =
      for {_side, {n, _width, mid}} <- sides(o), along = Vec.cross({0.0, 0.0, 1.0}, n), k <- [-1.5, 1.5] do
        c = Vec.add(mid, Vec.add(Vec.scale(along, k), Vec.scale(n, -0.13)))

        {{x0, y0, _}, {x1, y1, _}} =
          Vec.bounds([
            Vec.add(c, Vec.scale(along, -0.4)),
            Vec.add(Vec.add(c, Vec.scale(along, 0.4)), Vec.scale(n, 0.04))
          ])

        dark.({x0, y0, 0.75}, {x1, y1, 1.2})
      end

    slots =
      for sx <- [-1.0, 1.0], sy <- [-1.0, 1.0], k <- [0.3, 0.6, 0.9] do
        [
          dark.({sx * (hw - k) - 0.05, sy * hd - 0.02, 1.0}, {sx * (hw - k) + 0.05, sy * hd + 0.02, h - 1.0}),
          dark.({sx * hw - 0.02, sy * (hd - k) - 0.05, 1.0}, {sx * hw + 0.02, sy * (hd - k) + 0.05, h - 1.0})
        ]
      end

    [door | small] ++ List.flatten(slots)
  end

  defp openings(_o), do: []

  # The bronze panel of each side of the curved plan, behind its figures:
  # 0.03 m out of the wall, between the pilasters, from 1.35 m to 0.8 m
  # under the top (the frames of the drone video).
  defp panels(%{base_plan: "curved", relief_metal: true} = o) do
    {hw, hd, h} = {o.base_width / 2 - 1.4, o.base_depth / 2 - 1.4, o.base_height}

    keep = fn {x, y}, side ->
      case side do
        :left -> x < 0 and abs(y) <= hd
        :right -> x > 0 and abs(y) <= hd
      end
    end

    for side <- [:front, :back, :left, :right] do
      # The straight front and back have no point between their corners.
      line = fn inset ->
        case side do
          :front -> [{hw, o.base_depth / 2 - inset}, {-hw, o.base_depth / 2 - inset}]
          :back -> [{-hw, -o.base_depth / 2 + inset}, {hw, -o.base_depth / 2 + inset}]
          _ -> Enum.filter(outline(o, inset), &keep.(&1, side))
        end
      end

      role = if o.relief_photos, do: @photo_roles[side], else: :bronze
      {role, line.(0.12), line.(0.15)}
    end
    |> Enum.flat_map(&door_gap/1)
    |> Enum.map(fn {role, a, b} ->
      Shape.prism(a ++ Enum.reverse(b), h - 2.15, role, frame: Frame.move({0.0, 0.0, 1.35})) |> Mesh.matter(:copper)
    end)
  end

  defp panels(_o), do: []

  # The back panel in two, at the two sides of the door (1.8 m).
  defp door_gap({role, [{x0, y}, {x1, _}], [{_, yi}, _]}) when y < 0,
    do: [{role, [{x0, y}, {-0.9, y}], [{x0, yi}, {-0.9, yi}]}, {role, [{0.9, y}, {x1, y}], [{0.9, yi}, {x1, yi}]}]

  defp door_gap(lines), do: [lines]

  # The steps up the front facet of a plinth of facets, 0.9 m wide: a
  # band of treads from the base to the hem (the photos).
  defp steps(%{plinth_top: t, base_room: true} = o, :near) when is_number(t) do
    c = :math.cos(:math.pi() / o.plinth_sides)
    {r, rt, ph, h} = {o.plinth_radius * c, t * c, o.plinth_height, o.base_height}
    n = round(ph / 0.3)

    for k <- 0..(n - 1) do
      f = (k + 0.5) / n
      y = rt + (r - rt) * :math.sqrt(1 - f * f)
      Shape.box({-0.45, y - 0.2, h + k * ph / n}, {0.45, y + 0.12, h + (k + 1) * ph / n}, :stone_wash)
    end
  end

  defp steps(_o, _level), do: []

  # The figures in relief of each panel: standing figures in a row, each
  # a body and a head that stand 0.12 m out of the recess; on a curved
  # side each on the curve, and with `relief_metal` of bronze.
  defp reliefs(o, look) do
    for %{"side" => side, "figures" => count} <- o.reliefs,
        not o.relief_photos,
        {n, width, mid} = sides(o)[side],
        i <- 0..(count - 1) do
      along = Vec.cross({0.0, 0.0, 1.0}, n)
      panel = width - 2 * o.corner - 2.0
      x = -panel / 2 + panel * (i + 0.5) / count
      c = Vec.add(mid, Vec.add(Vec.scale(along, x), Vec.scale(n, curve(o, side, x) - 0.09)))
      ph = o.base_height - 1.1
      fw = min(0.3, panel / count * 0.35)
      body = {Vec.add(c, {0.0, 0.0, 0.7}), along, n, fw, 0.06, 3.0}
      shoulders = {Vec.add(c, {0.0, 0.0, 0.6 + 0.62 * ph}), along, n, fw * 1.1, 0.06, 3.0}
      neck = {Vec.add(c, {0.0, 0.0, 0.6 + 0.7 * ph}), along, n, fw * 0.45, 0.05, 2.0}
      head = {Vec.add(c, {0.0, 0.0, 0.6 + 0.85 * ph}), along, n, fw * 0.55, 0.05, 2.0}
      figure = Shape.loft([body, shoulders, neck, head], look, sides: 12)
      if o.relief_metal, do: %{figure | material: :bronze} |> Mesh.matter(:copper), else: figure
    end
  end

  # How far out of the middle of a curved side the face is at `x` along it.
  defp curve(%{base_plan: "curved"} = o, side, x) when side in ~w(left right),
    do: o.base_curve * :math.pow(x / (o.base_depth / 2), 2)

  defp curve(_o, _side, _x), do: 0.0
end
