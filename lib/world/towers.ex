defmodule World.Towers do
  @moduledoc """
  The towers of the world (W13 of Vũng Tàu): a lighthouse, a water tower
  or a bell tower of masonry on a round platform. The parts, from the
  ground up:

  - the platform (`platform`: its diameter and its height);
  - the body: round, `body` m across at its foot and `top` m at the
    cornice, with a `ledge` round its foot and `bands` (rings at their
    heights); the ledge, the bands and the flare are over the platform,
    the other heights over the ground;
  - the pilasters (`pilasters` of `pilaster_width` m, out to `across` m
    over the body), flared at their foot out to `foot` m over the lowest
    `flare` m;
  - the cornice: a cove from the body and the pilasters out to the
    gallery, from `cornice` m to the gallery floor at `gallery` m;
  - the gallery (`gallery_width` m across) with its rail (`rail` m);
  - the drum (the watch room, `drum` m across), the lantern (`lantern`:
    from, to, across, and its `panes` of glass in frames, with a lens in
    it), the dome to `height` m, a ball, and a lightning rod to `rod` m;
  - a door at the foot (`door`), and with `hollow` at near the wall of
    `wall` m and a spiral stair of `steps` steps round a column, to the
    gallery floor;
  - a house next to it (`house`: the points of its outline on the ground
    and its height; a hip roof of clay tiles).

  The origin is on the ground at the center of the platform; the axes are
  those of the order (x to the east and y to the north for the outline of
  a house from OpenStreetMap). Each size can have its source, in the
  extras (`"sizes"`) and in the receipt (`World.Sizes`).
  """
  alias World.{Assembly, Detail, Frame, Mesh, Part, Shape, Sizes, Vec}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @defaults [
    name: "thap",
    height: 18.0,
    platform: {7.8, 0.3},
    body: 3.2,
    top: 3.2,
    ledge: 0.8,
    bands: [4.1, 7.5],
    pilasters: 4,
    pilaster_width: 0.7,
    across: 5.1,
    foot: 6.4,
    flare: 3.1,
    cornice: 10.2,
    gallery: 12.7,
    gallery_width: 5.6,
    rail: 1.0,
    drum: 2.5,
    lantern: {15.4, 17.3, 2.2},
    panes: 10,
    rod: 21.0,
    door: {0.9, 2.1},
    door_angle: 270.0,
    hollow: false,
    wall: 0.5,
    steps: 55,
    house: nil,
    light: nil,
    sources: %{}
  ]

  @sizes [
    height: "m",
    platform: "m",
    body: "m",
    top: "m",
    ledge: "m",
    bands: "m",
    pilasters: nil,
    pilaster_width: "m",
    across: "m",
    foot: "m",
    flare: "m",
    cornice: "m",
    gallery: "m",
    gallery_width: "m",
    rail: "m",
    drum: "m",
    lantern: "m",
    panes: nil,
    rod: "m",
    door: "m",
    wall: "m",
    steps: "steps",
    house: "m"
  ]

  @doc "The names of the sizes that an order can give a source for."
  def sized, do: Enum.map(Keyword.keys(@sizes), &Atom.to_string/1) ++ ["light"]

  @doc "A check of the sources of an order (`World.Sizes.check/3`)."
  def check_sources(raw, path), do: Sizes.check(raw, path, sized())

  @doc "A check of a house of an order: an outline of 3 to 32 points `[x, y]` (within 60 m) and a height of 2 to 12 m."
  def check_house(%{"outline" => [_, _, _ | _] = pts, "height" => h} = raw, path)
      when length(pts) <= 32 and is_number(h) and h >= 2 and h <= 12 do
    if Enum.all?(pts, &match?([x, y] when is_number(x) and is_number(y) and abs(x) <= 60 and abs(y) <= 60, &1)),
      do: {:ok, Map.take(raw, ["outline", "height"])},
      else: {:error, [{path <> ".outline", "must be points [x, y] within 60 m"}]}
  end

  def check_house(_, path), do: {:error, [{path, "must be {outline: 3 to 32 points [x, y], height: 2 to 12 m}"}]}

  @doc "A check of a light of an order: a color, a count of flashes, a period (s) and a range (nm)."
  def check_light(%{"color" => c, "flashes" => f, "period" => p, "range" => r} = raw, _path)
      when is_binary(c) and byte_size(c) <= 20 and is_integer(f) and f >= 0 and f <= 9 and is_number(p) and p > 0 and
             p <= 60 and
             is_number(r) and r > 0 and r <= 50,
      do: {:ok, Map.take(raw, ["color", "flashes", "period", "range"])}

  def check_light(_, path), do: {:error, [{path, "must be {color, flashes: 0 to 9, period: s, range: nm}"}]}

  @doc "The models of the catalog: the lighthouse of Vũng Tàu."
  def models, do: [{"hai_dang_vung_tau", &vung_tau/0}]

  @doc """
  A tower; the options and their defaults are in the doc of the module
  (`@defaults`). `light` is a map of the light for the app (its color,
  flashes, period and range), or nil.
  """
  def tower(opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    level = Detail.level()
    {_, ph} = o.platform

    tower = Part.new(o.name, :tower, platform(o) ++ body(o, level) ++ top(o, level), [@o], sources: sources(o))
    stair = if o.hollow and level == :near, do: [stair(o, ph)], else: []
    house = if o.house, do: [house(o, level)], else: []

    asm = Assembly.new(o.name, tower, root: tower.name, kind: :tower, sources: sources(o), extras: extras(o))
    Enum.reduce(stair ++ house, asm, fn p, a -> Assembly.add(a, p.name, p, at: "o", port: "o") end)
  end

  @doc """
  The lighthouse of Vũng Tàu on Núi Nhỏ (Hải đăng Vũng Tàu, the tower of
  1913): 18 m from the ground to the top of its dome, a round body of 3 m,
  four pilasters, the gallery, the lantern and the keeper's house to its
  north-west. Each size has its source: a text, a measure on a photo, or
  an estimate.
  """
  def vung_tau do
    vi = "vi.wikipedia, Hải đăng Vũng Tàu"
    ld = "Lighthouse Digest, Vung Tau Light (#4244): \"white round tower on dwelling\""
    osm = "OpenStreetMap, way 229301316 (Hải đăng Vũng Tàu)"

    photo =
      "measured on the photo Hải đăng Vũng Tàu.JPG (Wikimedia Commons, Category:Vung Tau lighthouse): the scale from the platform of OpenStreetMap and a person, the heights fitted to 18 m; ±10%"

    tower(
      name: "hai_dang_vung_tau",
      hollow: true,
      house: %{
        "outline" => [
          [-4.18, 4.9],
          [-2.74, 6.32],
          [-0.18, 8.54],
          [0.25, 3.61],
          [-0.93, 3.51],
          [-2.01, 3.07],
          [-2.92, 2.33]
        ],
        "height" => 3.2
      },
      light: %{"color" => "white", "flashes" => 2, "period" => 10.0, "range" => 23},
      sources: %{
        "height" =>
          "#{vi}: a round tower 18 m high; #{ld}, 59 (ft); #{osm}, height=18. The owner: from the ground to the top of the dome.",
        "body" => "#{vi}: 3 m across (\"đường kính 3 m\"); #{photo}: the round body between the pilasters, 3.2 m.",
        "top" => photo <> ": no taper that the photo shows.",
        "platform" => "#{osm}: the outline, a circle of 7.8 m; " <> photo <> ": 0.3 m high.",
        "ledge" => photo,
        "bands" => photo,
        "pilasters" => photo <> ": 4 (three show from 45 degrees).",
        "pilaster_width" => photo,
        "across" => photo,
        "foot" => photo,
        "flare" => photo,
        "cornice" => photo,
        "gallery" => photo,
        "gallery_width" => photo,
        "drum" => photo,
        "lantern" => photo,
        "rod" => photo,
        "steps" => "Tinhte (a forum), the lighthouses of Việt Nam: 55 steps in a spiral (a weak source).",
        "house" =>
          "OpenStreetMap, way 790529527: the outline (its inner wall on the edge of the platform); the photo: brick walls and a roof of clay tiles.",
        "light" => "#{ld}: two white flashes each 10 seconds; #{osm}: seamark:light, white, period 10 s, range 23 nm."
      }
    )
  end

  # --- The parts ----------------------------------------------------------------

  defp platform(%{platform: {d, h}}),
    do: [Shape.cylinder(d / 2, h, :tile_granite, sides: 48) |> Mesh.matter(:concrete)]

  # The body, its ledge, its bands, its pilasters and the cornice: at
  # near with `hollow` the wall is a tube with the door through it.
  defp body(o, level) do
    {_, z0} = o.platform
    {r0, r1} = {o.body / 2, o.top / 2}
    sides = %{near: 48, mid: 24, far: 8}[level]
    h = o.cornice - z0
    r = fn z -> r0 + (r1 - r0) * (z - z0) / h end

    wall =
      if o.hollow and level == :near do
        {dw, dh} = o.door
        ri = fn z -> r.(z) - o.wall end

        around =
          Shape.lathe(
            [{ri.(z0 + dh), z0 + dh}, {r.(z0 + dh), z0 + dh}, {r.(o.gallery), o.gallery}, {ri.(o.gallery), o.gallery}],
            :white,
            kind: :ring,
            sides: sides
          )

        [around, door_wall(o, r0, ri.(z0), z0, dw, dh, sides)]
      else
        [Shape.lathe([{0.0, z0}, {r0, z0}, {r.(o.gallery), o.gallery}, {0.0, o.gallery}], :white, sides: sides)]
      end

    rings =
      if level == :far,
        do: [],
        else: [{z0, z0 + o.ledge, 0.1}] ++ for(b <- o.bands, do: {z0 + b, z0 + b + 0.2, 0.12})

    rings =
      for {za, zb, out} <- rings do
        Shape.lathe([{r.(za) - 0.05, za}, {r.(za) + out, za}, {r.(zb) + out, zb}, {r.(zb) - 0.05, zb}], :white,
          kind: :ring,
          sides: sides
        )
      end

    (wall ++ rings ++ pilasters(o, r, level) ++ [cornice(o, sides)]) |> Enum.map(&Mesh.matter(&1, :concrete))
  end

  # The wall at the foot with the door through it: a ring of the plan
  # with a gap of the width of the door at its angle.
  defp door_wall(o, ro, ri, z0, dw, dh, sides) do
    gap = dw / ro
    a0 = o.door_angle * :math.pi() / 180 + gap / 2
    n = max(div(sides * 7, 8), 6)
    arc = for k <- 0..n, a = a0 + (2 * :math.pi() - gap) * k / n, do: a
    outer = for a <- arc, do: {ro * :math.cos(a), ro * :math.sin(a)}
    inner = for a <- Enum.reverse(arc), do: {ri * :math.cos(a), ri * :math.sin(a)}
    Shape.prism(outer ++ inner, dh, :white, frame: Frame.move({0.0, 0.0, z0}))
  end

  # The pilasters: each a prism in the plane of its radius, from inside
  # the body out to `across`, flared at its foot out to `foot`.
  defp pilasters(o, r, level) do
    {_, z0} = o.platform
    n = if level == :far, do: 0, else: o.pilasters

    for k <- 0..(n - 1)//1 do
      a = (45.0 + 360.0 * k / n) * :math.pi() / 180
      {c, s} = {:math.cos(a), :math.sin(a)}
      tangent = {-s, c, 0.0}
      rin = r.(z0) - 0.3
      {out, foot} = {o.across / 2, o.foot / 2}
      ztop = o.cornice

      loop = [{rin, z0}, {foot, z0}, {out, z0 + o.flare}, {out, ztop}, {rin, ztop}]
      # x out along the radius, y up, z back along the tangent (the
      # right hand): the prism goes from one side of the pilaster to the
      # other.
      frame = Frame.new(Vec.scale(tangent, o.pilaster_width / 2), Vec.scale(tangent, -1.0), {0.0, 0.0, 1.0})
      Shape.prism(loop, o.pilaster_width, :white, frame: frame)
    end
  end

  # The cornice: a cove from the pilasters out to the gallery, and the
  # floor of the gallery on it.
  defp cornice(o, sides) do
    {r0, rg, z1} = {o.across / 2 - 0.05, o.gallery_width / 2, o.gallery}
    zc = o.cornice
    steps = if sides > 8, do: 6, else: 2

    cove =
      for i <- 0..steps do
        t = i / steps * :math.pi() / 2
        {r0 + (rg - r0) * (1 - :math.cos(t)), zc + (z1 - 0.25 - zc) * :math.sin(t)}
      end

    Shape.lathe([{0.0, zc} | cove] ++ [{rg, z1}, {0.0, z1}], :white, sides: sides)
  end

  # The top: the rail of the gallery, the drum with its door, the lantern
  # with its panes and its lens, the dome, the ball and the rod.
  defp top(o, level) do
    sides = %{near: 32, mid: 16, far: 8}[level]
    {la, lb, ld} = o.lantern
    {rg, rd, rl} = {o.gallery_width / 2, o.drum / 2, ld / 2}
    z = o.gallery

    drum = Shape.cylinder(rd, la - z, :white, sides: sides, frame: Frame.move({0.0, 0.0, z})) |> Mesh.matter(:concrete)

    glass =
      Shape.cylinder(rl - 0.03, lb - la, :glass, sides: max(o.panes, 6), frame: Frame.move({0.0, 0.0, la}))
      |> Mesh.matter(:glass)

    dome =
      Shape.lathe(
        [{rl + 0.12, lb}, {rl + 0.12, lb + 0.08}] ++
          for(
            i <- 1..6,
            t = i / 6 * :math.pi() / 2,
            do: {(rl + 0.05) * :math.cos(t) + 0.001, lb + 0.08 + (o.height - lb - 0.08) * :math.sin(t)}
          ) ++
          [{0.0, o.height}],
        :white,
        sides: sides
      )
      |> Mesh.matter(:steel)

    rest =
      if level == :far do
        []
      else
        frames =
          for k <- 0..(o.panes - 1) do
            a = 2 * :math.pi() * (k + 0.5) / o.panes
            {x, y} = {rl * :math.cos(a), rl * :math.sin(a)}
            Shape.cylinder(0.035, lb - la, :white, sides: 6, frame: Frame.move({x, y, la})) |> Mesh.matter(:steel)
          end

        ball =
          Shape.sphere(0.15, :white, rings: 6, sides: 12)
          |> Mesh.transform(Frame.move({0.0, 0.0, o.height}))
          |> Mesh.matter(:steel)

        rod =
          Shape.cylinder(0.02, o.rod - o.height, :steel, sides: 6, frame: Frame.move({0.0, 0.0, o.height + 0.1}))
          |> Mesh.matter(:steel)

        lens =
          Shape.cylinder(0.45, 1.0, :glass, sides: 12, frame: Frame.move({0.0, 0.0, la + 0.4})) |> Mesh.matter(:glass)

        door = Shape.box({-0.35, rd - 0.02, z}, {0.35, rd + 0.03, z + 1.8}, :dark) |> Mesh.matter(:steel)
        frames ++ [ball, rod, lens, door] ++ rail(o, rg - 0.1, z, level)
      end

    [drum, glass, dome | rest]
  end

  # The rail of the gallery: posts, and two rails round them (at mid one
  # low wall of the height of the rail).
  defp rail(o, r, z, :mid) do
    [
      Shape.lathe([{r - 0.06, z}, {r, z}, {r, z + o.rail}, {r - 0.06, z + o.rail}], :white, kind: :ring, sides: 24)
      |> Mesh.matter(:steel)
    ]
  end

  defp rail(o, r, z, _near) do
    n = round(2 * :math.pi() * r / 0.6)

    posts =
      for k <- 0..(n - 1) do
        a = 2 * :math.pi() * k / n
        Shape.cylinder(0.025, o.rail, :white, sides: 6, frame: Frame.move({r * :math.cos(a), r * :math.sin(a), z}))
      end

    tube = for k <- 0..7, a = 2 * :math.pi() * k / 8, do: {r + 0.025 * :math.cos(a), 0.025 * :math.sin(a)}

    rails =
      for h <- [o.rail * 0.5, o.rail] do
        Shape.lathe(Enum.map(tube, fn {rr, zz} -> {rr, zz + z + h} end), :white, kind: :ring, sides: 48)
      end

    Enum.map(posts ++ rails, &Mesh.matter(&1, :steel))
  end

  # The spiral stair inside: a column and `steps` treads, 10 to a turn,
  # from the platform to the floor of the gallery (an estimate: the
  # stair of a lighthouse of this size).
  defp stair(o, z0) do
    ri = o.body / 2 - o.wall
    rise = (o.gallery - z0) / o.steps

    column =
      Shape.cylinder(0.12, o.gallery - z0, :concrete, sides: 12, frame: Frame.move({0.0, 0.0, z0}))
      |> Mesh.matter(:concrete)

    treads =
      for i <- 0..(o.steps - 1) do
        {a0, a1} = {i * :math.pi() / 5, (i + 1) * :math.pi() / 5}
        p = fn rr, a -> {rr * :math.cos(a), rr * :math.sin(a)} end
        loop = [p.(0.12, a0), p.(ri, a0), p.(ri, (a0 + a1) / 2), p.(ri, a1), p.(0.12, a1)]

        Shape.prism(loop, 0.06, :concrete, frame: Frame.move({0.0, 0.0, z0 + (i + 1) * rise - 0.06}))
        |> Mesh.matter(:concrete)
      end

    Part.new("cau_thang", :tower, [column | treads], [@o],
      params: %{"steps" => o.steps, "rise" => Float.round(rise, 3)},
      sources: ["The stair: #{o.steps} steps of #{Float.round(rise * 100, 1)} cm round a column, 10 to a turn."]
    )
  end

  # The house: walls of brick on the outline, a door on its longest side
  # away from the tower, and a hip roof of clay tiles over eaves of 0.4 m.
  defp house(o, level) do
    pts = Enum.map(o.house["outline"], fn [x, y] -> {x / 1, y / 1} end)
    h = o.house["height"] / 1
    {cx, cy} = centroid(pts)
    walls = Shape.prism(ccw(pts), h, :brick) |> Mesh.matter(:brick)
    eave = for {x, y} <- ccw(pts), do: {cx + (x - cx) * 1.12, cy + (y - cy) * 1.12}
    roof = pyramid(eave, h, {cx, cy, h + 1.2}) |> Mesh.matter(:tile)
    door = if level == :far, do: [], else: [door(pts, {cx, cy})]
    Part.new("nha_quan_dang", :tower, [walls, roof | door], [@o], sources: [o.sources["house"] || Sizes.none()])
  end

  defp centroid(pts) do
    n = length(pts)
    {Enum.sum(Enum.map(pts, &elem(&1, 0))) / n, Enum.sum(Enum.map(pts, &elem(&1, 1))) / n}
  end

  # The loop counterclockwise from +z.
  defp ccw(pts) do
    area =
      pts |> Enum.zip(tl(pts) ++ [hd(pts)]) |> Enum.map(fn {{x0, y0}, {x1, y1}} -> x0 * y1 - x1 * y0 end) |> Enum.sum()

    if area >= 0, do: pts, else: Enum.reverse(pts)
  end

  # A hip roof: the eaves at `z`, each side up to the apex.
  defp pyramid(loop, z, apex) do
    n = length(loop)
    points = Enum.map(loop, fn {x, y} -> {x, y, z} end) ++ [apex]
    sides = for i <- 0..(n - 1), do: [i, rem(i + 1, n), n]
    Mesh.new(points, Mesh.outside(points, [Enum.reverse(Enum.to_list(0..(n - 1))) | sides]), :roof_clay)
  end

  # The door of the house: in the middle of its longest side, the side
  # that is farthest from the tower.
  defp door(pts, {cx, cy}) do
    {{x0, y0}, {x1, y1}} =
      pts
      |> Enum.zip(tl(pts) ++ [hd(pts)])
      |> Enum.max_by(fn {{a, b}, {c, d}} -> Vec.len({c - a, d - b, 0.0}) * Vec.len({(a + c) / 2, (b + d) / 2, 0.0}) end)

    {mx, my} = {(x0 + x1) / 2, (y0 + y1) / 2}
    out = Vec.norm({mx - cx, my - cy, 0.0})
    at = Vec.add({mx, my, 0.0}, Vec.scale(out, 0.02))
    frame = Frame.new(at, out, {0.0, 0.0, 1.0})
    Shape.box({-0.45, 0.0, 0.0}, {0.45, 2.1, 0.05}, :wood) |> Mesh.transform(frame) |> Mesh.matter(:wood)
  end

  # --- The data of the model --------------------------------------------------------------

  defp sources(o) do
    ["The sizes of the order and their sources are in the extras (\"sizes\"); a size with no source is an estimate."] ++
      for({_, v} <- Enum.sort(o.sources), do: v)
  end

  defp extras(o) do
    {d, _} = o.platform
    r = d / 2
    house = if o.house, do: Enum.map(o.house["outline"], fn [x, y] -> [x / 1, y / 1] end), else: []

    light =
      if o.light,
        do: [%{"name" => "light", "value" => o.light, "source" => o.sources["light"] || Sizes.none()}],
        else: []

    %{
      "site" => true,
      "sizes" => Sizes.list(o, @sizes, o.sources) ++ light,
      "light" => o.light,
      "ports" => ports(o),
      "collision" => collision(o),
      "surface" => %{"corners" => [[-r, -r], [r, -r], [-r, r], [r, r]] ++ house}
    }
  end

  defp port(kind, at, normal, size),
    do: %{"kind" => kind, "at" => Vec.float(at), "normal" => Vec.float(normal), "size" => size}

  # The ports: the light in the lantern, the door at the foot, a view on
  # the gallery, and the door of the house.
  defp ports(o) do
    {la, lb, _} = o.lantern
    {_, z0} = o.platform
    {dw, dh} = o.door
    a = o.door_angle * :math.pi() / 180
    out = {:math.cos(a), :math.sin(a), 0.0}

    [
      port("light", {0.0, 0.0, (la + lb) / 2}, {0.0, 0.0, 1.0}, [0.9, 0.9, 1.0]),
      port("door", Vec.add(Vec.scale(out, o.body / 2), {0.0, 0.0, z0}), out, [dw, 0.3, dh]),
      port("view", {0.0, o.gallery_width / 2 - 0.5, o.gallery}, {0.0, 0.0, 1.0}, [1.5, 0.8, 2.0])
    ]
  end

  # The collision boxes: the platform, the body with its pilasters, the
  # gallery, the top, and the house.
  defp collision(o) do
    {d, ph} = o.platform
    {_, lb, ld} = o.lantern

    box = fn name, {x0, y0, z0}, {x1, y1, z1} ->
      %{"name" => name, "at" => {(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2}, "size" => {x1 - x0, y1 - y0, z1 - z0}}
    end

    {f, a, g} = {o.foot / 2, o.across / 2, o.gallery_width / 2}

    house =
      if o.house do
        {{x0, y0}, {x1, y1}} =
          o.house["outline"]
          |> Enum.map(fn [x, y] -> {x / 1, y / 1, 0.0} end)
          |> Vec.bounds()
          |> then(fn {{a0, b0, _}, {a1, b1, _}} -> {{a0, b0}, {a1, b1}} end)

        [box.("nha", {x0, y0, 0.0}, {x1, y1, o.house["height"] / 1})]
      else
        []
      end

    [
      box.("nen", {-d / 2, -d / 2, 0.0}, {d / 2, d / 2, ph}),
      box.("chan", {-f, -f, ph}, {f, f, ph + o.flare}),
      box.("than", {-a, -a, ph + o.flare}, {a, a, o.gallery}),
      box.("ban_cong", {-g, -g, o.gallery - 0.3}, {g, g, o.gallery + o.rail}),
      box.("den", {-ld / 2, -ld / 2, o.gallery}, {ld / 2, ld / 2, max(lb, o.height)})
    ] ++ house
  end
end
