defmodule World.Statues do
  @moduledoc """
  The statues of the world (W13 of Vũng Tàu): a figure of the person
  blueprint (`World.People.Human`) at any size and in any pose, in a long
  robe, cast as one solid of concrete or stone (`World.Cast`), with a
  halo, on a base: a round plaza with steps in rings, a block with round
  corners and a front that curves in, panels of gold with figures in
  relief in white frames, a band of letters, small windows with grilles,
  a terrace with a pierced balustrade, and a low dome of 8 faces with a
  stair up its front to the feet.

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
  dome to the shoulders, and openings: the `windows`
  in the front of the robe, a balcony at each shoulder, and the shaft of
  the stair down into the base. The mid and the far levels are solid
  (the inside is closed to the player).

  Each size of an order has its source (`sources`, by the name of the
  size); a size with no source is an estimate, and the receipt says so
  (`"sizes"` in the extras).

  The origin of the model is on the ground at the center of the base;
  the figure looks to +y.
  """
  alias World.{Assembly, Cast, Detail, Figure, Frame, Mesh, Part, Scene, Shape, Vec}
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
    head: nil,
    beard: false,
    material: :concrete,
    hollow: false,
    wall: 0.3,
    steps: 133,
    well: 1.0,
    windows: [],
    plaza_radius: 10.5,
    plaza_steps: 3,
    plaza_rise: 0.15,
    plaza_tread: 0.6,
    base_width: 13.0,
    base_depth: 13.0,
    base_height: 6.5,
    corner: 1.5,
    base_curve: 0.8,
    panel_width: 8.0,
    panel_height: 3.0,
    letters: true,
    grilles: 2,
    reliefs: [],
    terrace_rail: 1.0,
    dome_width: 8.0,
    dome_height: 3.0,
    dome_sides: 8,
    dome_stair: 1.2,
    weathering: 0.5,
    sources: %{}
  ]

  # The sizes of an order, with their units, for the receipt.
  @sizes [
    height: "m",
    span: "m",
    hand: "m",
    lift: "deg",
    head: "m",
    wall: "m",
    steps: "steps",
    well: "m",
    plaza_radius: "m",
    plaza_steps: "steps",
    plaza_rise: "m",
    plaza_tread: "m",
    base_width: "m",
    base_depth: "m",
    base_height: "m",
    corner: "m",
    base_curve: "m",
    panel_width: "m",
    panel_height: "m",
    grilles: nil,
    terrace_rail: "m",
    dome_width: "m",
    dome_height: "m",
    dome_sides: nil,
    dome_stair: "m"
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
  opening over the feet, m); the plaza: `plaza_radius` (0: no plaza),
  `plaza_steps`, `plaza_rise` and `plaza_tread` (each ring step); the
  block: `base_width`, `base_depth` and `base_height` (0: no block),
  `corner` (the radius of its round corners), `base_curve` (how far its
  front curves in at the middle), `panel_width` and `panel_height` (the
  panel of each relief), `letters` (the band of letters over each panel),
  `grilles` (the small windows under the panel of the front), `reliefs`
  (a list of `%{"side" => front | back | left | right, "figures" => n,
  "title" => text}`); the terrace: `terrace_rail` (the height of its
  balustrade; 0: none); the dome: `dome_width` (across its faces),
  `dome_height` (0: no dome), `dome_sides` and `dome_stair` (the width
  of its stair); `weathering` (0 to 1: the stains of the sea air,
  for the shader of an app) and `sources` (a map of the name of a size to
  its source).
  """
  def statue(opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    level = Detail.level()
    {_, _, lift} = levels(o)
    fig = figure(o)

    base = base_part(o, fig)
    {shapes, grid} = statue_shapes(fig, o, level)
    up = Frame.move({0.0, 0.0, lift})
    tuong = Part.new(o.name, :statue, Enum.map(shapes, &Mesh.transform(&1, up)), [@o], sources: sources(o))
    stair = if o.hollow and level == :near, do: [stair_part(fig, o, grid) |> move_part(up)], else: []
    rail = if o.terrace_rail > 0 and o.base_height > 0 and level != :far, do: [rail_part(o)], else: []
    # With no plaza, no block and no dome, the statue is the root.
    parts = if(base.shapes == [], do: [], else: [base]) ++ [tuong] ++ stair ++ rail
    [root | rest] = parts

    asm = Assembly.new(o.name, root, root: root.name, kind: :statue, sources: sources(o), extras: extras(fig, o, lift))
    Enum.reduce(rest, asm, fn p, a -> Assembly.add(a, p.name, p, at: "o", port: "o") end)
  end

  @doc """
  The statue of Christ the King on Núi Nhỏ, Vũng Tàu (Tượng Chúa Kitô
  Vua, 1974 to 1993): 32 m from the feet to the top of the halo, the
  arms 18.4 m from hand to hand, 133 steps inside to the shoulders, on a
  round plaza, a block of 6.5 m with four panels in relief, a terrace and
  a low dome. Each size has its source, or says that it is an estimate.
  """
  def nui_nho do
    vi = "vi.wikipedia, Tượng Chúa Kitô Vua (Vũng Tàu)"
    en = "en.wikipedia, Christ of Vũng Tàu"
    av = "amazingvietnam.vn (2010), the statue of Christ on Núi Nhỏ"
    photo = "by eye from the photo Statue_of_Jesus_in_Vung_Tau.jpg (Wikimedia Commons, Category:Christ of Vung Tau)"
    lm = "measured from photos (Vung_Tau landmarks.md)"

    statue(
      name: "tuong_chua_kito_vua",
      height: 32.0,
      span: 18.4,
      hand: 2.2,
      head: 4.0,
      beard: true,
      hollow: true,
      steps: 133,
      plaza_radius: 10.5,
      plaza_steps: 3,
      base_width: 13.0,
      base_depth: 13.0,
      base_height: 6.5,
      base_curve: 0.8,
      panel_width: 8.0,
      panel_height: 3.0,
      grilles: 2,
      dome_width: 8.0,
      dome_height: 3.0,
      dome_sides: 8,
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
        "head" =>
          "#{lm}, photo 3: about 4 m from the top of the head to the end of the beard, the face about 1.6 m wide; the hair to the shoulders, a beard.",
        "hand" => "#{av}: each hand 2.2 m long (the middle finger 1.1 m).",
        "lift" => photo <> ": the arms a little over the level.",
        "steps" => "#{vi}: 133 steps in a spiral from the base to the shoulders.",
        "plaza_radius" => "#{lm}, photo 4: a round plaza about 21 m across; ±15%.",
        "plaza_steps" => "#{lm}, photo 1: 3 steps in rings round the base (15 cm each, an estimate).",
        "base_height" =>
          "#{lm}, photo 1: the block from the plaza to the terrace about 6.5 m (the relief of 3 m, its frame, the band of letters, the small windows, the foot band); ±15%. #{en}: a platform of 4 m (36 m in all), which does not agree.",
        "base_width" => "#{lm}: a block about 12 m to 14 m wide, with round corners. #{av}: the base 12 m long.",
        "base_depth" => "#{lm}: a block about 12 m to 14 m wide (photo 4: about square).",
        "base_curve" => "#{lm}: the front of the block is a little curved (photos 1, 4: in between its corner piers).",
        "panel_width" => "#{lm}: a wide relief in gold color, about 8 m × 3 m, in a white frame.",
        "panel_height" => "#{lm}: a wide relief in gold color, about 8 m × 3 m, in a white frame.",
        "grilles" => "#{lm}: small square windows with grilles under the relief (photo 1: two).",
        "terrace_rail" => "#{lm}: a terrace with 8 sides and a pierced balustrade, about 11 m to 14 m wide.",
        "dome_width" => "#{lm}: a low dome with 8 faces, about 8 m wide.",
        "dome_height" =>
          "#{lm}, photo 1: about 3 m with its drum of 0.6 m, from the face of the dome and the view down of about 45 degrees; ±15%.",
        "dome_sides" => "#{lm}: a low dome with 8 faces.",
        "dome_stair" => "#{lm}: a narrow stair up the front of the dome to the feet (1.2 m, an estimate).",
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
  def check_sources(raw, path), do: World.Sizes.check(raw, path, sized())

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

    surfaces = for {ps, tris, mat} <- surfaces, do: {Enum.map(ps, move), tris, mat}
    marks = Map.new(marks, fn {k, p} -> {k, squeeze.(p)} end)
    {detail, head_top} = head(o, detail(o, surfaces, move), marks, s, top * s)

    %{
      surfaces: surfaces,
      detail: detail,
      hands: hands(surfaces, marks, o),
      marks: marks,
      scale: s,
      top: head_top,
      halo: {halo_r * s, Vec.scale(halo_c, s)}
    }
  end

  # The surfaces of the figure for the fine casts of the head and of the
  # hands (in a robe): of the person at near (the full mesh of MakeHuman,
  # with the shapes of the face) at the level near, else of the figure.
  defp detail(%{robe: false}, _surfaces, _move), do: nil

  defp detail(o, surfaces, move) do
    if Detail.level() == :near do
      f =
        Detail.with(:near, fn ->
          Human.person(o.name, gender: o.gender, age: o.age, hair: o.hair, clothes: [], pose: pose(o))
        end)

      f = if o.pose == "arms_out", do: Figure.pose(f, %{}, arm_targets(f, o.lift)), else: f
      frames = Scene.world_frames(%Scene{nodes: f.nodes})
      for {ps, tris, mat} <- skin(f, frames), do: {Enum.map(ps, move), tris, mat}
    else
      surfaces
    end
  end

  # The head of a statue in a robe: with `head`, smaller than the head of
  # the person, so that `head` m go from its top to the end of its beard
  # (a beard of 0.32 of the head, from the chin): each point over the head
  # bone moves to it (the jaw and the chin too, the neck under them a
  # little less, the hair all of it). The hair is a solid mass to the shoulders (the cards of the hair
  # of a person cast as thin sheets), and with `beard` a beard goes on the
  # chin. Gives the surfaces, with the solids of the hair and the beard,
  # and the new top.
  defp head(_o, nil, _marks, _s, top), do: {nil, top}

  defp head(o, detail, marks, s, top) do
    {px, py, pz} = pivot = marks["head"]
    skin = for {ps, _, :skin} <- detail, p <- ps, do: p

    chin =
      skin
      |> Enum.filter(fn {x, y, z} -> abs(x - px) < 0.015 * s and y > py + 0.03 * s and z > pz - 0.02 * s end)
      |> Enum.map(&elem(&1, 2))
      |> Enum.min()

    k = if o.head, do: o.head / (1.32 * (top - chin)), else: 1.0

    move = fn {_, _, z} = p, mat ->
      w = if mat == :hair, do: 1.0, else: min(max((z - pz + 0.1 * s) / (0.06 * s), 0.0), 1.0)
      Vec.add(p, Vec.scale(Vec.sub(p, pivot), w * (k - 1)))
    end

    detail = for {ps, tris, mat} <- detail, do: {Enum.map(ps, &move.(&1, mat)), tris, mat}
    {top, chin} = {pz + k * (top - pz), pz + k * (chin - pz)}
    hair = for {ps, _, :hair} <- detail, p <- ps, do: p
    skull = for {ps, _, :skin} <- detail, {_, _, z} = p <- ps, z > pz, do: p
    mass = hair_mass(hair, skull, {py, elem(marks["upperarm_l"], 2), chin, top}, s)

    front =
      for(
        {ps, _, :skin} <- detail,
        {x, y, z} <- ps,
        abs(x - px) < 0.015 * s and z > chin and z < chin + 0.05 * k * s,
        do: y
      )
      |> Enum.max()

    beard = if o.beard and o.head, do: Enum.map(beard(px, front, chin, top - o.head, k * s), &{:solid, &1}), else: []
    {Enum.reject(detail, &(elem(&1, 2) == :hair)) ++ [{:solid, core(pivot, top, k * s, s)}] ++ mass ++ beard, top}
  end

  # The mass of the hair, a hood round the skull: a loft of an ellipse for
  # each slab of the skull from the shoulders to its top, out of it by the
  # thickness of the hair (0.012 of the figure); over the ears round the
  # slab of the skull, under them straight down to the shoulders as wide
  # as the skull; its front at the hairline over the brow, else behind the
  # cheeks (the face shows); a cap over the top.
  defp hair_mass([], _, _, _), do: []

  defp hair_mass(_hair, skull, {py, shoulders, chin, top}, s) do
    t = 0.012 * s
    n = 12
    {brow, ears} = {chin + 0.82 * (top - chin), chin + 0.45 * (top - chin)}
    {{sx0, sy0, _}, {sx1, sy1, sz1}} = Vec.bounds(skull)
    dz = (top - shoulders) / n

    # The points of the skull in a slab; a slab over the skull takes the
    # top of the skull.
    slab = fn z0, z1 ->
      {{x0, y0, _}, {x1, y1, _}} =
        skull |> Enum.filter(fn {_, _, z} -> z >= min(z0, sz1 - dz) and (z < z1 or z1 > sz1) end) |> Vec.bounds()

      {x0, x1, y0, y1}
    end

    sections =
      for i <- 0..(n - 1) do
        {z0, z1} = {shoulders + i * dz, shoulders + (i + 1) * dz}
        z = (z0 + z1) / 2
        {x0, x1, y0, y1} = if z > ears, do: slab.(z0, z1), else: {sx0, sx1, sy0, sy1}
        front = if z > brow, do: y1 - 0.02 * s, else: py + 0.015 * s
        {x0, x1, y0} = {x0 - t, x1 + t, y0 - t}
        {{(x0 + x1) / 2, (y0 + front) / 2, z}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, (x1 - x0) / 2, (front - y0) / 2, 2.0}
      end

    {{cx, cy, _}, u, v, hx, hy, p} = List.last(sections)
    cap = [{{cx, cy, top + 0.6 * t}, u, v, 0.55 * hx, 0.55 * hy, p}, {{cx, cy, top + t}, u, v, 0.1 * hx, 0.1 * hy, p}]
    [{:solid, Shape.loft(sections ++ cap, :concrete, sides: 32)}]
  end

  # The core of the head: a solid in the neck and the skull, so that the
  # cast fills the head behind the face (the skin of the head is open at
  # the neck).
  defp core({x, y, z}, top, u, s) do
    [
      {z - 0.07 * s, 0.045 * s, 0.045 * s},
      {z, 0.055 * s, 0.06 * s},
      {(z + top) / 2, 0.055 * u, 0.065 * u},
      {top - 0.035 * u, 0.035 * u, 0.045 * u}
    ]
    |> Enum.map(fn {zz, hx, hy} -> {{x, y + 0.01 * s, zz}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hx, hy, 2.0} end)
    |> Shape.loft(:concrete, sides: 32)
  end

  # The beard (by eye from photo 3 of Vung_Tau landmarks.md): along the
  # jaw behind the lips, over the chin, down to a point at `tip`; and a
  # mustache over the upper lip (a thin tube). In units of the head (`u`).
  defp beard(x, front, chin, tip, u) do
    beard =
      [
        {chin + 0.025 * u, front - 0.075 * u, 0.056 * u, 0.034 * u},
        {chin + 0.005 * u, front - 0.04 * u, 0.047 * u, 0.036 * u},
        {chin - 0.03 * u, front - 0.032 * u, 0.034 * u, 0.03 * u},
        {(chin + tip) / 2, front - 0.032 * u, 0.02 * u, 0.02 * u},
        {tip, front - 0.035 * u, 0.005 * u, 0.005 * u}
      ]
      |> Enum.map(fn {z, y, hx, hy} -> {{x, y, z}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hx, hy, 2.0} end)
      |> Shape.loft(:concrete, sides: 32)

    zm = chin + 0.042 * u
    ym = front - 0.004 * u

    mustache =
      Shape.sweep(
        [{x - 0.038 * u, ym - 0.012 * u, zm - 0.014 * u}, {x, ym, zm}, {x + 0.038 * u, ym - 0.012 * u, zm - 0.014 * u}],
        0.008 * u,
        :concrete,
        sides: 12
      )

    [beard, mustache]
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

  # The triangles of the skin, the hair and the eyes (they close the holes
  # of the skin for the cast) of the posed person.
  defp skin(%Figure{nodes: nodes, skins: skins}, frames) do
    for n <- nodes,
        n.skin != nil,
        skin = Enum.at(skins, n.skin),
        p <- n.primitives,
        p.material in [:skin, :hair, :eyes] do
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

      {points, Enum.chunk_every(p.indices, 3), p.material}
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
    {robe, mitts} = robe(fig, o)

    # In a robe, the head and the hands are casts of their own on a fine
    # grid (about 3 cm for a statue of 32 m at near, 10 cm at mid), and
    # the robe is the cast of the figure; else the person is one cast.
    {main, details} =
      if robe == [] do
        {uncovered(fig), []}
      else
        fine = if level == :near, do: o.height / 1000, else: o.height / 320
        {robe, Enum.map(details(fig, mitts), &(Cast.solid(&1, fine) |> Cast.mesh(look) |> Mesh.matter(matter)))}
      end

    grid = Cast.solid(main, step)

    grid =
      if o.hollow and level == :near,
        do: Cast.hollow(grid, max(o.wall, 2 * step), openings(fig, o, step)),
        else: grid

    shell = Cast.mesh(grid, look) |> Mesh.matter(matter)
    grilles = if o.hollow and level == :near, do: Enum.flat_map(o.windows, &grille(shell, &1, look, matter)), else: []
    {[shell | details ++ grilles ++ halo(fig, o, level)], grid}
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

  # The surfaces of the person with no robe: all of them, in one cast.
  defp uncovered(%{surfaces: surfaces}), do: Enum.map(surfaces, fn {ps, tris, _} -> {ps, tris} end)

  # The surfaces of the fine casts of a figure in a robe: the head (the
  # mass of the hair, the head and the neck, its core, the beard), and each
  # hand out of its sleeve.
  defp details(%{detail: detail, marks: m, scale: s}, mitts) do
    {hx, _, hz} = m["head"]

    pick = fn test ->
      for {ps, tris, _} <- detail do
        t = ps |> Enum.map(test) |> List.to_tuple()
        {ps, Enum.filter(tris, fn tri -> Enum.any?(tri, &elem(t, &1)) end)}
      end
    end

    solids = for {:solid, mesh} <- detail, do: mesh
    # The head with its jaw, and the neck under it (not the shoulders: the
    # robe has them).
    head =
      solids ++
        pick.(fn {x, _, z} ->
          (z > hz - 0.04 * s and abs(x - hx) < 0.09 * s) or (z > hz - 0.07 * s and abs(x - hx) < 0.05 * s)
        end)

    # Each hand is its mitt: it covers the fingers of the person.
    [head | Enum.map(mitts, &[&1])]
  end

  # The robe: a straight column with a flat front from the neck to the
  # feet, its sleeves along the bones of the arms, and the two long panels
  # at its sides to a little over the feet (Vung_Tau landmarks.md: the
  # column 3.7 m to 4.5 m wide at the feet and 4.5 m to 5 m at the top).
  # In units of the person.
  defp robe(%{scale: _}, %{robe: false}), do: {[], []}

  defp robe(%{scale: s, marks: m, hands: hands}, _o) do
    sh = elem(m["upperarm_l"], 2) / s
    neck = elem(m["head"], 2) / s
    yc = 0.01 * s

    column =
      [
        {0.0, 0.119, 0.085},
        {0.06, 0.119, 0.085},
        {0.07, 0.117, 0.083},
        {0.5, 0.122, 0.085},
        {0.95, 0.128, 0.088},
        {sh - 0.12, 0.134, 0.092},
        {sh, 0.136, 0.09},
        {sh + 0.05, 0.11, 0.075},
        {neck, 0.055, 0.055}
      ]
      |> Enum.map(fn {z, hx, hy} -> {{0.0, yc, z * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hx * s, hy * s, 3.5} end)
      |> Shape.loft(:concrete, sides: 24)

    panels =
      for side <- [-1.0, 1.0] do
        Shape.loft(
          [
            {{side * 0.148 * s, yc, (sh - 0.02) * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, 0.02 * s, 0.08 * s, 4.0},
            {{side * 0.139 * s, yc, 0.03 * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, 0.02 * s, 0.075 * s, 4.0}
          ],
          :concrete,
          sides: 16
        )
      end

    sleeves = for side <- ~w(l r), do: sleeve(m["upperarm_" <> side], m["lowerarm_" <> side], m["hand_" <> side], s)
    {[column | panels ++ sleeves], Enum.map(hands, &mitt/1)}
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
  # the stair down to the dome.
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
          {z, hx, hy} <- [{0.0, 0.16, 0.085}, {sh / s, 0.168, 0.09}, {neck / s, 0.055, 0.055}],
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
  # turn), from the dome to the floor of the shoulders. Each tread goes
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

  # The heights of the base: the top of the plaza, of the block (the
  # floor of the terrace) and of the dome (the feet of the figure).
  defp levels(o) do
    zp = if o.plaza_radius > 0, do: o.plaza_steps * o.plaza_rise, else: 0.0
    zb = zp + o.base_height
    {zp, zb, zb + o.dome_height}
  end

  # The points of a curve at the level now.
  defp curve_steps, do: %{near: 8, mid: 4, far: 2}[Detail.level()]

  # The half of the front between its corner piers: the part that curves
  # in (`base_curve` m at its middle).
  defp front_half(o), do: max(o.base_width / 2 - o.corner - 0.5, 0.0)

  defp curve(o, x) do
    a = front_half(o)
    if abs(x) < a, do: o.base_curve * (1 - x * x / (a * a)), else: 0.0
  end

  defp face_y(o, x), do: o.base_depth / 2 - curve(o, x)

  # The outline of the block, in order round it (counterclockwise from
  # +z): a rectangle with round corners (`n` steps each; 1 gives the 8
  # sides of the terrace), the front curved in between its corner piers.
  defp block_outline(o, inset, n) do
    {hw, hd, r} = {o.base_width / 2 - inset, o.base_depth / 2 - inset, max(o.corner - inset, 0.01)}
    a = front_half(o)

    arc = fn cx, cy, a0 ->
      for k <- 0..n, t = (a0 + 90.0 * k / n) * :math.pi() / 180, do: {cx + r * :math.cos(t), cy + r * :math.sin(t)}
    end

    m = curve_steps()
    front = if a > 0, do: for(k <- 0..(2 * m), x = a - a * k / m, do: {x, face_y(o, x) - inset}), else: []

    arc.(hw - r, hd - r, 0.0) ++
      front ++ arc.(-hw + r, hd - r, 90.0) ++ arc.(-hw + r, -hd + r, 180.0) ++ arc.(hw - r, -hd + r, 270.0)
  end

  # The base: the plaza with its steps in rings, the block (a band at its
  # foot and at its top, its middle in a recess of 0.15 m), the panels of
  # the reliefs in their frames with the band of letters over them, the
  # small windows with grilles under the panel of the front, and the dome
  # with its stair. At far: the plaza, the block and the dome.
  defp base_part(o, fig) do
    level = Detail.level()
    {look, matter} = @materials[o.material]
    {zp, zb, _} = levels(o)
    h = o.base_height

    block =
      cond do
        h <= 0 ->
          []

        level == :far ->
          [Shape.prism(block_outline(o, 0.0, 1), h, look, frame: Frame.move({0.0, 0.0, zp}))]

        true ->
          [
            Shape.prism(block_outline(o, 0.0, 4), 0.6, look, frame: Frame.move({0.0, 0.0, zp})),
            Shape.prism(block_outline(o, 0.15, 4), h - 1.1, look, frame: Frame.move({0.0, 0.0, zp + 0.6})),
            Shape.prism(block_outline(o, 0.0, 4), 0.5, look, frame: Frame.move({0.0, 0.0, zb - 0.5}))
          ] ++ panels(o, look) ++ grilles(o, look, level)
      end

    shapes = plaza(o, look) ++ block ++ dome(o, fig, look, zb, level)
    Part.new("be", :statue, Enum.map(shapes, &Mesh.matter(&1, matter)), [@o], sources: sources(o))
  end

  # The plaza: a round floor with `plaza_steps` steps in rings up to the
  # block, each `plaza_rise` m high and `plaza_tread` m deep.
  defp plaza(%{plaza_radius: r} = o, look) when r > 0 do
    {n, rise, t} = {o.plaza_steps, o.plaza_rise, o.plaza_tread}

    rings =
      if Detail.level() == :far,
        do: [{r, 0.0}, {r, n * rise}],
        else: for(k <- 1..n, rk = r - (k - 1) * t, p <- [{rk, (k - 1) * rise}, {rk, k * rise}], do: p)

    sides = if Detail.level() == :far, do: 40, else: 64
    [Shape.lathe([{0.0, 0.0} | rings] ++ [{0.0, n * rise}], look, sides: sides)]
  end

  defp plaza(_o, _look), do: []

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

  # A strip on a side of the block: from `u0` to `u1` along it, from `d0`
  # to `d1` in from its face (less than 0: out of it), from `z0` to `z1`.
  # On the front it follows the curve.
  defp strip(o, "front", {u0, u1}, {d0, d1}, {z0, z1}, role) do
    n = curve_steps()
    xs = for k <- 0..n, do: u1 - (u1 - u0) * k / n
    loop = for(x <- xs, do: {x, face_y(o, x) - d0}) ++ for(x <- Enum.reverse(xs), do: {x, face_y(o, x) - d1})
    Shape.prism(loop, z1 - z0, role, frame: Frame.move({0.0, 0.0, z0}))
  end

  defp strip(o, side, {u0, u1}, {d0, d1}, {z0, z1}, role) do
    {n, _, mid} = sides(o)[side]
    along = Vec.cross({0.0, 0.0, 1.0}, n)
    at = fn u, d -> Vec.add(Vec.add(mid, Vec.scale(along, u)), Vec.scale(n, -d)) end
    {{x0, y0, _}, {x1, y1, _}} = Vec.bounds([at.(u0, d0), at.(u1, d1)])
    Shape.box({x0, y0, z0}, {x1, y1, z1}, role)
  end

  # The heights of a panel: its foot and its top, the foot of the band of
  # letters over it; no panel in a block too low for one.
  defp panel_heights(o) do
    {zp, zb, _} = levels(o)
    zl = if o.letters, do: zb - 1.1, else: zb - 0.5
    top = zl - 0.2
    floor = zp + 0.85 + if(o.grilles > 0, do: 1.2, else: 0.2)
    ph = min(o.panel_height, top - floor)
    if ph >= 0.3, do: {top - ph, top, zl}, else: nil
  end

  # The width of the panel of a side.
  defp panel_width("front", o), do: min(o.panel_width, 2 * front_half(o) - 0.8)
  defp panel_width(side, o), do: min(o.panel_width, elem(sides(o)[side], 1) - 2 * o.corner - 1.0)

  # The panel of each side with a relief: the relief of gold in the
  # recess, its white frame (two sides, a head, a sill out of the face),
  # the band of letters over it (the letters at near), and the figures.
  defp panels(o, look) do
    case panel_heights(o) do
      nil ->
        []

      {z0, z1, zl} ->
        Enum.flat_map(o.reliefs, fn %{"side" => side} = relief ->
          w = panel_width(side, o)
          f = w / 2 + 0.35
          s = fn u, d, z, role -> strip(o, side, u, d, z, role) end

          frame = [
            s.({-w / 2, w / 2}, {0.08, 0.2}, {z0, z1}, :gold),
            s.({-f, -w / 2}, {-0.05, 0.2}, {z0 - 0.25, z1 + 0.2}, look),
            s.({w / 2, f}, {-0.05, 0.2}, {z0 - 0.25, z1 + 0.2}, look),
            s.({-w / 2, w / 2}, {-0.05, 0.2}, {z1, z1 + 0.2}, look),
            s.({-f, f}, {-0.3, 0.2}, {z0 - 0.25, z0}, look)
          ]

          letters =
            cond do
              not o.letters ->
                []

              Detail.level() == :near ->
                n = trunc(2 * f / 0.42)

                [s.({-f, f}, {-0.02, 0.2}, {zl, zl + 0.6}, look)] ++
                  for k <- 0..(n - 1), u = -f + 2 * f * (k + 0.5) / n do
                    s.({u - 0.11, u + 0.11}, {-0.06, 0.0}, {zl + 0.12, zl + 0.48}, :dark)
                  end

              true ->
                [s.({-f, f}, {-0.02, 0.2}, {zl, zl + 0.6}, look)]
            end

          frame ++ letters ++ figures(o, relief, w, {z0, z1})
        end)
    end
  end

  # The figures in relief of a panel, of gold as the panel: standing
  # figures in a row, each a body and a head that stand 0.06 m out of the
  # panel (at near).
  defp figures(o, %{"side" => side, "figures" => count}, w, {z0, z1}) do
    if Detail.level() == :near do
      {n, _, mid} = sides(o)[side]
      along = Vec.cross({0.0, 0.0, 1.0}, n)
      ph = z1 - z0
      fw = min(0.3, w / count * 0.35)

      for i <- 0..(count - 1) do
        x = -w / 2 + w * (i + 0.5) / count
        dy = if side == "front", do: -curve(o, x), else: 0.0
        c = Vec.add(Vec.add(mid, {0.0, dy, 0.0}), Vec.add(Vec.scale(along, x), Vec.scale(n, -0.08)))
        at = fn k -> Vec.add(c, {0.0, 0.0, z0 + k * ph}) end

        [{0.05, 1.0, 3.0}, {0.62, 1.1, 3.0}, {0.7, 0.45, 2.0}, {0.85, 0.55, 2.0}]
        |> Enum.map(fn {k, wk, p} -> {at.(k), along, n, fw * wk, 0.06, p} end)
        |> Shape.loft(:gold, sides: 12)
      end
    else
      []
    end
  end

  # The small windows under the panel of the front: a dark square and, at
  # near, a grille of bars in a frame.
  defp grilles(%{grilles: g} = o, look, level) when g > 0 do
    case panel_heights(o) do
      nil ->
        []

      {z0, _, _} ->
        w = panel_width("front", o)
        zc = z0 - 0.25 - 0.6

        for k <- 0..(g - 1), x = -w / 2 + w * (k + 0.5) / g do
          dark = strip(o, "front", {x - 0.4, x + 0.4}, {0.12, 0.3}, {zc - 0.4, zc + 0.4}, :dark)

          bars =
            if level == :near do
              s = fn u, z -> strip(o, "front", u, {0.06, 0.12}, z, look) end

              [
                s.({x - 0.4, x - 0.33}, {zc - 0.4, zc + 0.4}),
                s.({x + 0.33, x + 0.4}, {zc - 0.4, zc + 0.4}),
                s.({x - 0.33, x + 0.33}, {zc - 0.4, zc - 0.33}),
                s.({x - 0.33, x + 0.33}, {zc + 0.33, zc + 0.4})
              ] ++
                for(t <- [-0.13, 0.13], do: s.({x + t - 0.03, x + t + 0.03}, {zc - 0.33, zc + 0.33})) ++
                for(t <- [-0.13, 0.13], do: s.({x - 0.33, x + 0.33}, {zc + t - 0.03, zc + t + 0.03}))
            else
              []
            end

          [dark | bars]
        end
        |> List.flatten()
    end
  end

  defp grilles(_o, _look, _level), do: []

  # The dome on the terrace under the feet: a drum and a low dome of
  # `dome_sides` faces, one face to the front, `dome_width` m across its
  # faces; and the narrow stair up its front to the feet (not at far).
  defp dome(%{dome_height: dh} = o, fig, look, zb, level) when dh > 0 do
    n = o.dome_sides
    ap = o.dome_width / 2
    rc = ap / :math.cos(:math.pi() / n)
    drum = min(0.6, dh / 4)
    rt = 0.42 * rc
    # The faces curve in from the drum to the feet (by eye from photos 1
    # and 5): the part of the radius and of the height at each point.
    curve =
      if level == :far,
        do: [{1.0, 0.0}, {0.0, 1.0}],
        else: [{1.0, 0.0}, {0.86, 0.3}, {0.62, 0.6}, {0.34, 0.85}, {0.0, 1.0}]

    profile =
      [{0.0, 0.0}, {rc, 0.0}] ++
        for({kr, kz} <- curve, do: {rt + (rc - rt) * kr, drum + (dh - drum) * kz}) ++ [{0.0, dh}]

    frame = Frame.compose(Frame.move({0.0, 0.0, zb}), Frame.turn({0.0, 0.0, 1.0}, 180.0 / n))
    # The faces at each level: a dome of 8 faces has 8 at far too.
    shell = Detail.with(:near, fn -> Shape.lathe(profile, look, sides: n, frame: frame) end)
    [shell | dome_stair(o, fig, look, {zb, dh, ap, rt}, level)]
  end

  defp dome(_o, _fig, _look, _zb, _level), do: []

  # The stair up the front of the dome: from the terrace in front of the
  # drum to the top of the dome at the robe, `dome_stair` m wide, risers
  # of at most 18 cm (blocks at near, one wedge at mid).
  defp dome_stair(o, %{scale: s}, look, {zb, dh, ap, rt}, level) do
    w = o.dome_stair
    {y0, y1} = {ap + 0.3, max(rt, 0.145 * s)}
    n = ceil(dh / 0.18)
    {rise, tread} = {dh / n, (y0 - y1) / n}

    case level do
      :near ->
        for k <- 1..n do
          Shape.box({-w / 2, y0 - k * tread, zb}, {w / 2, y0 - (k - 1) * tread, zb + k * rise}, look)
        end

      :mid ->
        frame = Frame.new({-w / 2, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0})
        [Shape.prism([{y0, zb}, {y1, zb}, {y1, zb + dh}], w, look, frame: frame)]

      :far ->
        []
    end
  end

  # The terrace on the block: a pierced balustrade along its 8 sides and
  # its curved front, 0.35 m in from the edge: a foot rail, a top rail
  # and rings between them at near; a low wall at mid.
  defp rail_part(o) do
    level = Detail.level()
    {look, matter} = @materials[o.material]
    {_, z, _} = levels(o)
    h = o.terrace_rail
    loop = block_outline(o, 0.35, 1)

    segments =
      for {{x0, y0}, {x1, y1}} <- Enum.zip(loop, tl(loop) ++ [hd(loop)]),
          :math.sqrt((x1 - x0) ** 2 + (y1 - y0) ** 2) > 0.05,
          do: {{x0, y0, 0.0}, {x1, y1, 0.0}}

    shapes =
      Enum.flat_map(segments, fn {a, b} ->
        len = Vec.len(Vec.sub(b, a))
        e = Vec.scale(Vec.sub(b, a), 1 / len)
        # In: to the left of the side (the outline goes counterclockwise).
        inward = Vec.cross({0.0, 0.0, 1.0}, e)

        quad = fn t ->
          [a, b, Vec.add(b, Vec.scale(inward, t)), Vec.add(a, Vec.scale(inward, t))]
          |> Enum.map(&Tuple.delete_at(&1, 2))
        end

        rail = fn z0, z1 -> Shape.prism(quad.(0.2), z1 - z0, look, frame: Frame.move({0.0, 0.0, z0})) end

        if level == :near do
          rr = (h - 0.27) / 2 - 0.03
          m = max(trunc(len / (2 * rr + 0.1)), 1)

          tube =
            for k <- 0..7, t = 2 * :math.pi() * k / 8, do: {rr - 0.035 + 0.035 * :math.cos(t), 0.035 * :math.sin(t)}

          rings =
            for i <- 0..(m - 1) do
              c = Vec.add(Vec.add(a, Vec.scale(e, len * (i + 0.5) / m)), Vec.scale(inward, 0.1))
              at = Vec.add(c, {0.0, 0.0, z + 0.15 + (h - 0.27) / 2})
              Shape.lathe(tube, look, kind: :ring, sides: 12, frame: Frame.new(at, inward, {0.0, 0.0, 1.0}))
            end

          [rail.(z, z + 0.15), rail.(z + h - 0.12, z + h) | rings]
        else
          [Shape.prism(quad.(0.12), h, look, frame: Frame.move({0.0, 0.0, z}))]
        end
      end)

    Part.new("lan_can", :statue, Enum.map(shapes, &Mesh.matter(&1, matter)), [@o],
      sources: ["The balustrade of the terrace: #{h} m high, pierced (by eye from the photos)."]
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
    sizes = World.Sizes.list(o, @sizes, o.sources)

    rest =
      for name <- ~w(rays material reliefs windows),
          do: %{"name" => name, "value" => choice(o, name), "source" => o.sources[name] || World.Sizes.none()}

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
    {zp, h, _} = levels(o)
    {hw, hd} = {o.base_width / 2 - 0.5, o.base_depth / 2 - 0.5}

    lights =
      for x <- [-hw, hw], y <- [-hd, hd], do: port("light", {x, y, h}, {-x, -y, 3 * hw} |> Vec.norm(), [0.3, 0.3, 0.3])

    door = port("door", {0.0, -o.base_depth / 2, zp}, {0.0, -1.0, 0.0}, [1.2, 0.2, 2.4])

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

  # The collision boxes: the plaza, the block, the dome, the robe, the
  # arms and the head (the halo and the rays have none: a player does not
  # reach them).
  defp collision(%{marks: m, scale: s, top: top}, o, lift) do
    box = fn name, {x0, y0, z0}, {x1, y1, z1} ->
      %{"name" => name, "at" => {(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2}, "size" => {x1 - x0, y1 - y0, z1 - z0}}
    end

    {hw, hd, r, ap} = {o.base_width / 2, o.base_depth / 2, o.plaza_radius, o.dome_width / 2}
    {zp, zb, _} = levels(o)
    sh = elem(m["upperarm_l"], 2) + lift
    tip = abs(elem(m["hand_l"], 0)) + (o.hand || 0.18 * s)
    neck = elem(m["head"], 2) + lift
    za = (elem(m["hand_l"], 2) + elem(m["upperarm_l"], 2)) / 2 + lift

    [
      box.("san", {-r, -r, 0.0}, {r, r, zp}),
      box.("be", {-hw, -hd, zp}, {hw, hd, zb}),
      box.("vom", {-ap, -ap, zb}, {ap, ap, lift}),
      box.("ao", {-0.168 * s, -0.075 * s, lift}, {0.168 * s, 0.095 * s, sh}),
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
