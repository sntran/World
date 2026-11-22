defmodule World.People.Human do
  @moduledoc """
  People from the data of MakeHuman (CC0, `World.People.Data`): a body of
  real shape from its numbers (sex, age, muscle, weight, height, origin),
  a skeleton of 53 bones ("game_engine"), skin weights, eyes, eyebrows,
  eyelashes, hair and clothes fitted to the body, and the textures of a
  skin.

  The levels of detail (`World.Detail`):
  - `:near`: the full base mesh, and the clothes and the hair;
  - `:mid`: a body of about 1,600 faces, with the colors and the form of
    the clothes on it (a loose part of an item is a mesh of its own), and
    the hair;
  - `:far`: a body of 730 faces, with the colors and the form of the
    clothes on it.
  """
  alias World.{Detail, Figure, Frame, Part, Port, Scene, Vec}
  alias World.People.{Data, Face, Joints, Parts, Pose, Skeleton, Skin}
  require Data

  @blink ~w(eyeBlinkLeft eyeBlinkRight)

  @defaults [
    gender: 1.0,
    age: 30,
    muscle: 0.5,
    weight: 0.5,
    height: 0.5,
    bust: 0.5,
    firmness: 0.5,
    waist: 0.5,
    hips: 0.5,
    buttocks: 0.5,
    stomach: 0.5,
    torso: 0.5,
    shoulders: 0.5,
    arms: 0.5,
    legs: 0.5,
    neck: 0.5,
    shape: %{},
    race: %{"asian" => 1.0},
    skin: Data.name!("skins", "young_asian_male"),
    eyes: Data.name!("eye_materials", "darkbrown"),
    eyebrows: Data.name!("eyebrows", "eyebrow001"),
    hair: Data.name!("hair", "short02"),
    clothes: Data.names!("clothes", ["male_casualsuit01", "shoes01"]),
    hair_color: nil,
    clothes_colors: [],
    clothes_options: [],
    head: 1.0,
    helmet: nil,
    pose: %{},
    hold: [],
    wear: [],
    speech: false,
    expressions: false,
    face: "relaxed",
    blink: true,
    talk: nil
  ]

  @doc """
  A person. The options (with their defaults in `@defaults`): `gender`
  (0 is a woman, 1 a man), `age` (years, 1 to 90: a baby, a child, an adult), `muscle`, `weight`
  and `height` (0 to 1, 0.5 is the mean), the options of the shape
  (`shapes/0`: `bust` and `firmness` of a woman, `waist`, `hips`,
  `buttocks`, `stomach`, `torso`, `shoulders`, `arms`, `legs`, `neck`; 0
  to 1, 0.5 is the shape of MakeHuman), `shape` (a map of a slider of
  MakeHuman, `World.People.Data.sliders/0`, to a value from -1 to 1; it
  wins over a short name of the same slider), `race` (a map of
  "african", "asian", "caucasian" to a weight), `skin`, `eyes`,
  `eyebrows`, `hair` (or nil), `clothes` (a list), `hair_color` (`[r, g,
  b]`, or nil for the color of the hair), `clothes_colors` (a list of
  `[r, g, b]` in the order of the clothes: at mid and far the color of
  the item, at near a tint of its texture), `clothes_options` (a list of
  maps in the order of the clothes: `hem` and `hood` of
  `World.Sewing.garment/2` for a garment of World, `print` (`"plain"`,
  `"checks"` or `"stripes"`), `print_color` (`[r, g, b]`, the color of
  the lines of the print; the color of the item is its ground) and
  `print_size` (m): a print of `World.Sewing.print/2` at the points of
  the item at near, and of the body under it at mid and far), `head` (the size of the head:
  1 is the size of the body, more is the bigger head of a game), `helmet`
  (`[r, g, b]`: a helmet of a rider of that color, or nil), `pose` (a map
  of a bone to `{axis, degrees}`, or a name of `World.People.Pose`), and
  `animations` (a list of names of `World.People.Pose`, or of `{name,
  opts}`: `delay` in seconds and `mirror` for a routine), and `hold` (a
  list of `{port, item}`: a prop on a port of a bone, as
  `World.Figure.hold/4`, by the port of the prop with the name of the
  port of the person with no side (`grip` for `grip_r`); a hand that
  holds a prop closes on it, in the pose and in each animation), `wear`
  (a list of the parts from edits of `World.People.Parts`, each a name
  or `{name, opts}`: hair as a mass, a nón lá, a helmet, with the size
  of the head of the person; give `hair: nil` with a mass of hair), and
  `speech` (true: the 15 visemes of `World.People.Face` as morph targets
  of the skin, and at near of the teeth and the tongue, for an app that
  moves the mouth with the voice), and `expressions` (true: the face
  shapes of ARKit of `World.People.Face` as morph targets of the skin,
  and at near of the teeth, the tongue, the eyebrows and the eyelashes:
  a blink closes the eyelashes). At mid and far the body moves by its
  fit to the base mesh. `face`: the face at rest (`World.People.Face.rest/1`:
  `"relaxed"`, `"neutral"` or a map of the face shapes to their weights;
  each target of a shape of it moves only the rest of the way, so 1 is
  the full shape). `blink` (true: the shapes `eyeBlinkLeft` and
  `eyeBlinkRight` as morph targets, and the animation `blink`). `talk`
  (with `speech`: a list of cues of visemes, as `World.People.Face.talk/2`):
  the animation `talk`, the weights of the visemes for those cues.
  """
  def person(name, opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    o = Map.put(o, :colors, chosen_colors(o))
    o = o |> Map.update!(:skin, &child_skin(&1, o.age)) |> Map.update!(:head, &(&1 * child_head(o.age, o.gender)))
    base = Data.base()
    o = Map.put(o, :rest, Face.rest(o.face))
    clothes = items(o)
    points = base.points |> morph(o) |> worn(clothes) |> rest_face(o)
    o = Map.put(o, :ground, ground(base, points, clothes))
    bones = skeleton(points, o.ground)
    weights = Detail.collect(vertex_weights(Enum.map(bones, & &1.name)))
    level = Detail.level()

    {prims, materials} =
      case level do
        :near -> near(base, points, weights, o, clothes)
        _ -> proxy(cloth(points), weights, o, clothes, level)
      end

    {prims, materials} = helmet({prims, materials}, points, weights, bones, o)
    {prims, materials} = if level == :near, do: soft_hair({prims, materials}), else: {prims, materials}

    skeleton = Skeleton.new(bones)
    hands = for {"grip_" <> side, _} <- o.hold, into: %{}, do: {String.to_existing_atom(side), "grip"}
    pose = Pose.expand(Map.merge(Pose.resolve(o.pose), Map.new(hands, fn {side, shape} -> {{:hand, side}, shape} end)))
    {nodes, skin} = nodes(name, skeleton, prims, pose, o.head)

    %Figure{
      name: name,
      kind: :person,
      params:
        Map.take(o, [
          :gender,
          :age,
          :muscle,
          :weight,
          :height,
          :bust,
          :firmness,
          :waist,
          :hips,
          :buttocks,
          :stomach,
          :torso,
          :shoulders,
          :arms,
          :legs,
          :neck,
          :shape,
          :race,
          :skin,
          :hair,
          :clothes,
          :hair_color,
          :clothes_colors,
          :head
        ])
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end),
      sources: [
        "MakeHuman (CC0): the base mesh, the targets, the skeleton game_engine, and the assets #{Enum.join([o.skin | o.clothes], ", ")}."
      ],
      nodes: nodes,
      skins: [skin],
      animations:
        for(
          a <- Map.get(o, :animations, []),
          do:
            if(is_tuple(a),
              do: Pose.animation(elem(a, 0), bones, [hands: hands] ++ elem(a, 1)),
              else: Pose.animation(a, bones, hands: hands)
            )
        ) ++ blink(o, prims, length(nodes) - 1) ++ talk(o, prims, length(nodes) - 1),
      materials: materials,
      ports: ports(bones, points, weights, o.ground),
      skeleton: skeleton,
      pose: pose,
      joints: Joints.all()
    }
    |> then(fn f ->
      # (A hat of one size is the size for the head of a child: `child_hat/2`.)
      hat = child_hat(o.age, o.gender)

      Enum.reduce(o.hold, f, fn {port, item}, f ->
        item = if port == "crown", do: sized(item, hat), else: item
        Figure.hold(f, port, item, String.replace(port, ~r/_[lr]$/, ""))
      end)
    end)
    |> then(fn f ->
      # A part from edits on its port, with the size of the head of this person. The part is in the node of
      # the bone of the head, so the scale of the head (`head`) is on it already: a part that fits the head
      # has the size of the head of the mesh, and a part of one size has the size for the head of a child.
      head = head_size(bones, weights, points)
      hat = child_hat(o.age, o.gender)

      Enum.reduce(o.wear, f, fn part, f ->
        {part, more} = if is_tuple(part), do: part, else: {part, []}
        scale = if Parts.fits?(part), do: Parts.scale(part, head), else: hat
        item = Parts.part(part, [scale: scale] ++ more)
        Figure.hold(f, Parts.on(part), item, Parts.on(part))
      end)
    end)
  end

  # The items of the clothes with the options of the order (`World.Sewing.asset/2`), each with its print
  # (`print`, or nil).
  defp items(o) do
    for {name, i} <- Enum.with_index(o.clothes) do
      opts = Map.new(Enum.at(o.clothes_options, i, %{}))
      a = World.Sewing.asset(name, opts)

      print =
        if Map.get(opts, :print, "plain") != "plain" do
          ground = Map.get(o.colors, name, a.color)

          %{
            kind: opts.print,
            size: Map.get(opts, :print_size, 0.03),
            colors: {ground, Map.get(opts, :print_color, [255, 255, 255])}
          }
        end

      Map.put(a, :print, print)
    end
  end

  # The width and the length of the head: the box of the points of the skin that follow the bone of the head.
  defp head_size(bones, weights, points) do
    head = Enum.find_index(bones, &(&1.name == "head"))

    {{x0, y0, _}, {x1, y1, _}} =
      Vec.bounds(
        for {v, ws} <- weights, Enum.any?(ws, fn {b, w} -> b == head and w >= 0.5 end), do: to_world(elem(points, v))
      )

    {x1 - x0, y1 - y0}
  end

  @doc """
  The skeleton (`World.People.Skeleton`) of a person with the options of
  `person/2`, with no mesh: to try a pose and measure it.
  """
  def skeleton(opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    base = Data.base()
    o = Map.put(o, :rest, Face.rest(o.face))
    clothes = items(o)
    points = base.points |> morph(o) |> worn(clothes) |> rest_face(o)
    Skeleton.new(skeleton(points, ground(base, points, clothes)))
  end

  @doc """
  The footprint of a bare foot of a person (the options of `person/2`;
  the clothes do not count), at rest, in the axes of World (m, the ground
  at z = 0): `%{length: m, rows: [{y, x0, x1, top}]}`, a row for each
  5 mm from the heel to the toes: the sides of the foot in plan (its
  points under 40 mm, 7.5 mm or less from the row: the base mesh is
  sparse) and the height of its top (its points under 120 mm). `side` is `"l"` (the left foot, x < 0) or `"r"`.
  """
  def footprint(opts \\ [], side \\ "l") when side in ["l", "r"] do
    o = Map.new(Keyword.merge(@defaults, Keyword.put(opts, :clothes, [])))
    base = Data.base()
    points = morph(base.points, o)
    g = ground(base, points, [])
    sign = if side == "l", do: -1, else: 1

    foot =
      for f <- Map.fetch!(base.groups, "body"),
          {v, _} <- f,
          {x, y, z} = to_world(elem(points, v)),
          z - g < 0.12 and x * sign > 0.02,
          uniq: true,
          do: {x, y, z - g}

    {y0, y1} = foot |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    step = 0.005

    rows =
      for i <- 0..floor((y1 - y0) / step),
          y = y0 + i * step,
          near = Enum.filter(foot, fn {_, py, _} -> abs(py - y) <= step * 1.5 end),
          low = Enum.filter(near, fn {_, _, pz} -> pz < 0.04 end),
          low != [] do
        {x0, x1} = low |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
        {y, x0, x1, near |> Enum.map(&elem(&1, 2)) |> Enum.max()}
      end

    %{length: y1 - y0, rows: rows}
  end

  @doc """
  The clothes of a person (the options of `person/2`) on its body: for
  each item, in the order of `clothes`, its name, its layer, and a list
  of `{point of the body, position, out}`, one for each point of the item
  (the axes of MakeHuman, after the drape; `out` is the distance of the
  point from its point of the body). The checks of the layers
  (`World.Sewing`) use it.
  """
  def dressed(opts) do
    o = Map.new(Keyword.merge(@defaults, opts))
    o = Map.put(o, :rest, Face.rest(o.face))
    clothes = items(o)
    points = Data.base().points |> morph(o) |> worn(clothes) |> rest_face(o) |> cloth()

    for c <- clothes do
      q = positions(c, points)

      items =
        for {{[v | _], _, _}, i} <- Enum.with_index(Tuple.to_list(c.fit.refs)),
            do: {v, elem(q, i), Vec.len(Vec.sub(elem(q, i), elem(points, v)))}

      {c.name, c.layer, items}
    end
  end

  # --- The shape of the body ----------------------------------------------------

  # The short names of some sliders of MakeHuman (`Data.sliders/0`), with
  # what each one changes: 0 to 1, 0.5 is the shape of MakeHuman (the
  # slider at 0). The bust and the firmness of a woman are in
  # `target_weights/1`: MakeHuman has a target for each age, muscle and
  # weight.
  @shape [
    waist: {"The size of the waist", ~w(measure-waist-circ-decr-incr)},
    hips: {"The size of the hips", ~w(measure-hips-circ-decr-incr)},
    buttocks: {"The size of the buttocks", ~w(buttocks-volume-decr-incr)},
    stomach: {"The size of the belly", ~w(stomach-pregnant-decr-incr)},
    torso: {"The V shape of the torso: wide at the shoulders, narrow at the waist", ~w(torso-vshape-decr-incr)},
    shoulders: {"The width of the shoulders", ~w(measure-shoulder-dist-decr-incr)},
    arms: {"The size of the arms", ~w(measure-upperarm-circ-decr-incr lowerarm-fat-decr-incr)},
    legs:
      {"The size of the legs (the thighs and the calves)", ~w(measure-thigh-circ-decr-incr measure-calf-circ-decr-incr)},
    neck: {"The size of the neck", ~w(measure-neck-circ-decr-incr)}
  ]

  # A short name of a slider that MakeHuman does not have stops the compile.
  for {name, {_, sliders}} <- @shape, s <- sliders, not Map.has_key?(Data.sliders(), s) do
    raise CompileError, description: "the short name #{name}: no slider #{s} in sliders.json"
  end

  @doc """
  The options of the shape of a body with short names, and what each one
  changes: 0 to 1, 0.5 is the shape of MakeHuman. The option `shape` has
  all the sliders of MakeHuman.

      iex> World.People.Human.shapes() |> Enum.take(3)
      [bust: "The cup of the breasts of a woman", firmness: "The firmness of the breasts of a woman", waist: "The size of the waist"]
  """
  def shapes do
    [bust: "The cup of the breasts of a woman", firmness: "The firmness of the breasts of a woman"] ++
      for {name, {doc, _}} <- @shape, do: {name, doc}
  end

  @doc """
  The targets of each short name of the shape (not the bust and the
  firmness): under 0.5 the targets `decr` at the weight `1 - 2 * v`, over
  0.5 the targets `incr` at the weight `2 * v - 1`. `kit.json` has them,
  so a viewer of the kit needs no copy of the table.

      iex> World.People.Human.shape_targets()["arms"]
      %{"decr" => ["arms/measure-upperarm-circ-decr", "arms/l-lowerarm-fat-decr", "arms/r-lowerarm-fat-decr"], "incr" => ["arms/measure-upperarm-circ-incr", "arms/l-lowerarm-fat-incr", "arms/r-lowerarm-fat-incr"]}
  """
  def shape_targets do
    sliders = Data.sliders()

    Map.new(@shape, fn {name, {_, names}} ->
      {Atom.to_string(name),
       %{"decr" => Enum.flat_map(names, &sliders[&1].decr), "incr" => Enum.flat_map(names, &sliders[&1].incr)}}
    end)
  end

  @doc """
  The weight of each target for the numbers of a person: a list of
  `{target name, weight}` (MakeHuman, "macrodetails").
  """
  def target_weights(o) do
    g = [{"female", 1 - o.gender}, {"male", o.gender}]
    age = ages(o.age, o.gender)
    # (A child and a baby have the targets of the mean muscle only.)
    adult = three(o.muscle, "minmuscle", "averagemuscle", "maxmuscle")
    muscle = fn an -> if an in ["young", "old"], do: adult, else: [{"averagemuscle", 1.0}] end
    weight = three(o.weight, "minweight", "averageweight", "maxweight")
    h = o.height
    height = if h < 0.5, do: [{"minheight", 1 - 2 * h}], else: [{"maxheight", 2 * h - 1}]
    total = o.race |> Map.values() |> Enum.sum()
    race = for {r, w} <- o.race, do: {r, w / total}

    racegenderage = for {r, wr} <- race, {gn, wg} <- g, {an, wa} <- age, do: {"#{r}-#{gn}-#{an}", wr * wg * wa}

    universal =
      for {gn, wg} <- g, {an, wa} <- age, {mn, wm} <- muscle.(an), {wn, ww} <- weight do
        {"universal-#{gn}-#{an}-#{mn}-#{wn}", wg * wa * wm * ww}
      end

    heights =
      for {gn, wg} <- g, {an, wa} <- age, {mn, wm} <- muscle.(an), {wn, ww} <- weight, {hn, wh} <- height do
        {"height/#{gn}-#{an}-#{mn}-#{wn}-#{hn}", wg * wa * wm * ww * wh}
      end

    # The shape: the breasts of a woman by her age, muscle and weight (the
    # mean cup and firmness has no target), then the sliders.
    cup = three(Map.get(o, :bust, 0.5), "mincup", "averagecup", "maxcup")
    firm = three(Map.get(o, :firmness, 0.5), "minfirmness", "averagefirmness", "maxfirmness")

    breasts =
      for {an, wa} <- age,
          an in ["young", "old"],
          {mn, wm} <- adult,
          {wn, ww} <- weight,
          {cn, wc} <- cup,
          {fname, wf} <- firm,
          {cn, fname} != {"averagecup", "averagefirmness"} do
        {"breast/female-#{an}-#{mn}-#{wn}-#{cn}-#{fname}", (1 - o.gender) * wa * wm * ww * wc * wf}
      end

    Enum.filter(racegenderage ++ universal ++ heights ++ breasts ++ slider_weights(o), fn {_, w} -> w > 1.0e-4 end)
  end

  # The face and the body of a child, over the shapes of a child of MakeHuman (which keep the face of an
  # adult): the younger head of MakeHuman, a round face, large eyes, a short small nose that points up,
  # full cheeks with no bones that show, a short small chin, a small mouth, a thin neck and a chest with no
  # muscle. Each at its full value for a child of 5 years or less (`youth/1`); the option `shape` of a
  # person comes after them.
  @child_face %{
    "head-age-decr-incr" => -1.0,
    "head-round" => 0.6,
    "eye-scale-decr-incr" => 0.5,
    "nose-scale-vert-decr-incr" => -0.5,
    "nose-scale-horiz-decr-incr" => -0.2,
    "nose-volume-decr-incr" => -0.4,
    "nose-point-down-up" => 0.4,
    "cheek-volume-decr-incr" => 0.6,
    "cheek-bones-decr-incr" => -0.5,
    "chin-height-decr-incr" => -0.5,
    "chin-prominent-decr-incr" => -0.4,
    "chin-width-decr-incr" => -0.2,
    "mouth-scale-horiz-decr-incr" => -0.25,
    "neck-scale-horiz-decr-incr" => -0.3,
    "torso-muscle-pectoral-decr-incr" => -0.8
  }

  @doc """
  How much a person of an age (years) has the face and the body of a
  child: 1 at 5 years or less, 0 at 15 years or more.
  """
  def youth(years), do: min(max((15 - years) / 10, 0.0), 1.0)

  # An item (a part or an assembly of parts) larger or smaller by `k` from its origin.
  defp sized(item, k) when k == 1.0, do: item

  defp sized(%World.Part{} = p, k),
    do: %{p | shapes: Enum.map(p.shapes, fn m -> %{m | points: Enum.map(m.points, &Vec.scale(&1, k))} end)}

  defp sized(%World.Assembly{nodes: nodes} = a, k),
    do: %{a | nodes: for({name, item, c} <- nodes, do: {name, sized(item, k), c})}

  # The skin of a child: the skins of MakeHuman are of adults, and the skin of a man has the shadow of a
  # beard and strong brows. A child of less than 13 years with the skin of a man has the skin of a woman of
  # the same age and origin.
  defp child_skin(skin, age) when age < 13 do
    woman = String.replace_suffix(skin, "_male", "_female")
    if Data.known?("skins", woman), do: woman, else: skin
  end

  defp child_skin(skin, _age), do: skin

  # The median height (cm) at each year of age from 1 to 20, of boys and of girls: the growth charts of the
  # CDC (2000; the length for the age from birth to 36 months, the stature for the age from 2 to 20 years,
  # the median M of `lenageinf.csv` and `statage.csv`; public domain).
  @growth %{
    boys:
      [75.5, 86.5, 95.0, 102.2, 108.9, 115.4, 121.8, 127.9, 133.5, 138.6] ++
        [143.5, 149.1, 156.1, 163.8, 169.9, 173.5, 175.3, 176.2, 176.6, 176.8],
    girls:
      [73.8, 85.0, 93.9, 100.8, 107.7, 114.7, 121.5, 127.6, 132.9, 138.0] ++
        [144.0, 151.2, 157.2, 160.4, 161.9, 162.5, 162.9, 163.1, 163.3, 163.3]
  }
  # The height of the shape of a baby and of a child of MakeHuman, as a part of the height of the young
  # adult (measured on the mesh: 0.60 m and 1.32 m for a man of 1.63 m).
  @baby 0.37
  @child 0.81

  @doc """
  The height of a person of an age (years, 1 to 20 or more) as a part of
  the height of an adult of the same gender (0 a woman, 1 a man): from
  the median heights of the growth charts of the CDC.
  """
  def growth(years, gender) do
    part = fn list ->
      y = min(max(years, 1), 20) * 1.0
      i = min(trunc(y), 19)
      {a, b} = {Enum.at(list, i - 1), Enum.at(list, i)}
      (a + (b - a) * (y - i)) / List.last(list)
    end

    part.(@growth.girls) * (1 - gender) + part.(@growth.boys) * gender
  end

  # The height of the head from the chin to the top (menton to vertex), as a part of the height of the
  # head of an adult: the means of each group of age of the 1977 study of the University of Michigan for
  # the Consumer Product Safety Commission (R. G. Snyder et al., "Anthropometry of Infants, Children, and
  # Youths to Age 18 for Product Safety Design", UM-HSRI-77-17, "Head height", males and females: 17.3 cm
  # at 2.0 to 3.5 years, 18.4 cm at 5.5 to 6.5, 19.5 cm at 9.5 to 10.5, 21.4 cm at 17.5 to 19), each over
  # 21.4 cm. At 1 year: the 2.75 years of the study times the growth of the circumference of the head of
  # the CDC from 12 to 33 months (46.3 cm to 49.4 cm, boys), an estimate.
  @heads [
    {1.0, 0.757},
    {2.75, 0.808},
    {4.0, 0.836},
    {5.0, 0.836},
    {6.0, 0.86},
    {7.0, 0.874},
    {8.0, 0.879},
    {9.0, 0.888},
    {10.0, 0.911},
    {11.0, 0.93},
    {12.0, 0.935},
    {13.0, 0.949},
    {14.0, 0.963},
    {15.0, 0.972},
    {16.0, 0.995},
    {17.0, 0.991},
    {18.25, 1.0}
  ]
  # The height of the head of the shapes of MakeHuman as a part of the head of the young adult (measured
  # on the mesh, chin to top): the baby and the child.
  @head_shapes %{"baby" => 0.55, "child" => 0.86, "young" => 1.0, "old" => 1.0}
  # The part of the height of the head that is over the joint of the head, as a part of the height of the
  # body of an adult (about 0.6 of a head of 0.149 of the height).
  @over_joint 0.09

  # The ages of MakeHuman for an age in years: a baby, a child, a young adult (25) and an old one (90),
  # each with its weight. Before 20 years the weights come from the height of the age (`growth/2`): a
  # person grows fast and then stops, so a person of 16 years is almost an adult, and the shape of a child
  # of MakeHuman is a child of about 10 years.
  defp ages(years, _gender) when years >= 25, do: between("young", "old", (min(years, 90) - 25) / 65)

  defp ages(years, gender) do
    # (The head of a child is larger than the head of the shape of its height (`child_head/2`): the part of
    # the head over its joint makes the person taller by that much, so the body is a little smaller.)
    part = growth(years, gender) - @over_joint * model_head(years, gender) * (head_factor(years, gender) - 1)

    if part >= @child,
      do: between("child", "young", (part - @child) / (1 - @child)),
      else: between("baby", "child", max(part - @baby, 0.0) / (@child - @baby))
  end

  @doc """
  The scale of the head of a person of an age (years) over the head of
  the shapes of MakeHuman of that height: so that the head is as large
  as the head of a real child of that age (the 1977 study of the
  University of Michigan). 1.0 from 18 years.
  """
  def child_head(years, gender), do: head_factor(years, gender)

  # The size of a hat of one size (a nón lá, a hard hat) on the head of a person of an age: the hat of a
  # child is made for the head of a child, so it sits on the head as the hat of an adult sits on the head of
  # an adult (a hat of an adult comes down over the eyes of a child: its ring sits on the head). The hat is
  # in the node of the bone of the head, which has the scale of `child_head/2`: the size is the head of a
  # real child of that age over the head of an adult, over that scale. 1.0 for an adult.
  defp child_hat(years, _gender) when years >= 18.25, do: 1.0
  defp child_hat(years, gender), do: real_head(years) / head_factor(years, gender)

  defp head_factor(years, _gender) when years >= 18.25, do: 1.0

  defp head_factor(years, gender) do
    max(real_head(years) / model_head(years, gender), 1.0)
  end

  defp real_head(years) do
    y = max(years * 1.0, 1.0)
    {{a, ra}, {b, rb}} = @heads |> Enum.zip(tl(@heads)) |> Enum.find(fn {{_, _}, {b, _}} -> y <= b end)
    ra + (rb - ra) * (y - a) / (b - a)
  end

  # The head of the shape of a height, from the weights of the shapes of MakeHuman for that height.
  defp model_head(years, gender) do
    part = growth(years, gender)

    weights =
      if part >= @child,
        do: between("child", "young", (part - @child) / (1 - @child)),
        else: between("baby", "child", max(part - @baby, 0.0) / (@child - @baby))

    weights |> Enum.map(fn {name, w} -> @head_shapes[name] * w end) |> Enum.sum()
  end

  defp between(a, b, t), do: [{a, 1 - t}, {b, t}]

  # The targets of the sliders: the short names, then the map `shape`
  # (it wins). A slider at -1 has its targets "decr" at the full weight, at
  # 1 its targets "incr".
  defp slider_weights(o) do
    sliders = Data.sliders()
    short = for {name, {_, names}} <- @shape, s <- names, into: %{}, do: {s, 2 * Map.get(o, name, 0.5) - 1}
    young = youth(Map.get(o, :age, 30))
    child = for {name, v} <- @child_face, young > 0, into: %{}, do: {name, v * young}

    for {name, v} <- child |> Map.merge(short) |> Map.merge(Map.get(o, :shape, %{})),
        slider = Map.get(sliders, name) || raise(ArgumentError, "no slider #{inspect(name)}"),
        t <- if(v < 0, do: slider.decr, else: slider.incr) do
      {t, abs(v)}
    end
  end

  defp three(v, low, mid, _high) when v < 0.5, do: [{low, 1 - 2 * v}, {mid, 2 * v}]
  defp three(v, _low, mid, high), do: [{mid, 2 - 2 * v}, {high, 2 * v - 1}]

  # The clothes fit to a body with no nipples: a smooth of the breasts (`smooth/1`), then the points of the
  # nipples go flat along the normal of the chest (`flat_nipples/1`). (The targets of MakeHuman that make
  # the nipples small move their points to the side, over each other, and the cloth over them folds into a
  # small star.) The body at near stays as MakeHuman makes it, under the clothes. The body at mid and far
  # and the kit have these points: there the clothes are the colors of the body.
  defp cloth(points), do: points |> smooth() |> flat_nipples()

  # The smooth of the breasts keeps a bump of 1 mm at each nipple, and a cloth over it shows a small
  # crease. The points of each nipple and of the ring round them go to the height of the mean of their
  # neighbors, 60 steps, along the normal of the chest there only: so the bump goes, and the many small
  # faces of a nipple keep their places side by side (a smooth to the mean of the neighbors pulls them to
  # their middle, where they fold over each other). The normal is the one of the base mesh, so each step is
  # linear (the kit of a client does the same to each of its targets).
  @nipple_steps 60

  defp flat_nipples(points) do
    {area, normal} = nipples()

    # (The points that move are in a map, and they go into the tuple of the points one time: a put_elem
    # copies the whole tuple.)
    moved =
      Enum.reduce(1..@nipple_steps, Map.new(area, fn {v, _, _} -> {v, elem(points, v)} end), fn _, m ->
        at = fn v -> Map.get(m, v) || elem(points, v) end

        Map.new(area, fn {v, side, ns} ->
          p = m[v]
          n = normal[side]
          {v, Vec.add(p, Vec.scale(n, Vec.dot(Vec.sub(ns |> Enum.map(at) |> Vec.mean(), p), n)))}
        end)
      end)

    put_all(points, moved)
  end

  # A tuple of points with the points of a map (an index to a point) in their places, in one copy.
  defp put_all(points, moved) do
    points |> Tuple.to_list() |> Enum.with_index(fn p, i -> Map.get(moved, i, p) end) |> List.to_tuple()
  end

  # The points of the nipples (that the target nipple-point-decr moves) and of the ring round them, each
  # with its side (1 left, -1 right) and its neighbors; and the normal of the chest of the base mesh at
  # each nipple (the sum of the normals of the faces of its area).
  defp nipples do
    Data.cached(:nipples, fn ->
      base = Data.base()
      ring = neighbors(base)

      # (The points of the body are the first 13,380 points of the base mesh.)
      nipple =
        for {v, d} <- Data.target("breast/nipple-point-decr"), v < 13_380, Vec.len(d) > 0.01, do: v

      side = fn v -> if elem(elem(base.points, v), 0) > 0, do: 1, else: -1 end
      area = Enum.uniq(nipple ++ Enum.flat_map(nipple, &Map.fetch!(ring, &1)))
      set = MapSet.new(area)

      normal =
        for(
          f <- Map.fetch!(base.groups, "body"),
          [a, b, c, d] = vs = Enum.map(f, &elem(&1, 0)),
          Enum.all?(vs, &MapSet.member?(set, &1)),
          [pa, pb, pc, pd] = Enum.map([a, b, c, d], &elem(base.points, &1)),
          do: {side.(a), Vec.cross(Vec.sub(pc, pa), Vec.sub(pd, pb))}
        )
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {s, ns} -> {s, ns |> Enum.reduce(&Vec.add/2) |> Vec.norm()} end)

      {for(v <- area, do: {v, side.(v), Map.fetch!(ring, v)}), normal}
    end)
  end

  @doc """
  The points of a body as its clothes fit to it: no nipples, and smooth
  breasts (the sewing shop takes the direction of the cloth from them).
  """
  def cloth_points(points), do: cloth(points)

  # The steps of the smooth of the breasts: each step moves each point of
  # the breasts (`Data.breast_points/0`) half the way to the mean of its
  # neighbors, then back a little more (Taubin), so the breasts stay
  # round and do not shrink, and the rest of the point of a nipple goes
  # (the cups of a bra are smooth). Each step is linear: the smooth of a
  # sum of targets is the sum of the smooth targets, so the kit smooths
  # each of its targets.
  @smooth_steps 60

  defp smooth(points) do
    chest = chest()

    moved =
      Enum.reduce(1..@smooth_steps, Map.new(chest, fn {v, _} -> {v, elem(points, v)} end), fn i, m ->
        t = if rem(i, 2) == 1, do: 0.5, else: -0.53
        at = fn v -> Map.get(m, v) || elem(points, v) end
        Map.new(chest, fn {v, ns} -> {v, Vec.lerp(at.(v), ns |> Enum.map(at) |> Vec.mean(), t)} end)
      end)

    put_all(points, moved)
  end

  # The points of the breasts with their neighbors.
  # (Not the points of the nipples: their many small faces fold in this smooth. `flat_nipples/1` does
  # them after it.)
  defp chest do
    Data.cached(:chest, fn ->
      ring = neighbors(Data.base())
      {area, _} = nipples()
      skip = MapSet.new(area, &elem(&1, 0))
      for v <- Data.breast_points(), not MapSet.member?(skip, v), do: {v, Map.fetch!(ring, v)}
    end)
  end

  # The points of the base mesh with the targets, in the axes of MakeHuman.
  # A child has a flat chest (`flat_chest/2`).
  defp morph(points, o), do: points |> add_targets(target_weights(o)) |> flat_chest(Map.get(o, :age, 30))

  # The shapes of a child of MakeHuman have a small bust (13 mm at 6 years, 21 mm at 12, as much as a man),
  # and a shirt shows it. The chest of a child is flat: the points of the breasts go to a membrane over
  # them (each point at the mean of its neighbors, the points round them fixed), all the way at 11 years
  # or less and none at 16. A membrane is never out of the body (the mean of the points round a point is
  # not in front of them), so no cloth goes into the body. Each step is linear, as `smooth/1`.
  @flat_steps 300

  defp flat_chest(points, years) do
    case min(max((16 - years) / 5, 0.0), 1.0) do
      k when k == 0.0 ->
        points

      k ->
        put_all(points, Map.new(chest_membrane(points), fn {v, p} -> {v, Vec.lerp(elem(points, v), p, k)} end))
    end
  end

  # The points of the breasts on a membrane: Gauss-Seidel steps, each a little past the mean (1.6), so
  # that 300 steps are enough.
  defp chest_membrane(points) do
    area =
      Data.cached(:chest_area, fn ->
        ring = neighbors(Data.base())
        for v <- Data.breast_points(), ns = Map.fetch!(ring, v), do: {v, ns, 1 / length(ns)}
      end)

    Enum.reduce(1..@flat_steps, Map.new(area, fn {v, _, _} -> {v, elem(points, v)} end), fn _, m ->
      Enum.reduce(area, m, fn {v, ns, w}, m ->
        mean = Enum.reduce(ns, {0.0, 0.0, 0.0}, fn n, s -> Vec.add(s, Map.get(m, n) || elem(points, n)) end)
        Map.put(m, v, Vec.lerp(m[v], Vec.scale(mean, w), 1.6))
      end)
    end)
  end

  # The body takes the shape that its clothes give it (the cups of a bra:
  # `World.Sewing`).
  defp worn(points, clothes), do: add_targets(points, Enum.flat_map(clothes, & &1.shape))

  defp add_targets(points, weights) do
    # (One read of the pack for all the targets that the cache does not have.)
    Data.load_targets(Enum.map(weights, &elem(&1, 0)))
    arr = :array.from_list(Tuple.to_list(points))

    weights
    |> Enum.reduce(arr, fn {name, w}, arr ->
      Enum.reduce(Data.target(name), arr, fn {i, {dx, dy, dz}}, arr ->
        {x, y, z} = :array.get(i, arr)
        :array.set(i, {x + w * dx, y + w * dy, z + w * dz}, arr)
      end)
    end)
    |> :array.to_list()
    |> List.to_tuple()
  end

  @doc "A point of MakeHuman (decimeters, +Y up, front +Z) in the axes of World (meters)."
  def to_world({x, y, z}), do: {-x * 0.1, z * 0.1, y * 0.1}

  # --- The skeleton ------------------------------------------------------------

  # The bones, parents first: name, parent, head and tail (in the axes of
  # World, with the feet on z = 0 later), and the frame of the bone.
  defp skeleton(points, ground) do
    base = Data.base()
    rig = Data.rig()

    center = fn cube ->
      faces = Map.fetch!(base.groups, cube)
      idx = faces |> List.flatten() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      idx |> Enum.map(&elem(points, &1)) |> Vec.mean() |> to_world() |> Vec.sub({0.0, 0.0, ground})
    end

    at = fn spec ->
      case spec do
        %{"strategy" => "CUBE", "cube_name" => cube} ->
          center.(cube)

        %{"strategy" => "MEAN", "vertex_indices" => idx} ->
          idx |> Enum.map(&elem(points, &1)) |> Vec.mean() |> to_world() |> Vec.sub({0.0, 0.0, ground})
      end
    end

    rig
    |> order_bones()
    |> Enum.map(fn name ->
      spec = Map.fetch!(rig, name)
      head = at.(spec["head"])
      tail = at.(spec["tail"])

      %{
        name: name,
        parent: if(spec["parent"] == "", do: nil, else: spec["parent"]),
        head: head,
        tail: tail,
        frame: bone_frame(head, tail, spec["roll"])
      }
    end)
  end

  defp order_bones(rig) do
    Stream.iterate({[], MapSet.new()}, fn {done, seen} ->
      ready =
        for {name, spec} <- rig,
            not MapSet.member?(seen, name),
            spec["parent"] == "" or MapSet.member?(seen, spec["parent"]),
            do: name

      ready = Enum.sort(ready)
      {done ++ ready, MapSet.union(seen, MapSet.new(ready))}
    end)
    |> Enum.find(fn {done, _} -> length(done) == map_size(rig) end)
    |> elem(0)
  end

  # The frame of a bone as in Blender (MPFB makes the skeleton there): its
  # y axis from the head to the tail, turned by the roll. Blender has the
  # axes of World turned 180 degrees around z.
  defp bone_frame(head, tail, roll) do
    flip = fn {x, y, z} -> {-x, -y, z} end
    nor = Vec.norm(flip.(Vec.sub(tail, head)))
    y = {0.0, 1.0, 0.0}
    axis = Vec.cross(y, nor)

    b =
      if Vec.len(axis) > 1.0e-9,
        do: Frame.turn(axis, :math.acos(max(min(Vec.dot(y, nor), 1.0), -1.0)) * 180 / :math.pi()),
        else: if(Vec.dot(y, nor) > 0, do: Frame.identity(), else: Frame.turn({0.0, 0.0, 1.0}, 180.0))

    m = Frame.compose(Frame.turn(nor, roll * 180 / :math.pi()), b)
    %Frame{x: flip.(m.x), y: flip.(m.y), z: flip.(m.z), at: head}
  end

  # The height of the ground (meters): under the lowest point that shows
  # at near, of the body or of the clothes (the soles of the shoes). A
  # point of the body that an item hides does not count: the heel of a
  # foot can be under the sole of a shoe, and the person then stands on
  # the shoe.
  defp ground(base, points, clothes) do
    hidden = clothes |> Enum.map(& &1.fit.delete) |> Enum.reduce(MapSet.new(), &MapSet.union/2)
    body = for f <- Map.fetch!(base.groups, "body"), {v, _} <- f, not MapSet.member?(hidden, v), do: elem(points, v)
    worn = Enum.flat_map(clothes, &Tuple.to_list(fit_positions(&1, points)))
    (body ++ worn) |> Enum.map(&elem(&1, 1)) |> Enum.min() |> Kernel.*(0.1)
  end

  # --- Weights -----------------------------------------------------------------

  # The 4 largest weights of each point of the base mesh: a map of a point
  # to `[{bone index, weight}]`, the sum 1.
  defp vertex_weights(bone_names) do
    index = bone_names |> Enum.with_index() |> Map.new()

    Data.weights()
    |> Enum.flat_map(fn {bone, list} -> for [v, w] <- list, Map.has_key?(index, bone), do: {v, {index[bone], w}} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {v, ws} -> {v, top4(ws)} end)
  end

  @doc """
  The 4 largest weights of a list of `{bone, weight}`, with the sum 1.
  The weights of a blend can be less than zero: they go. A point with no
  weight follows the root bone.
  """
  def top4(ws) do
    ws = ws |> Enum.filter(&(elem(&1, 1) > 1.0e-4)) |> Enum.sort_by(fn {b, w} -> {-w, b} end) |> Enum.take(4)
    total = ws |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    if ws == [], do: [{0, 1.0}], else: for({b, w} <- ws, do: {b, w / total})
  end

  defp blend(weights, refs) do
    refs
    |> Enum.flat_map(fn {v, k} -> for {b, w} <- Map.get(weights, v, [{0, 1.0}]), do: {b, w * k} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {b, ws} -> {b, Enum.sum(ws)} end)
    |> top4()
  end

  # --- The meshes --------------------------------------------------------------

  # The near level: the base mesh with no hidden faces, and the assets.
  defp near(base, points, weights, o, clothes) do
    hidden = clothes |> Enum.map(& &1.fit.delete) |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    faces =
      for f <- Map.fetch!(base.groups, "body"), not Enum.any?(f, fn {v, _} -> MapSet.member?(hidden, v) end), do: f

    # With one of speech and expressions, the teeth (with the gums) and
    # the tongue, fit to the helper meshes of the mouth of the base mesh,
    # which the targets of the mouth move.
    shapes = shapes(o)

    # The creases of the skin are darker and warmer (World.People.Skin).
    body =
      mesh(:skin, faces, &elem(points, &1), &elem(base.uvs, &1), &Map.get(weights, &1, [{0, 1.0}]), o.ground, shapes)
      |> Skin.creases()

    mouth =
      if o.speech or o.expressions,
        do: [{:teeth, Data.asset!("teeth", "teeth_base")}, {:tongue, Data.asset!("tongue", "tongue01")}],
        else: []

    assets =
      [
        {:eyes, Data.asset!("eyes", "high-poly"), Data.asset("eye_materials", o.eyes)},
        {:eyebrows, Data.asset("eyebrows", o.eyebrows), nil},
        {:eyelashes, Data.asset!("eyelashes", "eyelashes01"), nil}
      ] ++
        if(o.hair, do: [{:hair, Data.asset("hair", o.hair), nil}], else: []) ++
        for(c <- clothes, do: {String.to_atom("clothes_" <> c.name), c, nil})

    # The body that the clothes fit to, one time for all of them (`cloth/1`).
    dressed = if clothes == [], do: points, else: cloth(points)

    # A collection after each mesh (World.Detail.collect/1).
    prims =
      [Detail.collect(body)] ++
        for(
          {role, a} <- mouth,
          do:
            Detail.collect(
              shade(fitted(role, a, points, weights, o.ground, mouth_shapes(role, a, mouth, points, shapes)))
            )
        ) ++
        for(
          {role, a, _} <- assets,
          do:
            Detail.collect(
              fitted(role, a, on(role, points, dressed), weights, o.ground, face(role, shapes), printed(a))
            )
        )

    materials =
      Map.new(
        [{:skin, Map.merge(textured(Data.asset("skins", o.skin).texture, false), Skin.material(:near))}] ++
          for({role, a} <- mouth, do: {role, Map.merge(textured(a.texture, false), mouth_color(role))}) ++
          for(
            {role, a, mat} <- assets,
            do: {role, a |> textured_item(mat, role) |> tint(a, o) |> unprinted(a)}
          )
      )

    {prims, materials}
  end

  # The levels mid and far: a low-poly body. Each face under clothes has
  # the color of those clothes: an item with a texture of many colors
  # (blue overalls over a white shirt) gives each point the color of its
  # swatch at the place of the item over the point (`point_colors/4`), and
  # an item of one color gives that color. The hair stays at mid.
  defp proxy(points, weights, o, clothes, level) do
    name = if level == :far, do: "proxy741", else: if(o.gender >= 0.5, do: "male1591", else: "female1605")
    p = proxy_asset(name)
    {pts, wts} = fit_points(p, points, weights)
    faces = p.mesh.groups |> Map.values() |> Enum.concat()

    # The form of the clothes: the moves of the body under the close parts of each item (`moves/4`), and
    # the loose parts (`loose/6`), with half as many triangles for each square meter as the body (smooth
    # cloth). The points of each item one time, and a collection after each item (World.Detail.collect/1).
    at = pts |> Tuple.to_list() |> Enum.map(&to_world/1) |> List.to_tuple()
    tris = for [a, b | rest] <- faces, t <- fan(a, [b | rest]), do: {Enum.map(t, &elem(&1, 0)), 0}
    density = 0.5 * length(tris) / area_of(at, tris)

    {moves, loose} =
      Enum.reduce(clothes, {%{}, []}, fn c, {moves, loose} ->
        q = positions(c, points)
        part = loose(c, q, points, weights, o, density)
        Detail.collect({moves(moves, c, q, points), if(part, do: loose ++ [part], else: loose)})
      end)

    pts = pts |> worn_form(p, moves) |> soles(ground(Data.base(), points, []), o.ground)
    ring = neighbors(Data.base())
    covers = Enum.map(clothes, &{&1, grow(cover(&1), ring)})
    # At far the scalp has the color of the hair: the points under the
    # hair, and the points under a short cut (the mesh of long hair is not
    # near each point of the scalp).
    covers =
      if level == :far and o.hair do
        cap = cover(Data.asset("hair", Data.name!("hair", "short03")))
        [{Data.asset("hair", o.hair), MapSet.union(cover(Data.asset("hair", o.hair)), cap)} | covers]
      else
        covers
      end

    # Of the clothes that cover the most of the points of the body under
    # a face, the one on the outer layer (a top over a bra); then the one
    # that covers the most.
    owner = fn face ->
      body = Enum.flat_map(face, fn {v, _} -> elem(elem(p.fit.refs, v), 0) end)

      covers
      |> Enum.map(fn {c, set} -> {c, Enum.count(body, &MapSet.member?(set, &1))} end)
      |> Enum.filter(fn {_, n} -> n * 2 > length(body) end)
      |> Enum.max_by(fn {c, n} -> {Map.get(c, :layer, 1), n} end, &>=/2, fn -> {nil, 0} end)
      |> elem(0)
    end

    uv = fn i -> if i, do: elem(p.mesh.uvs, i), else: {0.0, 0.0} end
    role = fn c -> if c, do: String.to_atom("color_" <> c.name), else: :skin end

    # The faces of the body under the loose parts go.
    under = loose |> Enum.map(&elem(&1, 1)) |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    inside? = fn f ->
      Enum.all?(f, fn {v, _} -> p.fit.refs |> elem(v) |> elem(0) |> Enum.all?(&MapSet.member?(under, &1)) end)
    end

    loose = Enum.map(loose, &elem(&1, 0))
    groups = faces |> Enum.reject(inside?) |> Enum.group_by(owner)

    # The visemes and the face shapes move the body by its fit (the hair
    # at mid has no targets: the GLB gives it zeros).
    shapes = fit_shapes(p, shapes(o))

    prims =
      for {c, faces} <- groups do
        color = point_colors(c, p, o, ring)
        mesh(role.(c), faces, &elem(pts, &1), if(c, do: nil, else: uv), &elem(wts, &1), o.ground, shapes, color)
      end

    prims = prims ++ loose

    # The eyes of few faces, the eyebrows at mid, and the mouth closed
    # behind.
    eyebrows =
      if level == :mid, do: [fitted(:eyebrows, Data.asset("eyebrows", o.eyebrows), points, weights, o.ground)], else: []

    low = Data.asset!("eyes", "low-poly")

    eyes =
      if level == :far do
        uv = fn i -> elem(low.mesh.uvs, i) end
        few(:eyes, low, 48, uv, &(not cornea?(low, &1)), points, weights, o.ground)
      else
        fitted(:eyes, low, points, weights, o.ground)
      end

    prims =
      prims ++
        [
          eyes,
          holes(p, pts, wts, shapes, o.ground)
        ] ++
        eyebrows

    hair =
      if level == :mid and o.hair, do: [fitted(:hair, Data.asset("hair", o.hair), points, weights, o.ground)], else: []

    # The hair at far: its form in few faces, in the color of the hair.
    prims =
      if level == :far and o.hair do
        a = Data.asset("hair", o.hair)
        prims ++ [few(role.(a), a, 80, nil, fn _ -> true end, points, weights, o.ground)]
      else
        prims
      end

    colors =
      for {c, _} <- covers do
        # (The points of an item with a swatch have their colors: the material is white.)
        color = if swatch(c) || c[:print], do: [255, 255, 255], else: Map.get(o.colors, c.name, c.color)
        spec = %{"color" => color, "roughness" => 0.9, "metalness" => 0.0}
        # (The faces of the hair at far and of a loose part of an item are seen from their two sides.)
        two = (level == :far and c.name == o.hair) or Enum.any?(loose, &(&1.material == role.(c)))
        {role.(c), if(two, do: Map.put(spec, "double_sided", true), else: spec)}
      end

    materials =
      Map.new([
        {:skin, Map.merge(textured(Data.asset("skins", o.skin).texture, false), Skin.material(level))},
        {:eyes, textured(Data.asset("eye_materials", o.eyes).texture, false)},
        {:eyebrows, textured(Data.asset("eyebrows", o.eyebrows).texture, :blend)},
        {:hole, %{"color" => [40, 22, 24], "roughness" => 0.9, "metalness" => 0.0}} | colors
      ])

    materials =
      if hair == [],
        do: materials,
        else:
          Map.put(
            materials,
            :hair,
            tint(textured(Data.asset("hair", o.hair).texture, true), Data.asset("hair", o.hair), o)
          )

    {Enum.sort_by(prims, & &1.material) ++ hair, materials}
  end

  # How far a point of a loose part of an item is out of the body at the least (dm).
  @loose 0.25

  # The low-poly body wears the form of the clothes that are close to it: each point of the body under an
  # item moves out to the item. A point of an item that is less than 2.5 cm out (`@loose`) gives its move
  # (from its point of the body, of the largest weight of its fit) to that point of the body; the
  # outermost item wins (`moves/4`: a map of a point of the body to its move). A point of the low-poly body
  # moves by the moves of its points of the body, by their weights (the points with no move do not count).
  # So a jacket, pants and shoes have their volume at mid and far, and a loose part of an item (`loose/6`)
  # starts at the surface of the body.
  defp moves(moves, c, q, points) do
    under = Data.body_points()

    for {{vs, ws, _}, i} <- c.fit.refs |> Tuple.to_list() |> Enum.with_index(),
        {b, _} = vs |> Enum.zip(ws) |> Enum.max_by(&elem(&1, 1)),
        b = Map.get(under, b, b),
        d = Vec.sub(elem(q, i), elem(points, b)),
        Vec.len(d) < @loose,
        reduce: moves do
      acc -> Map.update(acc, b, d, &if(Vec.len(d) > Vec.len(&1), do: d, else: &1))
    end
  end

  defp worn_form(pts, p, moves) do
    for {pt, {vs, ws, _}} <- Enum.zip(Tuple.to_list(pts), Tuple.to_list(p.fit.refs)) do
      moved = for {v, w} <- Enum.zip(vs, ws), m = moves[v], m != nil, do: {m, w}
      total = moved |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      if total > 0, do: Enum.reduce(moved, pt, fn {m, w}, acc -> Vec.add(acc, Vec.scale(m, w / total)) end), else: pt
    end
    |> List.to_tuple()
  end

  # The loose part of an item of the clothes at mid and far: its faces with each point 2.5 cm or more out
  # of its place on the body (a tunic, the panels of an áo dài, the legs of wide pants under the knee, a
  # hood, a down jacket). It is its own mesh (`World.Simplify`: the points that stay keep their places), in
  # the color of the item, with `density` triangles for each square meter, so its form shows where a
  # color on the body has none. With the points of the body that its points fit to; nil for an item with
  # no loose part.
  defp loose(c, q, points, weights, o, density) do
    under = Data.body_points()

    out =
      for {{vs, ws, _}, i} <- c.fit.refs |> Tuple.to_list() |> Enum.with_index() do
        at = Enum.zip(vs, ws) |> Enum.map(fn {v, w} -> Vec.scale(elem(points, Map.get(under, v, v)), w) end)
        Vec.len(Vec.sub(elem(q, i), Enum.reduce(at, &Vec.add/2))) >= @loose
      end
      |> List.to_tuple()

    tris =
      for f <- c.mesh.groups |> Map.values() |> Enum.concat(),
          Enum.all?(f, &elem(out, elem(&1, 0))),
          t <- fan(hd(f), tl(f)),
          do: Enum.map(t, &elem(&1, 0))

    if tris != [] do
      used = tris |> List.flatten() |> Enum.uniq()
      index = used |> Enum.with_index() |> Map.new()
      at = used |> Enum.map(&to_world(elem(q, &1))) |> List.to_tuple()
      faces = for t <- tris, do: {Enum.map(t, &index[&1]), 0}
      budget = max(8, round(area_of(at, faces) * density))
      # (The points of an open edge, a hem or a cuff, keep their places: a pin of 10 planes.)
      edges =
        Enum.frequencies(for {[a, b, c], _} <- faces, {x, y} <- [{a, b}, {b, c}, {c, a}], do: {min(x, y), max(x, y)})

      hem = for {{x, y}, 1} <- edges, v <- [x, y], into: MapSet.new(), do: v
      pins = for i <- 0..(length(used) - 1), do: if(MapSet.member?(hem, i), do: 10.0, else: 0.0)
      %{faces: faces, ids: ids} = World.Simplify.collapse(Tuple.to_list(at), faces, budget, pins: pins)
      back = used |> List.to_tuple()
      ids = List.to_tuple(ids)
      faces = for {vs, _} <- faces, do: Enum.map(vs, &{elem(back, elem(ids, &1)), nil})

      role = String.to_atom("color_" <> c.name)
      # (The weights of the points that stay only.)
      wts = Map.new(Tuple.to_list(ids), &{elem(back, &1), blend(weights, ref_pairs(c, elem(back, &1)))})
      prim = mesh(role, faces, &elem(q, &1), nil, &Map.fetch!(wts, &1), o.ground, [], item_colors(c, o))
      {prim, for(v <- used, {vs, _, _} = elem(c.fit.refs, v), b <- vs, into: MapSet.new(), do: Map.get(under, b, b))}
    end
  end

  defp ref_pairs(c, v) do
    {vs, ws, _} = elem(c.fit.refs, v)
    Enum.zip(vs, ws)
  end

  # The area of triangles of points.
  defp area_of(at, faces) do
    for {[a, b, c], _} <- faces, reduce: 0.0 do
      sum -> sum + 0.5 * Vec.len(Vec.cross(Vec.sub(elem(at, b), elem(at, a)), Vec.sub(elem(at, c), elem(at, a))))
    end
  end

  # The colors of the points of the loose part of an item: its print, or the swatch of its texture at its
  # UVs (tinted by the color of the order, as `point_colors/4`), or nil (the color of its material).
  defp item_colors(%{print: %{} = print} = c, _o) do
    base = Data.base().points
    fn v -> List.to_tuple(World.Sewing.print(print, at_rest(elem(c.fit.refs, v), base))) end
  end

  defp item_colors(c, o) do
    case swatch(c) do
      nil ->
        nil

      sw ->
        uv =
          for f <- c.mesh.groups |> Map.values() |> Enum.concat(),
              {v, t} <- f,
              t,
              into: %{},
              do: {v, elem(c.mesh.uvs, t)}

        factor = tint_factor(c, o)
        &swatch_color(sw, Map.get(uv, &1), factor, c)
    end
  end

  # The color of a swatch at a UV (the mean color of the item with no UV), by a factor.
  defp swatch_color(sw, uv, factor, c) do
    if(uv, do: sample(sw, uv), else: List.to_tuple(c.color))
    |> Tuple.to_list()
    |> Enum.zip_with(factor, &min(255, round(&1 * &2)))
    |> List.to_tuple()
  end

  # The factor of the color of an order for an item over its mean color.
  defp tint_factor(c, o) do
    case Map.fetch(o.colors, c.name) do
      {:ok, rgb} -> Enum.zip_with(rgb, c.color, &(&1 / max(&2, 1)))
      :error -> [1.0, 1.0, 1.0]
    end
  end

  # The hair and the eyes at far, in few faces. The scalp has the color of
  # the hair, and the hair has its form, so a person is as high as at near
  # and long hair is long. The points of the mesh in one cell of a grid
  # become the one of them farthest from the middle of the mesh, so the
  # outline stays, and the cells are the smallest that give `most`
  # triangles at the most. Then the points stretch to the box of the
  # whole mesh (`boxed/2`): the top of the hair is the top of the person.
  defp few(role, a, most, uv, keep, points, weights, ground) do
    faces = Data.cached({:few, role, a.name}, fn -> few_faces(a, most, keep) end)
    {pts, wts} = fit_points(a, points, weights)
    pts = boxed(pts, faces |> List.flatten() |> Enum.map(&elem(&1, 0)) |> Enum.uniq())
    mesh(role, faces, &elem(pts, &1), uv, &elem(wts, &1), ground, [])
  end

  # The points `used` of a mesh, stretched on each axis from the middle of
  # their box to the box of all the points of the mesh. (A side of the box
  # of the used points at the middle stays.)
  defp boxed(pts, used) do
    {lo, hi} = Vec.bounds(Tuple.to_list(pts))
    {ulo, uhi} = Vec.bounds(Enum.map(used, &elem(pts, &1)))
    mid = Vec.lerp(ulo, uhi, 0.5)

    axis = fn p, k ->
      {c, q} = {elem(mid, k), elem(p, k)}
      {to, from} = if q > c, do: {elem(hi, k), elem(uhi, k)}, else: {elem(lo, k), elem(ulo, k)}
      if abs(from - c) < 1.0e-9, do: q, else: c + (q - c) * (to - c) / (from - c)
    end

    Enum.reduce(used, pts, fn v, acc ->
      p = elem(pts, v)
      put_elem(acc, v, {axis.(p, 0), axis.(p, 1), axis.(p, 2)})
    end)
  end

  defp few_faces(a, most, keep) do
    faces = a.mesh.groups |> Map.values() |> Enum.concat() |> Enum.filter(keep)
    tris = for [a, b | rest] <- faces, t <- fan(a, [b | rest]), do: t
    uvs = for t <- tris, {v, uv} <- t, into: %{}, do: {v, uv}

    [0.05, 0.08, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1.0, 1.2, 1.5, 2.0]
    |> Stream.map(&clustered(a.mesh.points, tris, uvs, &1))
    |> Enum.find(&(length(&1) <= most))
  end

  # The triangles of a mesh with the points of each cell of `size` as one point.
  defp clustered(at, tris, uvs, size) do
    cell = fn {x, y, z} -> {floor(x / size), floor(y / size), floor(z / size)} end
    middle = at |> Tuple.to_list() |> Vec.mean()

    one =
      0..(tuple_size(at) - 1)
      |> Enum.group_by(&cell.(elem(at, &1)))
      |> Enum.flat_map(fn {_, list} ->
        out = list |> Enum.map(&elem(at, &1)) |> Vec.mean() |> Vec.sub(middle) |> Vec.norm()
        best = Enum.max_by(list, &Vec.dot(Vec.sub(elem(at, &1), middle), out))
        for v <- list, do: {v, best}
      end)
      |> Map.new()

    tris
    |> Enum.map(fn t -> Enum.map(t, fn {v, _} -> one[v] end) end)
    |> Enum.filter(&(length(Enum.uniq(&1)) == 3))
    |> Enum.uniq_by(&Enum.sort/1)
    |> Enum.map(fn t -> Enum.map(t, &{&1, uvs[&1]}) end)
  end

  # The soles of the shoes of a low-poly body: the shoes are only a color
  # on its feet, so each point of the sole of a foot (at most 1.5 cm above
  # the lowest point of the body) goes to the ground of the shoes. With
  # bare feet the soles stay. No point goes under the ground (the
  # low-poly foot can be a little lower than the foot of the base mesh).
  # Then the person stands on the ground, as at near.
  defp soles(pts, bare, ground) do
    shoes = abs(bare - ground) >= 0.001

    pts
    |> Tuple.to_list()
    |> Enum.map(fn {x, y, z} ->
      cond do
        shoes and y * 0.1 < bare + 0.015 -> {x, ground * 10, z}
        y * 0.1 < ground -> {x, ground * 10, z}
        true -> {x, y, z}
      end
    end)
    |> List.to_tuple()
  end

  # The hair at near in two passes: with a cut of its alpha at 0.5 (it
  # hides what is behind it), then again with a blend (`hair_edge`), which
  # adds the soft ends of the strands at its edge, so the edge is not a
  # hard line.
  defp soft_hair({prims, %{hair: hair} = materials}) do
    edges = for %{material: :hair} = p <- prims, do: %{p | material: :hair_edge}
    {prims ++ edges, Map.put(materials, :hair_edge, Map.put(hair, "alpha_mode", "BLEND"))}
  end

  defp soft_hair(prims_materials), do: prims_materials

  # The holes of a low-poly body at the mouth (not the holes of the eyes,
  # 1 cm or more to the side): a dark fan from the edge of each hole to a
  # point 2 cm behind its middle, so an open mouth shows no background.
  # The point behind has the mean weights and the mean moves (`shapes`, of
  # the points of the body) of its edge.
  defp holes(p, pts, wts, shapes, ground) do
    faces = p.mesh.groups |> Map.values() |> Enum.concat() |> Enum.map(fn f -> Enum.map(f, &elem(&1, 0)) end)
    edges = for f <- faces, [a, b] <- Enum.chunk_every(f ++ [hd(f)], 2, 1, :discard), do: {a, b}
    set = MapSet.new(edges)
    open = edges |> Enum.reject(fn {a, b} -> MapSet.member?(set, {b, a}) end) |> Enum.sort()
    next = Map.new(open)

    loops =
      open
      |> Enum.reduce({[], MapSet.new()}, fn {a, _}, {loops, seen} ->
        if MapSet.member?(seen, a) do
          {loops, seen}
        else
          loop =
            a
            |> Stream.iterate(&next[&1])
            |> Enum.reduce_while([], &if(&1 in &2, do: {:halt, &2}, else: {:cont, [&1 | &2]}))

          {[Enum.reverse(loop) | loops], MapSet.union(seen, MapSet.new(loop))}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
      |> Enum.filter(fn loop -> abs(Enum.sum(Enum.map(loop, &elem(elem(pts, &1), 0))) / length(loop)) < 0.1 end)

    n = tuple_size(pts)
    mean = fn loop, f -> loop |> Enum.map(f) |> Enum.reduce(&Vec.add/2) |> Vec.scale(1 / length(loop)) end
    backs = for loop <- loops, do: Vec.sub(mean.(loop, &elem(pts, &1)), {0.0, 0.0, 0.2})
    pos = fn v -> if v < n, do: elem(pts, v), else: Enum.at(backs, v - n) end

    weights = fn v ->
      if v < n,
        do: elem(wts, v),
        else:
          Enum.at(loops, v - n)
          |> Enum.flat_map(&elem(wts, &1))
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
          |> Enum.map(fn {b, ws} -> {b, Enum.sum(ws)} end)
          |> top4()
    end

    moves =
      for {name, move} <- shapes do
        {name, fn v -> if v < n, do: move.(v), else: mean.(Enum.at(loops, v - n), move) end}
      end

    fans =
      for {loop, k} <- Enum.with_index(loops),
          [a, b] <- Enum.chunk_every(loop ++ [hd(loop)], 2, 1, :discard),
          do: [{b, nil}, {a, nil}, {n + k, nil}]

    mesh(:hole, fans, pos, nil, weights, ground, moves)
  end

  # --- The helmet ----------------------------------------------------------------

  # A half helmet of a rider (the helmet of Việt Nam): a dome over the top
  # of the head from the line of the brows, a little larger than the head
  # and the hair over that line (at most 4 cm more). It is a part of the
  # skinned mesh on the bone "head", so it follows the head, its pose and
  # its size.
  defp helmet(prims_materials, _points, _weights, _bones, %{helmet: nil}), do: prims_materials

  defp helmet({prims, materials}, points, weights, bones, o) do
    head = Enum.find_index(bones, &(&1.name == "head"))
    at = fn p -> Vec.sub(to_world(p), {0.0, 0.0, o.ground}) end

    skull =
      for {v, ws} <- weights, Enum.any?(ws, fn {b, w} -> b == head and w >= 0.5 end), do: at.(elem(points, v))

    {{x0, y0, z0}, {x1, y1, z1}} = Vec.bounds(skull)
    brow = z0 + 0.62 * (z1 - z0)
    c = {(x0 + x1) / 2, (y0 + y1) / 2 - 0.08 * (y1 - y0), brow}

    hair =
      if o.hair,
        do:
          for(
            p <- Tuple.to_list(fit_positions(Data.asset("hair", o.hair), points)),
            q = at.(p),
            elem(q, 2) > brow,
            do: q
          ),
        else: []

    reach = fn axis, half ->
      out = Enum.map(hair, &abs(elem(Vec.sub(&1, c), axis)))
      min(max(half, Enum.max(out, fn -> 0.0 end)), half + 0.04) + 0.012
    end

    r = {reach.(0, (x1 - x0) / 2), reach.(1, (y1 - y0) / 2 + 0.08 * (y1 - y0)), reach.(2, z1 - brow)}
    prim = dome(c, r, head)
    paint = %{"color" => o.helmet, "roughness" => 0.35, "metalness" => 0.0, "double_sided" => true}
    {prims ++ [prim], Map.put(materials, :helmet, paint)}
  end

  # The upper half of an ellipsoid (center `c`, radii `r`), a little under
  # the middle at its rim, on one bone.
  defp dome({cx, cy, cz}, {rx, ry, rz}, bone) do
    {rings, steps} = {8, 24}

    verts =
      for i <- 0..rings, j <- 0..(steps - 1) do
        lat = :math.pi() / 2 * (1.08 * i / rings)
        lon = 2 * :math.pi() * j / steps
        {u, v, w} = {:math.sin(lat) * :math.cos(lon), :math.sin(lat) * :math.sin(lon), :math.cos(lat)}
        {{cx + rx * u, cy + ry * v, cz + rz * w}, Vec.norm({u / rx, v / ry, w / rz})}
      end

    k = fn i, j -> i * steps + rem(j, steps) end

    indices =
      for i <- 0..(rings - 1),
          j <- 0..(steps - 1),
          tri <- [[k.(i, j), k.(i + 1, j), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i, j + 1)]],
          do: tri

    %Scene.Primitive{
      material: :helmet,
      positions: Enum.map(verts, &elem(&1, 0)),
      normals: Enum.map(verts, &elem(&1, 1)),
      indices: List.flatten(indices),
      joints: List.duplicate({bone, 0, 0, 0}, length(verts)),
      weights: List.duplicate({1.0, 0.0, 0.0, 0.0}, length(verts))
    }
  end

  # The points of the body next to each point (in the faces of the body).
  defp neighbors(base) do
    for f <- Map.fetch!(base.groups, "body"), {a, _} <- f, {b, _} <- f, a != b, reduce: %{} do
      acc -> Map.update(acc, a, [b], &[b | &1])
    end
  end

  # The color of each point of the proxy under an item at mid and far (for `mesh/8`), from the swatch of
  # its texture: the mean of the swatch at the places (UV) of the points of the item over the body points
  # of the point, or over their neighbors when the item has no point over them. An order with a color of
  # the item tints them, as at near (`tint/3`). An item with no swatch (a garment of World, of one
  # fabric: one color) gives nil: it keeps the color of its material.
  defp point_colors(nil, _proxy, _o, _ring), do: nil

  # (An item with a print: the print at the place on the base mesh of each point.)
  defp point_colors(%{print: %{} = print}, proxy, _o, _ring) do
    base = Data.base().points
    fn v -> List.to_tuple(World.Sewing.print(print, at_rest(elem(proxy.fit.refs, v), base))) end
  end

  defp point_colors(c, proxy, o, ring) do
    case swatch(c) do
      nil ->
        nil

      sw ->
        over = items_over(c)
        mean = List.to_tuple(c.color)
        factor = tint_factor(c, o)

        fn v ->
          {body, _, _} = elem(proxy.fit.refs, v)

          case near_items(body, over, ring, 3) do
            [] -> mean
            uvs -> uvs |> Enum.map(&sample(sw, &1)) |> Vec.mean()
          end
          |> Tuple.to_list()
          |> Enum.zip_with(factor, &min(255, round(&1 * &2)))
          |> List.to_tuple()
        end
    end
  end

  # The place on the base mesh at rest of a line of a fit (its points of the body by their weights).
  defp at_rest({vs, ws, _}, base),
    do: Enum.zip(vs, ws) |> Enum.map(fn {b, w} -> Vec.scale(elem(base, b), w) end) |> Enum.reduce(&Vec.add/2)

  # The UVs of the points of an item over some body points, else over their neighbors (at most `steps`
  # rings out).
  defp near_items(body, over, ring, steps) do
    case Enum.flat_map(body, &Map.get(over, &1, [])) do
      [] when steps > 0 ->
        near_items(body |> Enum.flat_map(&Map.get(ring, &1, [])) |> Enum.uniq(), over, ring, steps - 1)

      uvs ->
        uvs
    end
  end

  # For each point of the body, the UVs of the points of an item over it (the first point of the fit of
  # each point of the item; a point of a helper is the point of the body under it).
  defp items_over(c) do
    Data.cached({:items_over, c.name}, fn ->
      under = Data.body_points()

      uv =
        for f <- c.mesh.groups |> Map.values() |> Enum.concat(), {v, t} <- f, t != nil, reduce: %{} do
          acc -> Map.put_new(acc, v, elem(c.mesh.uvs, t))
        end

      for {{[b | _], _, _}, v} <- c.fit.refs |> Tuple.to_list() |> Enum.with_index(),
          at = uv[v],
          at != nil,
          reduce: %{} do
        acc -> Map.update(acc, Map.get(under, b, b), [at], &[at | &1])
      end
    end)
  end

  # The swatch of an item (`scripts/swatches.py`), or nil.
  defp swatch(c), do: Data.swatch(c.name)

  # The color of a swatch at a UV (v from the bottom of the image, and the image wraps).
  defp sample({w, h, ch, rows}, {u, v}) do
    x = Integer.mod(floor(u * w), w)
    y = Integer.mod(floor((1 - v) * h), h)
    <<r, g, b, _::binary>> = binary_part(elem(rows, y), x * ch, ch)
    {r / 1, g / 1, b / 1}
  end

  # A low-poly body of MakeHuman for mid, with each face on the breasts
  # cut in four, two times: with its 11 faces on a breast, the bust of a
  # woman at mid is a cone (at far the body stays as it is). Each new
  # point refers to the place on the surface of the body nearest to it
  # (the three points of a face of the body, with their weights, as a fit
  # of MakeHuman), with the offset of the edge or the face that it cuts,
  # so it is on the round bust of each person. The faces around take the
  # new points of their edges, so the mesh has no hole.
  defp proxy_asset("proxy741"), do: Data.asset("proxies", "proxy741")
  defp proxy_asset(name), do: Data.cached({:proxy, name}, fn -> refine(Data.asset("proxies", name)) end)

  defp refine(p) do
    breasts = MapSet.new(Data.breast_points())
    on? = fn {v, _} -> p.fit.refs |> elem(v) |> elem(0) |> Enum.all?(&MapSet.member?(breasts, &1)) end
    faces = p.mesh.groups |> Map.values() |> Enum.concat()
    cut = faces |> Enum.filter(&Enum.all?(&1, on?)) |> MapSet.new()

    # A new point: its place on the base mesh (the points of the file of
    # the proxy are not in the axes of the base mesh: their fit is), its
    # offset, its UV.
    start = %{
      points:
        p
        |> fit_positions(Data.base().points)
        |> Tuple.to_list()
        |> Enum.with_index()
        |> Map.new(fn {q, i} -> {i, q} end),
      offsets: p.fit.refs |> Tuple.to_list() |> Enum.with_index() |> Map.new(fn {{_, _, d}, i} -> {i, d} end),
      uvs: p.mesh.uvs |> Tuple.to_list() |> Enum.with_index() |> Map.new(fn {t, i} -> {i, t} end),
      mids: %{},
      faces: MapSet.to_list(cut)
    }

    halved = Enum.reduce(1..2, start, fn _, acc -> quarter(acc) end)
    n0 = tuple_size(p.mesh.points)
    # (The faces round each point of the body: made here and not kept, since the refined proxy is kept.)
    around =
      for f <- Map.fetch!(Data.base().groups, "body"), vs = Enum.map(f, &elem(&1, 0)), v <- vs, reduce: %{} do
        acc -> Map.update(acc, v, [vs], &[vs | &1])
      end

    new_refs =
      for i <- n0..(map_size(halved.points) - 1)//1, do: on_body(halved.points[i], halved.offsets[i], around)

    # The faces around: the new points of their edges, in their order.
    split = fn split, {a, ta}, {b, tb} ->
      case halved.mids[{min(a, b), max(a, b)}] do
        nil ->
          []

        {m, tm} ->
          split.(split, {a, ta}, {m, tm}) ++ [{m, tm}] ++ split.(split, {m, tm}, {b, tb})
      end
    end

    widen = fn f ->
      if MapSet.member?(cut, f),
        do: [f],
        else: [Enum.flat_map(Enum.zip(f, tl(f) ++ [hd(f)]), fn {x, y} -> [x | split.(split, x, y)] end)]
    end

    groups =
      Map.new(p.mesh.groups, fn {g, fs} ->
        {g, Enum.flat_map(fs, fn f -> if MapSet.member?(cut, f), do: [], else: widen.(f) end)}
      end)

    groups = Map.update(groups, Enum.min(Map.keys(groups)), halved.faces, &(&1 ++ halved.faces))

    %{
      p
      | mesh: %{
          p.mesh
          | points:
              List.to_tuple(
                Tuple.to_list(p.mesh.points) ++ for(i <- n0..(map_size(halved.points) - 1)//1, do: halved.points[i])
              ),
            uvs: List.to_tuple(for(i <- 0..(map_size(halved.uvs) - 1), do: halved.uvs[i])),
            groups: groups
        },
        fit: %{p.fit | refs: List.to_tuple(Tuple.to_list(p.fit.refs) ++ new_refs)}
    }
  end

  # Each face in four: a point at the middle of each edge (one for two
  # faces), and one at the middle of the face.
  defp quarter(acc) do
    Enum.reduce(acc.faces, %{acc | faces: []}, fn f, acc ->
      {mids, acc} =
        Enum.map_reduce(Enum.zip(f, tl(f) ++ [hd(f)]), acc, fn {{a, ta}, {b, tb}}, acc ->
          key = {min(a, b), max(a, b)}

          case acc.mids[key] do
            nil ->
              m = map_size(acc.points)
              tm = map_size(acc.uvs)

              acc = %{
                acc
                | points: Map.put(acc.points, m, Vec.lerp(acc.points[a], acc.points[b], 0.5)),
                  offsets: Map.put(acc.offsets, m, Vec.lerp(acc.offsets[a], acc.offsets[b], 0.5)),
                  uvs: Map.put(acc.uvs, tm, uv_mid(acc.uvs[ta], acc.uvs[tb])),
                  mids: Map.put(acc.mids, key, {m, tm})
              }

              {{m, tm}, acc}

            {m, tm} ->
              {{m, tm}, acc}
          end
        end)

      c = map_size(acc.points)
      tc = map_size(acc.uvs)
      corners = Enum.map(f, &elem(&1, 0))

      acc = %{
        acc
        | points: Map.put(acc.points, c, corners |> Enum.map(&acc.points[&1]) |> Vec.mean()),
          offsets: Map.put(acc.offsets, c, corners |> Enum.map(&acc.offsets[&1]) |> Vec.mean()),
          uvs:
            Map.put(
              acc.uvs,
              tc,
              uv_mid(
                uv_mid(acc.uvs[elem(Enum.at(f, 0), 1)], acc.uvs[elem(Enum.at(f, 2), 1)]),
                uv_mid(acc.uvs[elem(Enum.at(f, 1), 1)], acc.uvs[elem(Enum.at(f, 3), 1)])
              )
            )
      }

      # The quad of each corner: the corner, the middle of its edge, the
      # middle of the face, the middle of the edge before it.
      n = length(f)

      quads =
        for i <- 0..(n - 1) do
          [Enum.at(f, i), Enum.at(mids, i), {c, tc}, Enum.at(mids, rem(i - 1 + n, n))]
        end

      %{acc | faces: acc.faces ++ quads}
    end)
  end

  # The place on the surface of the body nearest to a point of the base
  # mesh: of the triangles of the faces around the nearest point of the
  # body, the nearest one, and the weights of its three corners there.
  # `around`: the faces round each point of the body.
  defp on_body(q, offset, around) do
    %{points: base} = Data.base()

    v = Enum.min_by(0..13379, &Vec.len(Vec.sub(elem(base, &1), q)))

    {_, vs, ws} =
      around
      |> Map.fetch!(v)
      |> Enum.flat_map(fn [a, b, c, d] -> [[a, b, c], [a, c, d]] end)
      |> Enum.map(fn tri ->
        ws = barycentric(q, Enum.map(tri, &elem(base, &1)))
        at = tri |> Enum.zip(ws) |> Enum.map(fn {k, w} -> Vec.scale(elem(base, k), w) end) |> Enum.reduce(&Vec.add/2)
        {Vec.len(Vec.sub(at, q)), tri, ws}
      end)
      |> Enum.min_by(&elem(&1, 0))

    {vs, ws, offset}
  end

  # The weights of the place on a triangle nearest to a point (the point
  # projected on its plane; a weight under 0 is 0).
  defp barycentric(q, [a, b, c]) do
    {v0, v1, v2} = {Vec.sub(b, a), Vec.sub(c, a), Vec.sub(q, a)}
    {d00, d01, d11, d20, d21} = {Vec.dot(v0, v0), Vec.dot(v0, v1), Vec.dot(v1, v1), Vec.dot(v2, v0), Vec.dot(v2, v1)}
    den = d00 * d11 - d01 * d01
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    ws = Enum.map([1 - v - w, v, w], &max(&1, 0.0))
    sum = Enum.sum(ws)
    Enum.map(ws, &(&1 / sum))
  end

  defp uv_mid({u1, v1}, {u2, v2}), do: {(u1 + u2) / 2, (v1 + v2) / 2}

  defp grow(set, ring), do: set |> Enum.flat_map(&Map.get(ring, &1, [])) |> MapSet.new() |> MapSet.union(set)

  # The points of the body under clothes: the points that the clothes
  # hide, and the points that hold the clothes (a point of a helper of
  # the base mesh holds the point of the body under it).
  defp cover(%{fit: fit}) do
    under = Data.body_points()

    fit.refs
    |> Tuple.to_list()
    |> Enum.flat_map(&elem(&1, 0))
    |> Enum.map(&Map.get(under, &1, &1))
    |> MapSet.new()
    |> MapSet.union(fit.delete)
  end

  # The morph targets of a person: with speech, the moves of the visemes,
  # for each point of the base mesh; with expressions, the moves of the
  # face shapes; with blink, the shapes of a blink. A shape of the face at
  # rest moves only the rest of the way.
  defp shapes(o) do
    faces =
      cond do
        o.expressions -> Face.shapes(o.race)
        o.blink -> Face.shapes(o.race, @blink)
        true -> []
      end

    for {n, moves} <- if(o.speech, do: Face.visemes(o.race), else: []) ++ faces do
      k = 1.0 - Map.get(o.rest, n, 0.0)
      {n, &Vec.scale(Map.get(moves, &1, {0.0, 0.0, 0.0}), k)}
    end
  end

  # The animation "blink": a loop of 4 s with one blink at its start, as
  # the weights of the targets of the mesh (the mesh node `node`): the
  # eyelids close in 0.07 s, stay closed 0.05 s, and open in 0.15 s.
  defp blink(%{blink: false}, _prims, _node), do: []

  defp blink(_o, prims, node) do
    names = prims |> Enum.find_value(& &1.targets) |> Enum.map(&elem(&1, 0))
    closed = fn w -> for n <- names, do: if(n in @blink, do: w, else: 0.0) end

    [
      %{
        name: "blink",
        channels: [
          %{
            node: node,
            path: :weights,
            times: [0.0, 0.07, 0.12, 0.27, 4.0],
            values: Enum.map([0.0, 1.0, 1.0, 0.0, 0.0], closed)
          }
        ]
      }
    ]
  end

  # The animation "talk": the weights of the visemes for the cues of the
  # option talk (World.People.Face.talk/2), with the other targets at 0.
  defp talk(%{speech: true, talk: [_ | _] = cues}, prims, node) do
    names = prims |> Enum.find_value(& &1.targets) |> Enum.map(&elem(&1, 0))
    keys = Face.talk(cues)

    [
      %{
        name: "talk",
        channels: [
          %{
            node: node,
            path: :weights,
            times: Enum.map(keys, &elem(&1, 0)),
            values: for({_, w} <- keys, do: for(n <- names, do: Map.get(w, n, 0.0)))
          }
        ]
      }
    ]
  end

  defp talk(_o, _prims, _node), do: []

  # The face at rest: the points of the body with the shapes of the face at
  # rest by their weights.
  defp rest_face(points, %{rest: rest}) when rest == %{}, do: points

  defp rest_face(points, o) do
    moves =
      for {n, moves} <- Face.shapes(o.race, Map.keys(o.rest)), {i, d} <- moves, reduce: %{} do
        acc -> Map.update(acc, i, Vec.scale(d, o.rest[n]), &Vec.add(&1, Vec.scale(d, o.rest[n])))
      end

    points
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> Vec.add(p, Map.get(moves, i, {0.0, 0.0, 0.0})) end)
    |> List.to_tuple()
  end

  # The moves of the shapes for the points of an asset (or of a body at
  # mid and far): the moves of the points of the body that it fits to, by
  # the weights of the fit.
  defp fit_shapes(a, shapes) do
    for {n, move} <- shapes do
      {n,
       fn i ->
         {vs, ws, _} = elem(a.fit.refs, i)
         Enum.zip(vs, ws) |> Enum.map(fn {v, w} -> Vec.scale(move.(v), w) end) |> Enum.reduce(&Vec.add/2)
       end}
    end
  end

  # A face of the cornea of the eyes of MakeHuman (its UVs in the corner of
  # the texture, a black disk): MakeHuman draws it clear; it goes, so the
  # iris shows.
  defp cornea?(a, face),
    do:
      Enum.all?(face, fn {_, t} ->
        {u, v} = elem(a.mesh.uvs, t)
        u > 0.85 and v < 0.15
      end)

  # The points of the body that an asset fits to: a cloth fits to the body
  # with no nipples (`cloth/1`).
  defp on(role, points, dressed),
    do: if(String.starts_with?(Atom.to_string(role), "clothes_"), do: dressed, else: points)

  # The eyebrows and the eyelashes move with the skin of the face.
  defp face(role, shapes) when role in [:eyebrows, :eyelashes], do: shapes
  defp face(_role, _shapes), do: []

  # An asset on the body: its points from the points of the body, its
  # weights from theirs; the moves of its shapes from the moves of the
  # points of the body (by the weights of the fit), or `{:own, shapes}`:
  # the moves of the points of the asset.
  defp fitted(role, a, points, weights, ground, shapes \\ [], color \\ nil) do
    {pts, wts} = fit_points(a, points, weights)
    faces = a.mesh.groups |> Map.values() |> Enum.concat() |> Enum.reject(&(role == :eyes and cornea?(a, &1)))
    uv = fn i -> if i, do: elem(a.mesh.uvs, i), else: {0.0, 0.0} end
    shapes = with {:own, own} <- shapes, do: own, else: (base -> fit_shapes(a, base))
    mesh(role, faces, &elem(pts, &1), uv, &elem(wts, &1), ground, shapes, color)
  end

  # The teeth are ivory, not white, and the tongue less bright (a factor
  # of the texture); both are wet (roughness 0.3).
  defp mouth_color(:teeth), do: %{"color" => [232, 224, 208], "roughness" => 0.3}
  defp mouth_color(:tongue), do: %{"color" => [220, 200, 200], "roughness" => 0.3}

  # The shadow in the mouth: the colors of the points of the teeth and the
  # tongue, from 1 at the front to 0.3 at the back (+y of World is the
  # front). With no shadow, the teeth at the back and the sides are as
  # bright as the front teeth, and show white at the corners of the lips.
  defp shade(%Scene.Primitive{positions: ps} = p) do
    {back, front} = ps |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    colors =
      for {_, y, _} <- ps do
        c = round(255 * (0.3 + 0.7 * :math.pow((y - back) / (front - back), 1.5)))
        {c, c, c}
      end

    %{p | colors: colors}
  end

  # The shapes of the teeth and the tongue. The units of MakeHuman move
  # the points of the teeth with the mouth, but not the points of the
  # tongue: the tongue moves with the lower teeth (the half of the teeth
  # below their middle, their mean move), all of it at the tip and 0.7
  # of it at the back, as on a jaw that turns. The upper teeth go down
  # 0.25 of the drop of the lower teeth: with the fit, the upper lip
  # hides all of the upper teeth when the mouth opens, and in a real
  # mouth 2 to 4 mm of them show.
  defp mouth_shapes(role, a, mouth, points, shapes) do
    teeth = Keyword.fetch!(mouth, :teeth)
    ys = for p <- Tuple.to_list(fit_positions(teeth, points)), do: elem(p, 1)
    middle = (Enum.min(ys) + Enum.max(ys)) / 2
    lower = for {y, i} <- Enum.with_index(ys), y < middle, do: i
    upper = ys |> Enum.map(&(&1 >= middle)) |> List.to_tuple()

    jaw = fn move -> lower |> Enum.map(move) |> Enum.reduce(&Vec.add/2) |> Vec.scale(1 / length(lower)) end

    case role do
      :teeth ->
        own =
          for {n, move} <- fit_shapes(teeth, shapes) do
            {_, drop, _} = jaw.(move)
            down = {0.0, 0.25 * min(drop, 0.0), 0.0}
            {n, fn i -> if elem(upper, i), do: Vec.add(move.(i), down), else: move.(i) end}
          end

        {:own, own}

      :tongue ->
        tip = a |> fit_positions(points) |> Tuple.to_list() |> Enum.map(&elem(&1, 2))
        {back, front} = Enum.min_max(tip)
        tip = List.to_tuple(for z <- tip, do: 1.0 + 0.4 * (z - back) / (front - back))

        own =
          for {n, move} <- fit_shapes(teeth, shapes) do
            drop = jaw.(move)
            {n, &Vec.scale(drop, elem(tip, &1))}
          end

        {:own, own}
    end
  end

  defp fit_points(%{fit: fit} = a, points, weights) do
    weights = for {vs, ws, _} <- Tuple.to_list(fit.refs), do: blend(weights, Enum.zip(vs, ws))
    {positions(a, points), List.to_tuple(weights)}
  end

  defp positions(a, points), do: a |> fit_positions(points) |> drape(a, points)

  # The cloth spans the dips of the body (`World.Sewing`): at each step,
  # each point of the drape moves out along the offset of its fit to the
  # mean of its neighbors in the mesh of the garment, but not nearer to
  # the body than at the fit. So the cloth bridges a dip (between the
  # breasts, under the bust) and stays on a round part. A point does not
  # move to the side: it stays over its point of the body, so it does not
  # go into a layer under it. The drape runs on the body of the person:
  # it is the same on each shape.
  defp drape(q, %{drape: nil}, _points), do: q

  defp drape(q, %{drape: %{points: ps, steps: steps}} = a, points) do
    ring = mesh_ring(a)
    body = fn i -> elem(points, a.fit.refs |> elem(i) |> elem(0) |> hd()) end

    least =
      Map.new(ps, fn i ->
        d = Vec.sub(elem(q, i), body.(i))
        {i, {Vec.norm(d), Vec.len(d)}}
      end)

    moved =
      Enum.reduce(1..steps//1, Map.new(ps, &{&1, elem(q, &1)}), fn _, m ->
        at = fn i -> Map.get(m, i) || elem(q, i) end

        Map.new(ps, fn i ->
          c = Vec.lerp(at.(i), ring |> Map.fetch!(i) |> Enum.map(at) |> Vec.mean(), 0.5)
          {n, d} = least[i]
          {i, Vec.add(body.(i), Vec.scale(n, max(d, Vec.dot(Vec.sub(c, body.(i)), n))))}
        end)
      end)

    Enum.reduce(moved, q, fn {i, p}, acc -> put_elem(acc, i, p) end)
  end

  # The neighbors of each point of the mesh of an asset.
  # (A garment sewn with the options of an order, `variant`, is not kept: there can be many.)
  defp mesh_ring(%{variant: true} = a), do: ring_of(a)
  defp mesh_ring(a), do: Data.cached({:mesh_ring, a.name}, fn -> ring_of(a) end)

  defp ring_of(a) do
    a.mesh.groups
    |> Map.values()
    |> Enum.concat()
    |> Enum.reduce(%{}, fn f, acc ->
      vs = Enum.map(f, &elem(&1, 0))
      Enum.reduce(vs, acc, fn v, acc -> Map.update(acc, v, vs -- [v], &Enum.uniq(&1 ++ (vs -- [v]))) end)
    end)
  end

  # The points of an asset on the body (MakeHuman, "mhclo"): the sum of
  # three points of the body with their weights, and an offset in the
  # scale of the body.
  defp fit_positions(%{fit: fit}, points) do
    # A scale is the distance of two points of the body over their
    # distance in the base mesh; with no scale, 1.
    scale = fn axis, k ->
      with {a, b, d} <- Map.get(fit.scales, axis, 1.0), do: abs(elem(elem(points, a), k) - elem(elem(points, b), k)) / d
    end

    s = {scale.("x_scale", 0), scale.("y_scale", 1), scale.("z_scale", 2)}

    fit.refs
    |> Tuple.to_list()
    |> Enum.map(fn {vs, ws, {dx, dy, dz}} ->
      p = Enum.zip(vs, ws) |> Enum.map(fn {v, w} -> Vec.scale(elem(points, v), w) end) |> Enum.reduce(&Vec.add/2)
      Vec.add(p, {dx * elem(s, 0), dy * elem(s, 1), dz * elem(s, 2)})
    end)
    |> List.to_tuple()
  end

  # A primitive from faces of `{point, uv}`: one vertex for each pair, the
  # normal of each point from its faces, and the 4 weights.
  # `shapes`: a list of `{name, move}`, the move of a point of the base
  # mesh (in the units of MakeHuman): the morph targets of the mesh.
  defp mesh(role, faces, pos, uv, wts, ground, shapes, color \\ nil) do
    tris = Enum.flat_map(faces, fn [a, b, c | rest] -> fan(a, [b, c | rest]) end)
    p = fn v -> Vec.sub(to_world(pos.(v)), {0.0, 0.0, ground}) end

    normals =
      tris
      |> Enum.flat_map(fn [{a, _}, {b, _}, {c, _}] ->
        n = Vec.cross(Vec.sub(p.(b), p.(a)), Vec.sub(p.(c), p.(a)))
        [{a, n}, {b, n}, {c, n}]
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {v, ns} -> {v, Vec.norm(Enum.reduce(ns, &Vec.add/2))} end)

    {indices, {_, verts}} =
      tris
      |> List.flatten()
      |> Enum.map_reduce({%{}, []}, fn key, {seen, verts} ->
        case seen do
          %{^key => i} -> {i, {seen, verts}}
          _ -> {map_size(seen), {Map.put(seen, key, map_size(seen)), [key | verts]}}
        end
      end)

    verts = Enum.reverse(verts)
    joints = for {v, _} <- verts, do: pad4(wts.(v))

    %Scene.Primitive{
      material: role,
      positions: for({v, _} <- verts, do: p.(v)),
      normals: for({v, _} <- verts, do: normals[v]),
      uvs: if(uv, do: for({_, t} <- verts, do: flip_v(uv.(t)))),
      colors: if(color, do: for({v, _} <- verts, do: color.(v))),
      joints: for(js <- joints, do: List.to_tuple(Enum.map(js, &elem(&1, 0)))),
      weights: for(js <- joints, do: List.to_tuple(Enum.map(js, &(elem(&1, 1) / 1)))),
      indices: indices,
      targets: if(shapes != [], do: for({n, move} <- shapes, do: {n, sparse(verts, move)}))
    }
  end

  # The moves of a shape for the vertices of a primitive: only the
  # vertices that move, by their index (a shape of the face moves few of
  # the points of the body).
  defp sparse(verts, move) do
    verts
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{v, _}, i}, acc ->
      case to_world(move.(v)) do
        {x, y, z} when x * x + y * y + z * z > 1.0e-14 -> Map.put(acc, i, {x, y, z})
        _ -> acc
      end
    end)
  end

  defp fan(a, [b, c | rest]), do: [[a, b, c] | fan(a, [c | rest])]
  defp fan(_, [_]), do: []

  defp pad4(ws), do: Enum.take(ws ++ List.duplicate({0, 0.0}, 4), 4)
  defp flip_v({u, v}), do: {u, 1.0 - v}

  # The colors that the order chose, by the name of the asset.
  defp chosen_colors(o) do
    hair = if o.hair && o.hair_color, do: [{o.hair, o.hair_color}], else: []
    Map.new(hair ++ Enum.zip(o.clothes, o.clothes_colors))
  end

  # The factor of a textured material. A gray texture (a hair) takes the
  # color of the order, or the mean color of the texture before it was
  # gray. Another texture takes the ratio of the color of the order to its
  # mean color: a tint, which can only make it darker. The base of the
  # tint (`tint_base`, in the extras of the material of the GLB) lets a
  # viewer show another color at once: factor = color * 255 / base.
  defp tint(spec, %{gray: gray} = a, o) when is_number(gray),
    do:
      spec
      |> Map.put("color", Enum.map(Map.get(o.colors, a.name, a.color), &min(255, round(&1 * 255 / gray))))
      |> Map.put("tint_base", [gray, gray, gray])

  defp tint(spec, a, o) do
    spec = Map.put(spec, "tint_base", a.color)

    case Map.fetch(o.colors, a.name) do
      {:ok, c} -> Map.put(spec, "color", Enum.zip_with(c, a.color, &min(255, round(&1 * 255 / max(&2, 1)))))
      :error -> spec
    end
  end

  # The alpha of an asset: the eyebrows and the eyelashes have soft
  # strands (a blend: with a cut at 0.5 only black specks of them stay);
  # the hair and a transparent item have holes.
  defp alpha(role, _a) when role in [:eyebrows, :eyelashes], do: :blend
  defp alpha(role, a), do: a.transparent or role == :hair

  defp textured_item(a, mat, role), do: textured((mat || a).texture, alpha(role, a))

  # The colors of the points of an item with a print (or nil): the print at the place on the base mesh at
  # rest of each point (`World.Sewing.print/2`), over the mean color of the texture of the item, so the
  # texture times the color is the color of the print. The material of the item is then white.
  defp printed(%{print: %{} = print} = a) do
    base = Data.base().points

    fn v ->
      World.Sewing.print(print, at_rest(elem(a.fit.refs, v), base))
      |> Enum.zip_with(a.color, &min(255, round(&1 * 255 / max(&2, 1))))
      |> List.to_tuple()
    end
  end

  defp printed(_a), do: nil

  defp unprinted(spec, %{print: %{}}), do: Map.put(spec, "color", [255, 255, 255])
  defp unprinted(spec, _a), do: spec

  defp textured(path, alpha) do
    mime = if String.ends_with?(path, ".png"), do: "image/png", else: "image/jpeg"

    spec = %{
      "color" => [255, 255, 255],
      "roughness" => 0.75,
      "metalness" => 0.0,
      "image" => {mime, World.People.Files.read!(path)}
    }

    case alpha do
      :blend -> Map.merge(spec, %{"alpha_mode" => "BLEND", "double_sided" => true})
      true -> Map.merge(spec, %{"alpha_mode" => "MASK", "double_sided" => true})
      false -> spec
    end
  end

  # --- The nodes of the figure ---------------------------------------------------

  defp nodes(name, %Skeleton{bones: bones} = skeleton, prims, pose, head) do
    index = bones |> Enum.with_index(1) |> Map.new(fn {b, i} -> {b.name, i} end)
    locals = Skeleton.locals(skeleton, pose)

    bone_nodes =
      for b <- bones do
        %Scene.Node{
          name: b.name,
          parent: if(b.parent, do: index[b.parent], else: 0),
          frame: locals[b.name],
          scale: if(b.name == "head", do: head / 1, else: 1.0)
        }
      end

    # glTF ignores the frame of a skinned mesh: the mesh is a root node.
    mesh = %Scene.Node{name: name <> "_mesh", skin: 0, primitives: prims}
    root = %Scene.Node{name: name}

    skin = %{
      name: name,
      joints: Enum.map(bones, &index[&1.name]),
      inverse_bind: Enum.map(bones, &Frame.invert(&1.frame)),
      skeleton: 1
    }

    {[root | bone_nodes] ++ [mesh], skin}
  end

  # The ports of a person: the ground and the hips (at rest), and the
  # ports on the bones for the props (`World.Figure.hold/4`).
  defp ports(bones, points, weights, ground) do
    by = Map.new(bones, &{&1.name, &1})
    index = bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
    at = fn v -> Vec.sub(to_world(elem(points, v)), {0.0, 0.0, ground}) end
    # The points of the skin that follow a bone (half or more).
    skin = fn bone ->
      for {v, ws} <- weights, Enum.any?(ws, fn {b, w} -> b == index[bone] and w >= 0.5 end), do: at.(v)
    end

    {{x0, y0, _}, {x1, y1, top}} = Vec.bounds(skin.("head"))
    back = skin.("spine_03")
    {_, ymin, _} = Vec.bounds(back) |> elem(0)
    spine = by["spine_03"]

    on_bones =
      [
        {"crown", "head", Part.port("crown", {(x0 + x1) / 2, (y0 + y1) / 2, top}, {0, 0, 1}, {0, 1, 0})},
        {"back", "spine_03",
         Part.port("back", {0.0, ymin - 0.01, (elem(spine.head, 2) + elem(spine.tail, 2)) / 2}, {0, -1, 0}, {0, 0, 1})}
      ] ++
        for side <- ~w(l r), {name, bone, port} <- [grip(by, side), sole(by, side)], do: {name, bone, port}

    pelvis = by["pelvis"]

    Map.merge(
      %{
        "ground" => Part.port("ground", {0.0, 0.0, 0.0}, {0, 0, 1}, {0, 1, 0}),
        "hips" => Part.port("hips", pelvis.head, {0, 0, 1}, {0, 1, 0})
      },
      Map.new(on_bones, fn {name, bone, port} -> {name, on_bone(port, by[bone])} end)
    )
  end

  # The grip of a hand: in the palm, where a closed hand holds a handle.
  # The axis is the line of the handle, to the side of the thumb; `up`
  # goes out of the palm.
  defp grip(by, side) do
    [hand, middle, index, pinky] = Enum.map(~w(hand middle_01 index_01 pinky_01), &by["#{&1}_#{side}"])
    along = Vec.norm(Vec.sub(middle.head, hand.head))
    across = Vec.norm(Vec.sub(index.head, pinky.head))
    palm = Vec.scale(Vec.norm(Vec.cross(along, across)), if(side == "l", do: 1.0, else: -1.0))
    at = Vec.add(Vec.lerp(hand.head, middle.head, 0.55), Vec.scale(palm, 0.03))
    axis = Vec.norm(Vec.sub(across, Vec.scale(palm, Vec.dot(across, palm))))
    {"grip_#{side}", "hand_#{side}", Part.port("grip_#{side}", at, axis, palm)}
  end

  # The sole of a foot: on the ground under the middle of the foot, its
  # axis down, `up` to the toes.
  defp sole(by, side) do
    {foot, ball} = {by["foot_#{side}"], by["ball_#{side}"]}
    {x, y, _} = Vec.lerp(foot.head, ball.head, 0.5)
    {dx, dy, _} = Vec.sub(ball.head, foot.head)
    {"sole_#{side}", "foot_#{side}", Part.port("sole_#{side}", {x, y, 0.0}, {0, 0, -1}, {dx, dy, 0.0})}
  end

  # A port in the axes of World of the person at rest, as a port on a
  # bone: in the axes of the bone.
  defp on_bone(port, bone) do
    f = Frame.compose(Frame.invert(bone.frame), Port.frame(port))
    %{Port.new(port.name, f.at, f.z, f.y) | bone: bone.name}
  end

  # --- The kit: the parts of a person for a viewer -------------------------------

  @races ~w(african asian caucasian)

  @doc """
  The names of the shape targets of a kit (`kit/3`) of a sex (0: a woman,
  1: a man): the targets of `target_weights/1` with the mean muscle, for
  each age, weight, height and origin, the breasts of a woman, the
  sliders of the short names of the shape (`shapes/0`; not all the
  sliders: each target makes the body of the kit bigger), and for a woman
  the targets of the shape that the clothes give (the cups of the bra of
  `World.Sewing`), in a fixed order.

      iex> length(World.People.Human.kit_targets(1))
      48
      iex> length(World.People.Human.kit_targets(0))
      99
      iex> hd(World.People.Human.kit_targets(0))
      "african-female-young"
  """
  def kit_targets(gender) do
    g = if gender < 0.5, do: "female", else: "male"
    ages = ~w(young old)
    weights = ~w(minweight averageweight maxweight)

    breasts =
      if g == "female",
        do:
          for(
            a <- ages,
            w <- weights,
            c <- ~w(mincup averagecup maxcup),
            f <- ~w(minfirmness averagefirmness maxfirmness),
            {c, f} != {"averagecup", "averagefirmness"},
            do: "breast/female-#{a}-averagemuscle-#{w}-#{c}-#{f}"
          ),
        else: []

    sliders = Data.sliders()

    for(r <- @races, a <- ages, do: "#{r}-#{g}-#{a}") ++
      for(a <- ages, w <- weights, do: "universal-#{g}-#{a}-averagemuscle-#{w}") ++
      for(a <- ages, w <- weights, h <- ~w(minheight maxheight), do: "height/#{g}-#{a}-averagemuscle-#{w}-#{h}") ++
      breasts ++
      for({_, {_, names}} <- @shape, s <- names, t <- sliders[s].decr ++ sliders[s].incr, do: t) ++
      if(g == "female", do: worn_targets(), else: [])
  end

  # The targets of the shapes that the clothes give to the body, once each.
  defp worn_targets do
    Data.assets()["clothes"]
    |> Map.keys()
    |> Enum.sort()
    |> Enum.flat_map(&Data.asset("clothes", &1).shape)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end

  @doc """
  The targets of a kit, in groups: the targets of `kit_targets/1` with
  the same moves are one group (MakeHuman has copies), and a target with
  no move goes. The weight of a group is the sum of the weights of its
  targets.
  """
  def kit_groups(gender) do
    gender
    |> kit_targets()
    |> Enum.map(&{&1, Map.new(Data.target(&1))})
    |> Enum.reject(fn {_, moves} -> moves == %{} end)
    |> Enum.reduce([], fn {name, moves}, groups ->
      case Enum.find_index(groups, fn {m, _} -> m == moves end) do
        nil -> groups ++ [{moves, [name]}]
        i -> List.update_at(groups, i, fn {m, ns} -> {m, ns ++ [name]} end)
      end
    end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  A part of the kit of a person (at mid), for a viewer that changes the
  body at once, with no new build: the shape is the weights of the
  targets of `kit_targets/1` (`target_weights/1`), and the viewer moves
  the bones and sets the weights of the morph targets.

  - `:body`: the body of a sex (0 or 1) with all the faces in one
    primitive of the material `skin`, the eyes, the eyebrows (`eyebrow010`
    for a woman, `eyebrow001` for a man) and the mouth closed behind; the
    skeleton in the pose "stand", and the animations "wave", "point" and
    "blink". The extras of the mesh node (`"kit"`) have the targets, the
    move of the head of each bone for each target, the ground under each
    pair of shoes, the faces that each item of clothes covers (the viewer
    gives a face the color of the item that covers the most of it, as
    `person/2` at mid) and the color of each item.
  - `{:hair, name}`: the hair, with the same skeleton (its mesh goes on
    the skeleton of the body).

  A morph target has the move of a point less the moves of its bones:
  the viewer moves the bones, so the mesh follows them, and the target
  adds the rest of the change of the shape. The ground is at z = 0 of
  the base mesh (the viewer puts the person down by the ground of its
  shoes). The head has its own size (the viewer can scale the bone).
  """
  def kit(gender, part, opts \\ []) do
    g = if gender < 0.5, do: 0.0, else: 1.0
    hair = with {:hair, h} <- part, do: h, else: (_ -> nil)

    o =
      Map.new(
        Keyword.merge(
          @defaults,
          [
            gender: g,
            eyebrows: if(g == 0.0, do: "eyebrow010", else: "eyebrow001"),
            hair: hair,
            clothes: [],
            pose: "stand"
          ] ++
            opts
        )
      )

    o = o |> Map.put(:colors, %{}) |> Map.put(:rest, Face.rest(o.face)) |> Map.put(:ground, 0.0)
    base = Data.base()
    raw = rest_face(base.points, o)
    points = cloth(raw)
    groups = kit_groups(g)
    names = Enum.map(groups, &hd/1)
    # The smooth of the breasts is linear: each target goes through it.
    shaped = Map.new(names, fn t -> {t, cloth(add_target(raw, t))} end)
    bones = skeleton(points, 0.0)
    weights = Detail.collect(vertex_weights(Enum.map(bones, & &1.name)))
    heads = fn bs -> List.to_tuple(Enum.map(bs, & &1.head)) end
    h0 = heads.(bones)

    moves =
      Map.new(names, fn t ->
        ht = heads.(skeleton(shaped[t], 0.0))
        {t, List.to_tuple(for i <- 0..(tuple_size(h0) - 1), do: Vec.sub(elem(ht, i), elem(h0, i)))}
      end)

    k = %{points: points, shaped: shaped, names: names, groups: groups, moves: moves, weights: weights}

    {prims, materials, extras} =
      Detail.with(:mid, fn ->
        case part do
          :body -> kit_body(base, o, k, bones)
          {:hair, _} -> kit_hair(o, k)
        end
      end)

    skeleton = Skeleton.new(bones)
    pose = Pose.expand(Pose.resolve(o.pose))
    {nodes, skin} = nodes("traveler", skeleton, prims, pose, 1.0)
    {mesh, rest} = List.pop_at(nodes, -1)
    nodes = rest ++ [%{mesh | extras: %{"kit" => extras}}]

    animations =
      if part == :body,
        do: for(a <- ~w(wave point), do: Pose.animation(a, bones, hands: %{})) ++ blink(o, prims, length(nodes) - 1),
        else: []

    %Figure{
      name: "traveler",
      kind: :person,
      params: %{"gender" => g, "part" => if(hair, do: "hair " <> hair, else: "body")},
      sources: ["MakeHuman (CC0): the base mesh, the targets, the skeleton game_engine, and the assets."],
      nodes: nodes,
      skins: [skin],
      animations: animations,
      materials: materials,
      ports: %{},
      skeleton: skeleton,
      pose: pose,
      joints: Joints.all()
    }
  end

  defp add_target(points, name) do
    moves = Map.new(Data.target(name))

    points
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> Vec.add(p, Map.get(moves, i, {0.0, 0.0, 0.0})) end)
    |> List.to_tuple()
  end

  # A point of World in the axes of MakeHuman (the inverse of to_world/1).
  defp from_world({x, y, z}), do: {-x * 10, z * 10, y * 10}

  # The targets of an asset (or of the body at mid): the move of each point
  # less the moves of its bones (in the units of MakeHuman).
  defp kit_shapes(a, wts, k) do
    p0 = fit_positions(a, k.points)

    for t <- k.names do
      pt = fit_positions(a, k.shaped[t])
      d = k.moves[t]

      {t,
       fn i ->
         rigid = elem(wts, i) |> Enum.map(fn {b, w} -> Vec.scale(elem(d, b), w) end) |> Enum.reduce(&Vec.add/2)
         move = Vec.sub(Vec.sub(elem(pt, i), elem(p0, i)), from_world(rigid))
         # A move of less than 0.2 mm goes (MakeHuman: dm).
         if Vec.len(move) < 0.002, do: {0.0, 0.0, 0.0}, else: move
       end}
    end
  end

  defp kit_body(base, o, k, bones) do
    name = if o.gender >= 0.5, do: "male1591", else: "female1605"
    p = proxy_asset(name)
    {pts, wts} = fit_points(p, k.points, k.weights)
    shapes = kit_shapes(p, wts, k) ++ fit_shapes(p, shapes(o))
    faces = p.mesh.groups |> Map.values() |> Enum.concat()
    uv = fn i -> if i, do: elem(p.mesh.uvs, i), else: {0.0, 0.0} end
    skin = mesh(:skin, faces, &elem(pts, &1), uv, &elem(wts, &1), 0.0, shapes)

    {eyes_pts, eyes_wts} = fit_points(Data.asset!("eyes", "low-poly"), k.points, k.weights)
    eyes = Data.asset!("eyes", "low-poly")
    eyes_faces = eyes.mesh.groups |> Map.values() |> Enum.concat() |> Enum.reject(&cornea?(eyes, &1))
    eyes_uv = fn i -> if i, do: elem(eyes.mesh.uvs, i), else: {0.0, 0.0} end

    eyes_prim =
      mesh(:eyes, eyes_faces, &elem(eyes_pts, &1), eyes_uv, &elem(eyes_wts, &1), 0.0, kit_shapes(eyes, eyes_wts, k))

    brows = Data.asset("eyebrows", o.eyebrows)
    {brow_pts, brow_wts} = fit_points(brows, k.points, k.weights)
    brow_faces = brows.mesh.groups |> Map.values() |> Enum.concat()
    brow_uv = fn i -> if i, do: elem(brows.mesh.uvs, i), else: {0.0, 0.0} end
    brow_shapes = kit_shapes(brows, brow_wts, k) ++ fit_shapes(brows, shapes(o))
    brow_prim = mesh(:eyebrows, brow_faces, &elem(brow_pts, &1), brow_uv, &elem(brow_wts, &1), 0.0, brow_shapes)

    holes = holes(p, pts, wts, shapes, 0.0)

    materials = %{
      skin: Map.merge(textured(Data.asset("skins", o.skin).texture, false), Skin.material(:mid)),
      eyes: textured(Data.asset("eye_materials", o.eyes).texture, false),
      eyebrows: textured(brows.texture, :blend),
      hole: %{"color" => [40, 22, 24], "roughness" => 0.9, "metalness" => 0.0}
    }

    {[skin, eyes_prim, holes, brow_prim], materials, body_extras(base, p, faces, bones, k, o)}
  end

  defp kit_hair(o, k) do
    a = Data.asset("hair", o.hair)
    {pts, wts} = fit_points(a, k.points, k.weights)
    faces = a.mesh.groups |> Map.values() |> Enum.concat()
    uv = fn i -> if i, do: elem(a.mesh.uvs, i), else: {0.0, 0.0} end
    prim = mesh(:hair, faces, &elem(pts, &1), uv, &elem(wts, &1), 0.0, kit_shapes(a, wts, k))
    {[prim], %{hair: tint(textured(a.texture, true), a, o)}, %{"targets" => k.groups}}
  end

  # The data of the viewer: the targets, the moves of the bones (glTF
  # axes), the ground under each pair of shoes (and with no shoes), the
  # faces of each item of clothes, and the color of each item.
  defp body_extras(base, p, faces, bones, k, o) do
    round3 = fn {x, y, z} -> [Float.round(x, 5), Float.round(y, 5), Float.round(z, 5)] end

    bone_moves =
      bones
      |> Enum.with_index()
      |> Map.new(fn {b, i} -> {b.name, for(t <- k.names, do: round3.(World.GLB.gl(elem(k.moves[t], i))))} end)

    ground = fn clothes ->
      g0 = ground(base, k.points, clothes)
      [Float.round(g0, 5), for(t <- k.names, do: Float.round(ground(base, k.shaped[t], clothes) - g0, 5))]
    end

    clothes = Data.assets()["clothes"] |> Map.keys() |> Enum.sort()

    shoes =
      for name <- clothes,
          String.starts_with?(name, "shoes"),
          into: %{"none" => ground.([])},
          do: {name, ground.([Data.asset("clothes", name)])}

    ring = neighbors(base)
    refs = Enum.map(faces, fn face -> Enum.flat_map(face, fn {v, _} -> elem(elem(p.fit.refs, v), 0) end) end)
    counts = Enum.map(faces, &(length(&1) - 2))
    starts = Enum.scan([0 | counts], &+/2) |> Enum.drop(-1)
    rows = Enum.zip([refs, starts, counts])

    covers =
      Map.new(clothes, fn name ->
        set = grow(cover(Data.asset("clothes", name)), ring)

        faces =
          for {body, start, count} <- rows,
              n = Enum.count(body, &MapSet.member?(set, &1)),
              n * 2 > length(body),
              do: [start, count, n]

        {name, faces}
      end)

    %{
      "targets" => k.groups,
      "bones" => bone_moves,
      "ground" => shoes,
      "covers" => covers,
      "colors" => Map.new(clothes, &{&1, Data.asset("clothes", &1).color}),
      "skin" => o.skin,
      "eyes" => o.eyes
    }
  end
end
