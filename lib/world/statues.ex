defmodule World.Statues do
  @moduledoc """
  The statues of the world (W13 of Vũng Tàu): a figure of the person
  blueprint (`World.People.Human`) at any size and in any pose, in a long
  robe, cast as one solid of concrete or stone (`World.Cast`), with a
  halo, on a round plinth and on a base with panels of figures in relief.

  The figure is the person at the level `:mid`, posed (the pose
  `arms_out` has the arms straight out to the sides, `lift` degrees over
  the level; any other pose is a pose of `World.People.Pose`), scaled so
  that its top (the top of the halo, when it has one) is `height` over
  its feet. With `span` (the hands, tip to tip) and `hand` (a hand, from
  the wrist to the tip of the middle finger), the arms out to the sides
  become shorter or longer along x, from the shoulders: a statue has the
  proportions of its sculptor, not of a person. The robe, its sleeves
  along the bones of the arms and the two long panels at its sides are
  shapes on the posed body; the cast makes one shell of them with the
  head, the hair and the hands, and no gap between them.

  With `hollow`, the near level has walls of `wall` m (to the cell of the
  cast, at the least two cells), a spiral stair of `steps` steps round an
  open well of `well` m, each tread from the well to the wall, from the
  plinth to the shoulders, and openings: the `windows`
  in the front of the robe, a balcony at each shoulder, and the shaft of
  the stair down into the base. The mid and the far levels are solid
  (the inside is closed to the player).

  Each size of an order has its source (`sources`, by the name of the
  size); a size with no source is an estimate, and the receipt says so
  (`"sizes"` in the extras).

  The origin of the model is on the ground at the center of the base;
  the figure looks to +y.
  """
  alias World.{Assembly, Cast, Contact, Detail, Figure, Frame, Mesh, Part, Scene, Shape, Vec}
  alias World.People.Human

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @defaults [
    name: "tuong",
    height: 32.0,
    span: nil,
    hand: nil,
    pose: "arms_out",
    lift: 8.0,
    gender: 1.0,
    age: 35,
    hair: "long01",
    robe: true,
    halo: true,
    rays: 9,
    material: :concrete,
    hollow: false,
    wall: 0.3,
    steps: 133,
    well: 1.0,
    windows: [],
    plinth_radius: 4.5,
    plinth_height: 1.2,
    base_width: 12.0,
    base_depth: 12.0,
    base_height: 4.0,
    corner: 1.5,
    reliefs: [],
    rail: 1.0,
    weathering: 0.5,
    sources: %{}
  ]

  # The sizes of an order, with their units, for the receipt.
  @sizes [
    height: "m",
    span: "m",
    hand: "m",
    lift: "deg",
    wall: "m",
    steps: "steps",
    well: "m",
    plinth_radius: "m",
    plinth_height: "m",
    base_width: "m",
    base_depth: "m",
    base_height: "m",
    corner: "m",
    rail: "m"
  ]

  # The materials of a statue: the role of its look and of its mass.
  @materials %{concrete: {:stone_wash, :concrete}, stone: {:stone, :stone}}

  @doc "The materials of a statue."
  def materials, do: Map.keys(@materials)

  @doc "The models of the catalog: the statue on Núi Nhỏ."
  def models, do: [{"tuong_chua_kito_vua", &nui_nho/0}]

  @doc """
  A statue. The options (with their defaults): `name`, `height` (32 m),
  `span` and `hand` (nil: the proportions of the person), `pose`
  ("arms_out"), `lift` (8 degrees), `gender`, `age` and `hair` (of the
  person), `robe` (true), `halo` (true) with `rays` (9 metal rays),
  `material` (`:concrete` with a render of washed stone, or `:stone`),
  `hollow` (false) with `wall`, `steps`, `well` (the open well in the
  middle of the stair) and `windows` (a list of `{z, width, height}`: the center of an
  opening over the feet, m), `plinth_radius` and `plinth_height` (0: no
  plinth), `base_width`, `base_depth` and `base_height` (0: no base),
  `corner` (the radius of the round corners of the base), `reliefs` (a
  list of `%{"side" => front | back | left | right, "figures" => n,
  "title" => text}`), `rail` (the height of the rail round the top of the
  base; 0: no rail), `weathering` (0 to 1: the stains of the sea air,
  for the shader of an app) and `sources` (a map of the name of a size to
  its source).
  """
  def statue(opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    level = Detail.level()
    lift = o.base_height + o.plinth_height
    fig = figure(o)

    base = base_part(o)
    {shapes, grid} = statue_shapes(fig, o, level)
    up = Frame.move({0.0, 0.0, lift})
    tuong = Part.new(o.name, :statue, Enum.map(shapes, &Mesh.transform(&1, up)), [@o], sources: sources(o))
    stair = if o.hollow and level == :near, do: [stair_part(fig, o, grid) |> move_part(up)], else: []
    rail = if o.rail > 0 and o.base_height > 0 and level != :far, do: [rail_part(o)], else: []
    # With no base and no plinth, the statue is the root.
    parts = if(base.shapes == [], do: [], else: [base]) ++ [tuong] ++ stair ++ rail
    [root | rest] = parts

    asm = Assembly.new(o.name, root, root: root.name, kind: :statue, sources: sources(o), extras: extras(fig, o, lift))
    Enum.reduce(rest, asm, fn p, a -> Assembly.add(a, p.name, p, at: "o", port: "o") end)
  end

  @doc """
  The statue of Christ the King on Núi Nhỏ, Vũng Tàu (Tượng Chúa Kitô
  Vua, 1974 to 1993): 32 m from the feet to the top of the halo, the
  arms 18.4 m from hand to hand, 133 steps inside to the shoulders, a
  base of 4 m with four panels in relief. Each size has its source, or
  says that it is an estimate.
  """
  def nui_nho do
    vi = "vi.wikipedia, Tượng Chúa Kitô Vua (Vũng Tàu)"
    en = "en.wikipedia, Christ of Vũng Tàu"
    av = "amazingvietnam.vn (2010), the statue of Christ on Núi Nhỏ"
    photo = "by eye from the photo Statue_of_Jesus_in_Vung_Tau.jpg (Wikimedia Commons, Category:Christ of Vung Tau)"

    statue(
      name: "tuong_chua_kito_vua",
      height: 32.0,
      span: 18.4,
      hand: 2.2,
      hollow: true,
      steps: 133,
      windows: [{0.585 * 32.0, 1.2, 1.2}, {0.495 * 32.0, 1.2, 1.2}, {0.39 * 32.0, 1.2, 1.2}],
      reliefs: [
        %{"side" => "front", "figures" => 13, "title" => "The Last Supper"},
        %{"side" => "back", "figures" => 2, "title" => "The keys to Peter"},
        %{"side" => "left", "figures" => 3, "title" => "Christ before Pilate"},
        %{"side" => "right", "figures" => 5, "title" => "The three Magi"}
      ],
      sources: %{
        "height" => "#{vi}: 32 m. The owner: from the feet to the top of the halo.",
        "span" => "#{vi}: the arms 18.4 m wide.",
        "hand" => "#{av}: each hand 2.2 m long (the middle finger 1.1 m).",
        "lift" => photo <> ": the arms a little over the level.",
        "steps" => "#{vi}: 133 steps in a spiral from the base to the shoulders.",
        "base_height" => "#{en}: a platform of 4 m (36 m in all). The owner: keep 4 m.",
        "base_width" => "#{av}: the base 12 m long.",
        "rays" => "#{av}: 9 rays of metal in the halo, which are also lightning rods.",
        "material" => "#{av}: reinforced concrete with a render of washed stone.",
        "reliefs" =>
          "#{av}: front the Last Supper, back the keys to Peter, the sides Christ before Pilate and the three Magi.",
        "windows" =>
          photo <> ": three square openings down the front of the robe, at 0.585, 0.495 and 0.39 of the height."
      }
    )
  end

  @doc "The names of the sizes and the choices that an order can give a source for."
  def sized, do: Enum.map(Keyword.keys(@sizes), &Atom.to_string/1) ++ ~w(rays material reliefs windows)

  @doc "A check of the sources of an order: a map of the name of a size to a text."
  def check_sources(raw, path) when is_map(raw) do
    errors =
      for {k, v} <- raw, not (k in sized() and is_binary(v) and String.length(v) <= 500) do
        {"#{path}.#{k}", "must be a size (#{Enum.join(sized(), ", ")}) with a text of at most 500 characters"}
      end

    if errors == [], do: {:ok, raw}, else: {:error, errors}
  end

  def check_sources(_, path), do: {:error, [{path, "must be a map of the name of a size to its source"}]}

  @doc "A check of a short text (the title of a relief)."
  def check_text(raw, _path) when is_binary(raw) and byte_size(raw) <= 200, do: {:ok, raw}
  def check_text(_, path), do: {:error, [{path, "must be a text of at most 200 bytes"}]}

  # --- The figure -----------------------------------------------------------------

  # The posed person, scaled and with its arms to the span: its surfaces
  # (`{points, triangles}`, in m, on its feet at z = 0), its marks (the
  # places of the shoulders, the elbows, the wrists and the head) and its
  # scale.
  defp figure(o) do
    f =
      Detail.with(:mid, fn ->
        Human.person(o.name, gender: o.gender, age: o.age, hair: o.hair, clothes: [], pose: pose(o))
      end)

    f = if o.pose == "arms_out", do: Figure.pose(f, %{}, arm_targets(f, o.lift)), else: f
    frames = Scene.world_frames(%Scene{nodes: f.nodes})
    bone = fn name -> frames[Enum.find_index(f.nodes, &(&1.name == name))].at end
    surfaces = skin(f, frames)
    points = Enum.flat_map(surfaces, &elem(&1, 0))
    {{left, _, _}, {right, _, top}} = Vec.bounds(points)
    neck = bone.("neck_01")
    # The halo: a ring round the head, behind it: its center at 0.45 of
    # the head (from the neck to the top) under the top, its radius 0.68
    # of the head (by eye from the photos).
    hh = top - elem(neck, 2)
    {{_, back, _}, _} = points |> Enum.filter(&(elem(&1, 2) > elem(neck, 2))) |> Vec.bounds()
    {halo_r, halo_c} = {0.68 * hh, {0.0, back, top - 0.45 * hh}}
    s = o.height / if(o.halo, do: elem(halo_c, 2) + halo_r, else: top)

    marks =
      Map.new(~w(upperarm_l lowerarm_l hand_l upperarm_r lowerarm_r hand_r head), &{&1, Vec.scale(bone.(&1), s)})

    # Each side by its own marks: the two arms of the pose are not quite
    # the same.
    side = fn name -> abs(elem(marks[name], 0)) end
    sl = squeeze(o, side.("upperarm_l"), side.("hand_l"), -left * s)
    sr = squeeze(o, side.("upperarm_r"), side.("hand_r"), right * s)
    squeeze = fn {x, _, _} = p -> if x < 0, do: sl.(p), else: sr.(p) end
    move = fn p -> squeeze.(Vec.scale(p, s)) end

    surfaces = for {ps, tris} <- surfaces, do: {Enum.map(ps, move), tris}
    marks = Map.new(marks, fn {k, p} -> {k, squeeze.(p)} end)

    %{
      surfaces: surfaces,
      hands: hands(surfaces, marks, o),
      marks: marks,
      scale: s,
      top: top * s,
      halo: {halo_r * s, Vec.scale(halo_c, s)}
    }
  end

  # The box of the points of each hand of the pose `arms_out`, out from
  # its wrist: the fingers of a person are too thin for a cast, so a mitt
  # (the fingers together, as a sculptor makes them) goes round them.
  defp hands(surfaces, marks, %{pose: "arms_out"}) do
    points = Enum.flat_map(surfaces, &elem(&1, 0))

    for {side, sign} <- [{"l", -1.0}, {"r", 1.0}] do
      xw = elem(marks["hand_" <> side], 0)
      Vec.bounds(Enum.filter(points, fn {x, _, _} -> x * sign > xw * sign end))
    end
  end

  defp hands(_, _, _), do: []

  defp pose(%{pose: "arms_out"}), do: %{}
  defp pose(%{pose: name}), do: name

  # The targets of the hands: straight out from the shoulders, `lift`
  # degrees over the level.
  defp arm_targets(f, lift) do
    frames = Scene.world_frames(%Scene{nodes: f.nodes})
    at = fn name -> frames[Enum.find_index(f.nodes, &(&1.name == name))].at end
    a = lift * :math.pi() / 180

    for {limb, bone, side} <- [{"arm_l", "upperarm_l", -1.0}, {"arm_r", "upperarm_r", 1.0}], into: %{} do
      {limb, Vec.add(at.(bone), {side * 3.0 * :math.cos(a), 0.0, 3.0 * :math.sin(a)})}
    end
  end

  # The triangles of the skin and the hair of the posed person.
  defp skin(%Figure{nodes: nodes, skins: skins}, frames) do
    for n <- nodes, n.skin != nil, skin = Enum.at(skins, n.skin), p <- n.primitives, p.material in [:skin, :hair] do
      bones =
        skin.joints
        |> Enum.zip(skin.inverse_bind)
        |> Enum.map(fn {j, ib} -> Frame.compose(frames[j], ib) end)
        |> List.to_tuple()

      points =
        for {pt, js, ws} <- Enum.zip([p.positions, p.joints, p.weights]) do
          Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
          |> Enum.map(fn {j, w} -> Vec.scale(Frame.point(elem(bones, j), pt), w) end)
          |> Enum.reduce(&Vec.add/2)
        end

      {points, Enum.chunk_every(p.indices, 3)}
    end
  end

  # The change of x of the arms out to the sides: from the shoulder to the
  # wrist by one factor, from the wrist to the tip by another, so that the
  # hand has its length and the span its width.
  defp squeeze(%{span: nil, hand: nil}, _, _, _), do: & &1

  defp squeeze(o, xs, xw, tip) do
    hand = o.hand || tip - xw
    span = o.span || 2 * tip
    ch = hand / (tip - xw)
    ca = (span / 2 - hand - xs) / (xw - xs)

    if ca <= 0,
      do: raise(ArgumentError, "the span #{span} m is too small for the shoulders and the hands of the statue")

    fn {x, y, z} ->
      a = abs(x)

      d =
        cond do
          a <= xs -> a
          a <= xw -> xs + (a - xs) * ca
          true -> xs + (xw - xs) * ca + (a - xw) * ch
        end

      {if(x < 0, do: -d, else: d), y, z}
    end
  end

  # --- The shapes of the statue ------------------------------------------------------

  defp statue_shapes(fig, o, :far), do: {far_form(fig, o) ++ halo(fig, o, :far), nil}

  defp statue_shapes(fig, o, level) do
    {look, matter} = @materials[o.material]
    step = if level == :near, do: o.height / 100, else: o.height / 56
    robe = robe(fig, o)
    grid = Cast.solid(uncovered(fig.surfaces, robe) ++ robe, step)

    grid =
      if o.hollow and level == :near,
        do: Cast.hollow(grid, max(o.wall, 2 * step), openings(fig, o, step)),
        else: grid

    shell = Cast.mesh(grid, look) |> Mesh.matter(matter)
    grilles = if o.hollow and level == :near, do: Enum.flat_map(o.windows, &grille(shell, &1, look, matter)), else: []
    {[shell | grilles ++ halo(fig, o, level)], grid}
  end

  # The grille of a window (by eye from the photos: a square pattern in
  # each opening): a frame and a cross of bars, 0.15 m in from the front
  # of the robe round the opening.
  defp grille(shell, {z, w, h}, look, matter) do
    front =
      shell.points
      |> Enum.filter(fn {x, y, pz} -> abs(x) < w / 2 + 0.5 and abs(pz - z) < h / 2 + 0.5 and y > 0 end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.max()

    {y0, y1, t} = {front - 0.25, front - 0.15, 0.1}
    {x0, x1, z0, z1} = {-w / 2, w / 2, z - h / 2, z + h / 2}

    [
      {{x0, y0, z0}, {x1, y1, z0 + t}},
      {{x0, y0, z1 - t}, {x1, y1, z1}},
      {{x0, y0, z0 + t}, {x0 + t, y1, z1 - t}},
      {{x1 - t, y0, z0 + t}, {x1, y1, z1 - t}},
      {{-t / 2, y0, z0 + t}, {t / 2, y1, z1 - t}},
      {{x0 + t, y0, z - t / 2}, {-t / 2, y1, z + t / 2}},
      {{t / 2, y0, z - t / 2}, {x1 - t, y1, z + t / 2}}
    ]
    |> Enum.map(fn {a, b} -> Shape.box(a, b, look) |> Mesh.matter(matter) end)
  end

  # The surfaces of the person with no triangle that the robe covers (its
  # three points in the robe): the cast takes the head, the hair out of
  # the robe and the feet, not a chest close under the robe.
  defp uncovered(surfaces, []), do: surfaces

  defp uncovered(surfaces, robe) do
    solids = Enum.map(robe, &Contact.solid/1)

    for {points, tris} <- surfaces do
      covered = points |> Enum.map(&Contact.blocked?(&1, solids)) |> List.to_tuple()
      {points, Enum.reject(tris, fn [a, b, c] -> elem(covered, a) and elem(covered, b) and elem(covered, c) end)}
    end
  end

  # The robe: a long column from the neck to the feet, its sleeves along
  # the bones of the arms, and the two long panels at its sides (by eye
  # from the photos of the statue on Núi Nhỏ). In units of the person.
  defp robe(%{scale: _}, %{robe: false}), do: []

  defp robe(%{scale: s, marks: m, hands: hands}, _o) do
    sh = elem(m["upperarm_l"], 2) / s
    neck = elem(m["head"], 2) / s
    yc = 0.01 * s

    column =
      [
        {0.0, 0.215, 0.135},
        {0.06, 0.215, 0.135},
        {0.07, 0.205, 0.13},
        {0.5, 0.19, 0.12},
        {0.95, 0.185, 0.125},
        {sh - 0.12, 0.2, 0.14},
        {sh, 0.215, 0.13},
        {sh + 0.05, 0.17, 0.1},
        {neck, 0.07, 0.07}
      ]
      |> Enum.map(fn {z, hx, hy} -> {{0.0, yc, z * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hx * s, hy * s, 3.5} end)
      |> Shape.loft(:concrete, sides: 24)

    panels =
      for side <- [-1.0, 1.0] do
        Shape.loft(
          [
            {{side * 0.235 * s, yc, (sh - 0.02) * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, 0.035 * s, 0.12 * s, 4.0},
            {{side * 0.23 * s, yc, 0.42 * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, 0.035 * s, 0.11 * s, 4.0}
          ],
          :concrete,
          sides: 16
        )
      end

    sleeves = for side <- ~w(l r), do: sleeve(m["upperarm_" <> side], m["lowerarm_" <> side], m["hand_" <> side], s)
    [column | panels ++ sleeves ++ Enum.map(hands, &mitt/1)]
  end

  # A mitt round the points of a hand out to the side: from the wrist to
  # the tip, a little narrower at the tip.
  defp mitt({{x0, y0, z0}, {x1, y1, z1}}) do
    {c, hy, hz} = {fn x -> {x, (y0 + y1) / 2, (z0 + z1) / 2} end, (y1 - y0) / 2 + 0.02, (z1 - z0) / 2 + 0.02}
    {inner, outer} = if abs(x0) < abs(x1), do: {x0, x1}, else: {x1, x0}
    mid = inner + 0.7 * (outer - inner)

    [{inner, 1.0}, {mid, 1.0}, {outer, 0.75}]
    |> Enum.map(fn {x, k} -> {c.(x), {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, hy * k, hz * k, 4.0} end)
    |> Shape.loft(:concrete, sides: 16)
  end

  # A sleeve: wide at the shoulder (and lower, as it hangs), narrow at the
  # wrist.
  defp sleeve(shoulder, elbow, wrist, s) do
    d1 = Vec.norm(Vec.sub(elbow, shoulder))
    d2 = Vec.norm(Vec.sub(wrist, elbow))

    [
      {Vec.sub(shoulder, Vec.scale(d1, 0.04 * s)), d1, 0.1, 0.14, -0.08},
      {shoulder, d1, 0.1, 0.14, -0.08},
      {elbow, Vec.norm(Vec.add(d1, d2)), 0.075, 0.095, -0.035},
      {Vec.sub(wrist, Vec.scale(d2, 0.01 * s)), d2, 0.06, 0.055, 0.0}
    ]
    |> Enum.map(fn {at, d, hu, hv, down} ->
      v = across(d)
      u = Vec.cross(v, d)
      {Vec.add(at, Vec.scale(v, down * s)), u, v, hu * s, hv * s, 4.0}
    end)
    |> Shape.loft(:concrete, sides: 16)
  end

  # The direction across a bone toward the top (or the front, for a bone
  # that goes up or down).
  defp across(d) do
    hint = if abs(Vec.dot(d, {0.0, 0.0, 1.0})) > 0.9, do: {0.0, 1.0, 0.0}, else: {0.0, 0.0, 1.0}
    Vec.norm(Vec.sub(hint, Vec.scale(d, Vec.dot(hint, d))))
  end

  # The openings of a hollow statue: the windows in the front of the robe,
  # a balcony in the top of each arm near the shoulder, and the shaft of
  # the stair down to the plinth.
  defp openings(%{marks: m, scale: s}, o, step) do
    xs = abs(elem(m["upperarm_l"], 0))
    za = elem(m["upperarm_l"], 2)
    r = o.well / 2 + 0.8

    windows = for {z, w, h} <- o.windows, do: {{-w / 2, 0.0, z - h / 2}, {w / 2, 50.0, z + h / 2}}

    balconies =
      for side <- [-1.0, 1.0] do
        {x0, x1} = {side * (xs + 1.0), side * (xs + 2.5)}
        {{min(x0, x1), -0.8, za}, {max(x0, x1), 0.8, za + 10.0}}
      end

    yc = 0.01 * s
    shaft = {{-r, yc - r, -2.0 * step}, {r, yc + r, 2.5 * step}}
    windows ++ balconies ++ [shaft]
  end

  # The halo: a ring behind the head with the three arms of a cross to
  # the head, and the metal rays out of it (round the top half).
  defp halo(_, %{halo: false}, _), do: []

  defp halo(%{halo: {r, {_, y, zc}}, scale: s}, o, level) do
    {look, matter} = @materials[o.material]
    t = 0.016 * s
    sides = %{near: 24, mid: 12, far: 8}[level]
    frame = Frame.new({0.0, y - t, zc}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0})
    tube = for k <- 0..7, a = 2 * :math.pi() * k / 8, do: {r - t + t * :math.cos(a), t * :math.sin(a)}
    ring = Shape.lathe(tube, look, kind: :ring, sides: sides, frame: frame) |> Mesh.matter(matter)

    arms =
      for {dx, dz} <- [{-1.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], level != :far do
        {a, b} = {0.45 * r, r - t}
        p0 = {dx * a - abs(dz) * t, y - 2 * t, zc + dz * a - abs(dx) * t}
        p1 = {dx * b + abs(dz) * t, y, zc + dz * b + abs(dx) * t}
        {{x0, y0, z0}, {x1, y1, z1}} = Vec.bounds([p0, p1])
        Shape.box({x0, y0, z0}, {x1, y1, z1}, look) |> Mesh.matter(matter)
      end

    arms ++ [ring | rays(r, {0.0, y - t, zc}, s, o.rays, level)]
  end

  # The rays: one up (the lightning rod) when their count is odd, the rest
  # to each side, 10 degrees apart from 10 under the level (by eye from
  # the photos).
  defp rays(_, _, _, _, :far), do: []

  defp rays(r, c, s, n, _level) do
    up = if rem(n, 2) == 1, do: [{90.0, 0.12}], else: []
    side = for i <- 0..(div(n, 2) - 1)//1, a = -10.0 + 10.0 * i, deg <- [a, 180.0 - a], do: {deg, 0.08}

    for {deg, len} <- up ++ side do
      a = deg * :math.pi() / 180
      d = {:math.cos(a), 0.0, :math.sin(a)}

      Shape.cylinder(0.0016 * s, len * s, :steel,
        sides: 6,
        frame: Frame.new(Vec.add(c, Vec.scale(d, r)), d, {0.0, 1.0, 0.0})
      )
      |> Mesh.matter(:steel)
    end
  end

  # The far form: the silhouette from 3 km, in few triangles (R9 of plan
  # 0008): the robe, the arms from hand to hand, the head.
  defp far_form(%{marks: m, scale: s, top: top}, o) do
    {look, matter} = @materials[o.material]
    sh = elem(m["upperarm_l"], 2)
    neck = elem(m["head"], 2)
    tip = abs(elem(m["hand_l"], 0)) + (o.hand || 0.18 * s)

    column =
      Shape.loft(
        for(
          {z, hx, hy} <- [{0.0, 0.215, 0.135}, {sh / s, 0.215, 0.13}, {neck / s, 0.07, 0.07}],
          do: {{0.0, 0.01 * s, z * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hx * s, hy * s, 3.5}
        ),
        look,
        sides: 8
      )

    za = (elem(m["hand_l"], 2) + sh) / 2

    arms =
      Shape.box({-tip, -0.07 * s, za - 0.07 * s}, {tip, 0.07 * s, za + 0.07 * s}, look)

    head = Shape.box({-0.08 * s, -0.09 * s, neck}, {0.08 * s, 0.11 * s, top}, look)
    Enum.map([column, arms, head], &Mesh.matter(&1, matter))
  end

  # --- The stair ---------------------------------------------------------------------

  # The spiral stair inside a hollow statue (by eye from the photo of
  # its inside: the treads go round an open well with a rail at its edge,
  # each from the well to the wall): `steps` treads of 30 degrees (12 to a
  # turn), from the plinth to the floor of the shoulders. Each tread goes
  # 0.1 m into the wall of the cast.
  defp stair_part(%{marks: m, scale: s}, o, grid) do
    r = o.well / 2
    top = elem(m["upperarm_l"], 2) - 0.5
    rise = top / o.steps
    yc = 0.01 * s
    pt = fn rr, a, z -> {rr * :math.cos(a), yc + rr * :math.sin(a), z} end

    wall = fn a, z ->
      Enum.find(Enum.map(1..120, &(r + 0.05 * &1)), r + 1.0, &Cast.inside?(grid, pt.(&1, a, z))) + 0.1
    end

    treads =
      for i <- 0..(o.steps - 1) do
        {a0, a1, z} = {i * :math.pi() / 6, (i + 1) * :math.pi() / 6, (i + 1) * rise}
        out = Enum.min(for a <- [a0, (a0 + a1) / 2, a1], do: wall.(a, z - 0.04))

        loop =
          for {rr, a} <- [{r, a0}, {out, a0}, {out, (a0 + a1) / 2}, {out, a1}, {r, a1}],
              do: Tuple.delete_at(pt.(rr, a, 0.0), 2)

        Shape.prism(loop, 0.08, :concrete, frame: Frame.move({0.0, 0.0, z - 0.08})) |> Mesh.matter(:concrete)
      end

    # The rail at the edge of the well: a post on each third tread and a
    # rail on the posts, 0.9 m over the treads.
    posts =
      for i <- 0..(o.steps - 1)//3 do
        {x, y, z} = pt.(r + 0.05, (i + 0.5) * :math.pi() / 6, (i + 1) * rise)
        Shape.cylinder(0.02, 0.9, :steel, sides: 6, frame: Frame.move({x, y, z})) |> Mesh.matter(:steel)
      end

    line = for i <- 0..o.steps, do: pt.(r + 0.05, (i + 0.5) * :math.pi() / 6, (i + 1) * rise + 0.9)
    rail = Shape.sweep(line, 0.025, :steel, sides: 6) |> Mesh.matter(:steel)

    Part.new("cau_thang", :statue, treads ++ [rail | posts], [@o],
      params: %{"steps" => o.steps, "rise" => Float.round(rise, 3)},
      sources: [
        "The stair: #{o.steps} steps of #{Float.round(rise * 100, 1)} cm, 12 to a turn, round an open well of #{o.well} m with a rail (by eye from the photo of the inside)."
      ]
    )
  end

  defp move_part(%Part{shapes: shapes} = p, frame), do: %{p | shapes: Enum.map(shapes, &Mesh.transform(&1, frame))}

  # --- The base ----------------------------------------------------------------------

  # The outline of the base: a rectangle with round corners, in order
  # round it (counterclockwise from +z).
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

  # The base and the plinth: at near and mid the base has bands at its
  # foot and its top and a frame round each panel, the panels in a recess
  # of 0.15 m with the figures in relief at near; the plinth is round with
  # a curved top.
  defp base_part(o) do
    level = Detail.level()
    {look, matter} = @materials[o.material]
    {w, d, h} = {o.base_width, o.base_depth, o.base_height}

    block =
      cond do
        h <= 0 ->
          []

        level == :far ->
          [Shape.prism(outline(w, d, o.corner, 0.0), h, look)]

        true ->
          [
            Shape.prism(outline(w, d, o.corner, 0.0), 0.6, look),
            Shape.prism(outline(w, d, o.corner, 0.15), h - 1.1, look, frame: Frame.move({0.0, 0.0, 0.6})),
            Shape.prism(outline(w, d, o.corner, 0.0), 0.5, look, frame: Frame.move({0.0, 0.0, h - 0.5}))
          ] ++ frames(o, look) ++ if(level == :near, do: reliefs(o, look), else: [])
      end

    plinth =
      if o.plinth_height > 0 do
        {r, ph} = {o.plinth_radius, o.plinth_height}
        profile = [{0.0, 0.0}, {r, 0.0}, {r, 0.75 * ph}, {0.92 * r, 0.93 * ph}, {0.7 * r, ph}, {0.0, ph}]
        [Shape.lathe(profile, look, sides: 32, frame: Frame.move({0.0, 0.0, h})) |> Mesh.matter(matter)]
      else
        []
      end

    Part.new("be", :statue, Enum.map(block, &Mesh.matter(&1, matter)) ++ plinth, [@o], sources: sources(o))
  end

  # The four sides of the base: their normal, their width, and where
  # their middle is.
  defp sides(o) do
    {hw, hd} = {o.base_width / 2, o.base_depth / 2}

    %{
      "front" => {{0.0, 1.0, 0.0}, o.base_width, {0.0, hd, 0.0}},
      "back" => {{0.0, -1.0, 0.0}, o.base_width, {0.0, -hd, 0.0}},
      "left" => {{-1.0, 0.0, 0.0}, o.base_depth, {-hw, 0.0, 0.0}},
      "right" => {{1.0, 0.0, 0.0}, o.base_depth, {hw, 0.0, 0.0}}
    }
  end

  # The frame of the panel of each side: a pilaster at each end of the
  # panel, in the recess of the middle of the base.
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

  # The figures in relief of each panel: standing figures in a row, each
  # a body and a head that stand 0.12 m out of the recess.
  defp reliefs(o, look) do
    for %{"side" => side, "figures" => count} <- o.reliefs, {n, width, mid} = sides(o)[side], i <- 0..(count - 1) do
      along = Vec.cross({0.0, 0.0, 1.0}, n)
      panel = width - 2 * o.corner - 2.0
      x = -panel / 2 + panel * (i + 0.5) / count
      c = Vec.add(mid, Vec.add(Vec.scale(along, x), Vec.scale(n, -0.09)))
      ph = o.base_height - 1.1
      fw = min(0.3, panel / count * 0.35)
      body = {Vec.add(c, {0.0, 0.0, 0.7}), along, n, fw, 0.06, 3.0}
      shoulders = {Vec.add(c, {0.0, 0.0, 0.6 + 0.62 * ph}), along, n, fw * 1.1, 0.06, 3.0}
      neck = {Vec.add(c, {0.0, 0.0, 0.6 + 0.7 * ph}), along, n, fw * 0.45, 0.05, 2.0}
      head = {Vec.add(c, {0.0, 0.0, 0.6 + 0.85 * ph}), along, n, fw * 0.55, 0.05, 2.0}
      Shape.loft([body, shoulders, neck, head], look, sides: 12)
    end
  end

  # The rail round the top of the base: posts at the corners and between,
  # a top rail, and at near the balusters (by eye from the photos).
  defp rail_part(o) do
    level = Detail.level()
    {hw, hd, h, z} = {o.base_width / 2 - 0.3, o.base_depth / 2 - 0.3, o.rail, o.base_height}
    {look, matter} = @materials[o.material]

    # The four lines of the rail (their middles, 0.15 m thick).
    lines = [
      {{-hw, hd - 0.15}, {hw, hd}},
      {{-hw, -hd}, {hw, -hd + 0.15}},
      {{-hw, -hd + 0.15}, {-hw + 0.15, hd - 0.15}},
      {{hw - 0.15, -hd + 0.15}, {hw, hd - 0.15}}
    ]

    walls =
      for {{x0, y0}, {x1, y1}} <- lines do
        if level == :near,
          do: [
            Shape.box({x0, y0, z}, {x1, y1, z + 0.15}, look),
            Shape.box({x0, y0, z + h - 0.12}, {x1, y1, z + h}, look)
          ],
          else: [Shape.box({x0, y0, z}, {x1, y1, z + h}, look)]
      end

    balusters =
      for {{x0, y0}, {x1, y1}} <- lines, level == :near, n = round(max(x1 - x0, y1 - y0) / 0.3), k <- 1..(n - 1)//1 do
        {cx, cy} = {(x0 + x1) / 2, (y0 + y1) / 2}
        {x, y} = if x1 - x0 > y1 - y0, do: {x0 + (x1 - x0) * k / n, cy}, else: {cx, y0 + (y1 - y0) * k / n}
        Shape.cylinder(0.05, h - 0.27, look, sides: 6, frame: Frame.move({x, y, z + 0.15}))
      end

    shapes = Enum.map(List.flatten(walls) ++ balusters, &Mesh.matter(&1, matter))

    Part.new("lan_can", :statue, shapes, [@o],
      sources: ["The rail: #{h} m high (an estimate), by eye from the photos."]
    )
  end

  # --- The data of the model ------------------------------------------------------------

  defp sources(o) do
    [
      "MakeHuman (CC0): the person of the figure.",
      "The sizes of the order and their sources are in the extras (\"sizes\"); a size with no source is an estimate."
    ] ++ for({_, v} <- Enum.sort(o.sources), do: v)
  end

  # The sizes with their sources, the ports, the collision boxes, the
  # corners of the base for the surface data, the stains.
  defp extras(fig, o, lift) do
    sizes =
      for {key, unit} <- @sizes, v = Map.fetch!(o, key), v != nil do
        name = Atom.to_string(key)
        %{"name" => name, "value" => v, "unit" => unit, "source" => o.sources[name] || "estimate (no source)"}
      end

    rest =
      for name <- ~w(rays material reliefs windows),
          do: %{"name" => name, "value" => choice(o, name), "source" => o.sources[name] || "estimate (no source)"}

    {hw, hd} = {o.base_width / 2, o.base_depth / 2}

    # A statue is cast fixed to its site (its base, or the ground): no
    # check of a stand.
    %{
      "site" => true,
      "sizes" => sizes ++ rest,
      "weathering" => o.weathering / 1,
      "ports" => ports(fig, o, lift),
      "collision" => collision(fig, o, lift),
      "surface" => %{"corners" => [[-hw, -hd], [hw, -hd], [-hw, hd], [hw, hd]]}
    }
  end

  defp choice(o, "windows"), do: for({z, w, h} <- o.windows, do: [z, w, h])
  defp choice(o, "material"), do: Atom.to_string(o.material)
  defp choice(o, name), do: Map.fetch!(o, String.to_existing_atom(name))

  defp port(kind, at, normal, size),
    do: %{"kind" => kind, "at" => Vec.float(at), "normal" => Vec.float(normal), "size" => size}

  # The ports: a light at each corner of the top of the base (the lamps
  # that light the statue at night), the door of the base at its back,
  # and with `hollow` the foot of the stair and a view at each balcony.
  defp ports(%{marks: m}, o, lift) do
    {hw, hd, h} = {o.base_width / 2 - 0.5, o.base_depth / 2 - 0.5, o.base_height}

    lights =
      for x <- [-hw, hw], y <- [-hd, hd], do: port("light", {x, y, h}, {-x, -y, 3 * hw} |> Vec.norm(), [0.3, 0.3, 0.3])

    door = port("door", {0.0, -o.base_depth / 2, 0.0}, {0.0, -1.0, 0.0}, [1.2, 0.2, 2.4])

    inside =
      if o.hollow do
        xs = abs(elem(m["upperarm_l"], 0))
        za = elem(m["upperarm_l"], 2) + lift

        [port("stair", {0.0, 0.0, lift}, {0.0, 0.0, 1.0}, [o.well + 1.6, o.well + 1.6, 2.0])] ++
          for side <- [-1.0, 1.0], do: port("view", {side * (xs + 1.75), 0.0, za}, {0.0, 0.0, 1.0}, [1.5, 1.6, 2.0])
      else
        []
      end

    lights ++ [door | inside]
  end

  # The collision boxes: the base, the plinth, the robe, the arms and the
  # head (the halo and the rays have none: a player does not reach them).
  defp collision(%{marks: m, scale: s, top: top}, o, lift) do
    box = fn name, {x0, y0, z0}, {x1, y1, z1} ->
      %{"name" => name, "at" => {(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2}, "size" => {x1 - x0, y1 - y0, z1 - z0}}
    end

    {hw, hd, r} = {o.base_width / 2, o.base_depth / 2, o.plinth_radius}
    sh = elem(m["upperarm_l"], 2) + lift
    tip = abs(elem(m["hand_l"], 0)) + (o.hand || 0.18 * s)
    neck = elem(m["head"], 2) + lift
    za = (elem(m["hand_l"], 2) + elem(m["upperarm_l"], 2)) / 2 + lift

    [
      box.("be", {-hw, -hd, 0.0}, {hw, hd, o.base_height}),
      box.("de", {-r, -r, o.base_height}, {r, r, lift}),
      box.("ao", {-0.215 * s, -0.125 * s, lift}, {0.215 * s, 0.145 * s, sh}),
      box.("tay", {-tip, -0.1 * s, za - 0.1 * s}, {tip, 0.1 * s, za + 0.1 * s}),
      box.("dau", {-0.09 * s, -0.1 * s, neck}, {0.09 * s, 0.12 * s, top + lift})
    ]
    |> Enum.filter(fn %{"size" => {_, _, h}} -> h > 0 end)
    |> Enum.map(fn b ->
      Map.new(b, fn {k, v} ->
        {k, if(is_tuple(v), do: Tuple.to_list(v) |> Enum.map(&Float.round(&1 / 1, 4)) |> List.to_tuple(), else: v)}
      end)
    end)
  end
end
