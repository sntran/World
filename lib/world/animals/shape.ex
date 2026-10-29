defmodule World.Animals.Shape do
  @moduledoc """
  The shape of an animal from numbers: one template mesh for a body plan
  (four legs, or a primate), and a species is its numbers. So a new
  species needs no mesh.

  Each number changes the bones at rest and the skin around them. A
  bone has a scale along it (its length) and across it (its girth):
  each point of the skin moves with the bones that move it, by its
  weights, so the skin stays smooth at the joints. A bone under another
  bone moves with the end of its parent. Some numbers change one part:
  the muzzle (the front of the head), the ears (turned down), the tail
  (turned down), new horns, the skull of a primate. The legs change by
  `scales/5`, so that the body does not tilt. After the change, the
  lowest point of the feet is on the ground. A body much deeper than
  the legs are long can go below the ground: the presets do not.

  | Number | Range | What it changes |
  |---|---|---|
  | `body_length` | 0.6 to 1.8 | The length of the back (the bones `pelvis` and `spine_01`, and `spine_02`, `spine_03` of a primate). |
  | `body_width`, `body_depth` | 0.6 to 1.8 | The width and the depth of the body (and the collarbones of a primate). |
  | `leg_length` | 0.5 to 1.6 | The length of the legs. |
  | `leg_girth` | 0.5 to 1.8 | The thickness of the legs. |
  | `arm_length`, `arm_girth` | 0.5 to 1.8 | The arms and the hands of a primate. |
  | `hand_width` | 0.5 to 1.5 | The width of the hands of a primate (the fingers nearer together). |
  | `neck_length`, `neck_girth` | 0.4 to 1.8 | The neck. |
  | `head_size` | 0.6 to 1.6 | All the head. |
  | `muzzle_length` | 0.3 to 1.8 | The front of the head, from the eyes to the nose. |
  | `muzzle_width` | 0.6 to 1.8 | The width and the depth of the front of the head. |
  | `cranium` | 0.5 to 1.2 | A primate: the height of the skull over the brow. |
  | `ear_size` | 0.5 to 2.0 | The ears (the bones `ear_l`, `ear_r`). |
  | `ear_width` | 0.5 to 2.0 | The width of the ears. |
  | `ear_droop` | -40 to 120 | Degrees: more turns the ears down to the sides. |
  | `tail_length` | 0.1 to 2.0 | The tail. |
  | `tail_girth` | 0.2 to 3.0 | The thickness of the tail. |
  | `tail_down` | -60 to 150 | Degrees: more turns the tail down (0: up as in the template). |
  | `neck_up` | -45 to 60 | Degrees: more turns the neck and the head up around the joint of the neck and the body (0: as in the template). |
  | `head_down` | -45 to 90 | Degrees: more turns the head down around the joint of the head and the neck (0: as in the template). |
  | `horns` | 0 to 1.5 | The length of new horns, in lengths of the head (0: no new horns). |
  | `horn_spread` | 0 to 1 | 0: the horns go up and to the back (a goat); 1: out to the sides (a water buffalo). |

  The coat: a color and a length of the fur for each region of the skin,
  with soft edges between the regions (`regions/3`, `colors/3`,
  `fur/3`), and the direction of the fur at each point (`fur_dirs/3`).
  """
  alias World.Vec

  @numbers %{
    "body_length" => {0.6, 1.8, 1.0},
    "body_width" => {0.6, 1.8, 1.0},
    "body_depth" => {0.6, 1.8, 1.0},
    "leg_length" => {0.5, 1.6, 1.0},
    "leg_girth" => {0.5, 1.8, 1.0},
    "arm_length" => {0.5, 1.8, 1.0},
    "arm_girth" => {0.5, 1.8, 1.0},
    "hand_width" => {0.5, 1.5, 1.0},
    "neck_length" => {0.4, 1.8, 1.0},
    "neck_girth" => {0.4, 1.8, 1.0},
    "head_size" => {0.6, 1.6, 1.0},
    "muzzle_length" => {0.3, 1.8, 1.0},
    "muzzle_width" => {0.6, 1.8, 1.0},
    "cranium" => {0.5, 1.2, 1.0},
    "ear_size" => {0.5, 2.0, 1.0},
    "ear_width" => {0.5, 2.0, 1.0},
    "ear_droop" => {-40.0, 120.0, 0.0},
    "tail_length" => {0.1, 2.0, 1.0},
    "tail_girth" => {0.2, 3.0, 1.0},
    "tail_down" => {-60.0, 150.0, 0.0},
    "neck_up" => {-45.0, 60.0, 0.0},
    "head_down" => {-45.0, 90.0, 0.0},
    "horns" => {0.0, 1.5, 0.0},
    "horn_spread" => {0.0, 1.0, 0.0}
  }

  @regions ~w(back belly mane legs socks head face lids ears tail tail_tip)
  @foot ~r/(^|_)foot_[lr]$/
  @leg ~r/^(front_|hind_|thigh_|calf_|foot_)/

  @doc "The numbers of a shape: a name to `{min, max, default}`."
  def numbers, do: @numbers

  @doc "The regions of the coat, in the order that they paint (a later region covers an earlier one)."
  def regions, do: @regions

  @doc """
  The bones and the points of the template after the numbers `n` (a map
  of a name to a number; a number not in the map is its default). The
  bones are maps with `name`, `parent`, `head` and `tail`, parents
  first; `weights` is a bone to a map of a point to its weight. The
  template gives `muzzle` (the part of the head where the muzzle
  starts). `space` is nil, or a move for each point from a shape space
  (`World.Animals.Space`): in the axes of the bone that moves the point
  most, in the units of the template, scaled as that bone. Gives
  `{bones, points}`.
  """
  def apply(bones, points, weights, n, template, space \\ nil) do
    n = Map.merge(Map.new(@numbers, fn {k, {_, _, d}} -> {k, d} end), n)
    by = Map.new(bones, &{&1.name, &1})
    frames = Map.new(bones, &{&1.name, frame(&1)})
    scales = scales(bones, points, weights, n, template)
    len = head_length(bones)
    heads = heads(bones, frames, scales, n, template)

    tails = Map.new(bones, &{&1.name, move(&1.name, &1.tail, frames, scales, heads, n, len, template)})
    by_point = owners(weights)

    moved =
      points
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        place(p, Map.get(by_point, i, [{"pelvis", 1.0}]), {frames, scales, heads, n, len, template})
      end)

    # The moves of the shape space: in the axes of the bone that moves the
    # point most (a bone turns only after this, with the tail and the
    # ears), scaled as that bone.
    moved =
      if space do
        Enum.zip_with([moved, space, Enum.to_list(0..(length(points) - 1))], fn [p, {a, b, c}, i] ->
          {bone, _} = by_point |> Map.get(i, [{"pelvis", 1.0}]) |> Enum.max_by(fn {bone, w} -> {w, bone} end)
          {_, x, y, z} = frames[bone]
          {sx, sy, sz} = scales[bone]
          p |> Vec.add(Vec.scale(x, a * sx)) |> Vec.add(Vec.scale(y, b * sy)) |> Vec.add(Vec.scale(z, c * sz))
        end)
      else
        moved
      end

    # The tail turns down around the root of the tail (a template with no
    # tail has no turn).
    tail_bones = for b <- bones, String.starts_with?(b.name, "tail_"), do: b.name
    pivot = heads["tail_01"]
    turn = if pivot, do: &turn_x(&1, pivot, n["tail_down"] * :math.pi() / 180), else: & &1

    moved =
      for {p, i} <- Enum.with_index(moved) do
        t =
          by_point
          |> Map.get(i, [])
          |> Enum.filter(&(elem(&1, 0) in tail_bones))
          |> Enum.map(&elem(&1, 1))
          |> Enum.sum()

        Vec.lerp(p, turn.(p), t)
      end

    bones =
      for b <- bones do
        {h, t} = {heads[b.name], tails[b.name]}
        if b.name in tail_bones, do: %{b | head: turn.(h), tail: turn.(t)}, else: %{b | head: h, tail: t}
      end

    # The ears turn down to the sides around their roots, on the axis
    # along the head.
    {bones, moved} =
      for ear <- ~w(ear_l ear_r), Map.has_key?(by, ear), reduce: {bones, moved} do
        {bones, moved} ->
          b = Enum.find(bones, &(&1.name == ear))
          side = if elem(local(frames["head"], by[ear].head), 0) < 0, do: -1, else: 1
          axis = elem(frames["head"], 2)
          spin = &turn(&1, b.head, axis, side * n["ear_droop"] * :math.pi() / 180)
          ws = Map.get(weights, ear, %{})
          moved = moved |> Enum.with_index() |> Enum.map(fn {p, i} -> Vec.lerp(p, spin.(p), Map.get(ws, i, 0.0)) end)
          {Enum.map(bones, &if(&1.name == ear, do: %{&1 | tail: spin.(&1.tail)}, else: &1)), moved}
      end

    # The neck and the head turn up around the joint of the neck and the
    # body, and the head down around the joint of the head and the neck (a
    # point as much as its weights on the bones that turn). No turn at 0:
    # the same points.
    {bones, moved} = bend({bones, moved}, by_point, ~w(neck_01 head ear_l ear_r), "neck_01", n["neck_up"])
    {bones, moved} = bend({bones, moved}, by_point, ~w(head ear_l ear_r), "head", -n["head_down"])

    # The paws on the ground: the lowest point of the feet.
    feet = for b <- bones, b.name =~ ~r/(^|_)foot_[lr]$/, {i, w} <- Map.get(weights, b.name, %{}), w >= 0.5, do: i
    ground = feet |> Enum.map(&elem(Enum.at(moved, &1), 2)) |> Enum.min()
    down = &Vec.sub(&1, {0.0, 0.0, ground})
    {Enum.map(bones, &%{&1 | head: down.(&1.head), tail: down.(&1.tail)}), Enum.map(moved, down)}
  end

  # The bones `names` turn up by `degrees` around the head of the bone
  # `at`, on the axis x; a point turns as much as its weights on them.
  defp bend(state, _by_point, _names, _at, degrees) when degrees == 0, do: state

  defp bend({bones, moved}, by_point, names, at, degrees) do
    turn = &turn_x(&1, Enum.find(bones, fn b -> b.name == at end).head, degrees * :math.pi() / 180)

    moved =
      for {p, i} <- Enum.with_index(moved) do
        t = by_point |> Map.get(i, []) |> Enum.filter(&(elem(&1, 0) in names)) |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        Vec.lerp(p, turn.(p), min(t, 1.0))
      end

    {for(b <- bones, do: if(b.name in names, do: %{b | head: turn.(b.head), tail: turn.(b.tail)}, else: b)), moved}
  end

  # The bones that move each point, with their weights.
  defp owners(weights) do
    for {bone, m} <- weights, {i, w} <- m, reduce: %{} do
      acc -> Map.update(acc, i, [{bone, w}], &[{bone, w} | &1])
    end
  end

  # A point after the change: the mean of its moves with each bone that
  # moves it, by the weights.
  defp place(p, ws, {frames, scales, heads, n, len, template}) do
    sum = ws |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    Enum.reduce(ws, {0.0, 0.0, 0.0}, fn {b, w}, acc ->
      Vec.add(acc, Vec.scale(move(b, p, frames, scales, heads, n, len, template), w / sum))
    end)
  end

  defp head_length(bones) do
    head = Enum.find(bones, &(&1.name == "head"))
    Vec.len(Vec.sub(head.tail, head.head))
  end

  # The new head of each bone: the end of its parent after the change.
  defp heads(bones, frames, scales, n, template) do
    len = head_length(bones)

    Enum.reduce(bones, %{}, fn b, acc ->
      h = if b.parent, do: move(b.parent, b.head, frames, scales, acc, n, len, template), else: b.head
      Map.put(acc, b.name, h)
    end)
  end

  @doc """
  The scale of each bone of a template (its bones, points and weights,
  as `apply/6`) after the numbers `n` (all the numbers: `numbers/0`
  gives the defaults): `{across in x, along, across in z}`. The length
  of each leg (the bones from the body to the foot, and the bones under
  them) is `leg_length`, then a little more or less, so that the lowest
  points of all the feet (the points that the foot moves most) move up
  or down by one height: the mean of their moves with `leg_length`. So
  the body does not tilt when the front legs and the hind legs are not
  the same length, or when the numbers of the body move the roots of
  the legs by different heights.
  """
  def scales(bones, points, weights, n, template) do
    scales = Map.new(bones, &{&1.name, bone_scale(&1.name, n)})
    by = Map.new(bones, &{&1.name, &1})
    frames = Map.new(bones, &{&1.name, frame(&1)})
    by_point = owners(weights)
    points = List.to_tuple(points)

    # Each leg: its bones (from the body down), and the points of its
    # foot (the points that the foot moves most).
    legs =
      for b <- bones, b.name =~ @foot do
        root = b.name |> Stream.iterate(&by[&1].parent) |> Enum.take_while(&(&1 && &1 =~ @leg)) |> List.last()
        {below(bones, root), for({i, w} <- weights[b.name], w >= 0.5, do: i)}
      end

    # The heights of the points with all the legs at the length k.
    heights = fn k ->
      s = for {leg, _} <- legs, bone <- leg, reduce: scales, do: (acc -> Map.update!(acc, bone, &put_elem(&1, 1, k)))
      state = {frames, s, heads(bones, frames, s, n, template), n, head_length(bones), template}
      fn i -> elem(place(elem(points, i), by_point[i], state), 2) end
    end

    # The height of a point after the change is linear in the length of
    # its leg (c + a × k), and the lowest point of a foot is the lowest of
    # these lines.
    {h0, h1} = {heights.(0.0), heights.(1.0)}

    feet =
      for {leg, ids} <- legs do
        rest = ids |> Enum.map(&elem(elem(points, &1), 2)) |> Enum.min()
        {leg, rest, Enum.map(ids, &{h0.(&1), h1.(&1) - h0.(&1)})}
      end

    k = n["leg_length"]
    low = fn lines, k -> lines |> Enum.map(fn {c, a} -> c + a * k end) |> Enum.min() end
    up = (feet |> Enum.map(fn {_, rest, lines} -> low.(lines, k) - rest end) |> Enum.sum()) / length(feet)

    # The length of a leg that moves its lowest point by `up`: the lines
    # go down as the leg grows (a < 0).
    for {leg, rest, lines} <- feet,
        k = lines |> Enum.map(fn {c, a} -> (rest + up - c) / a end) |> Enum.min(),
        bone <- leg,
        reduce: scales,
        do: (acc -> Map.update!(acc, bone, &put_elem(&1, 1, k)))
  end

  # A bone and all the bones under it.
  defp below(bones, root) do
    Enum.reduce(bones, [root], fn b, acc -> if b.parent in acc, do: [b.name | acc], else: acc end)
  end

  @doc """
  The frame of a bone (a map with `head` and `tail`): its head, and its
  axes x (to the side), y (along the bone) and z.
  """
  def frame(b) do
    y = Vec.norm(Vec.sub(b.tail, b.head))
    x = Vec.norm(Vec.sub({1.0, 0.0, 0.0}, Vec.scale(y, elem(y, 0))))
    {b.head, x, y, Vec.cross(x, y)}
  end

  defp local({o, x, y, z}, p) do
    d = Vec.sub(p, o)
    {Vec.dot(d, x), Vec.dot(d, y), Vec.dot(d, z)}
  end

  defp global({_, x, y, z}, o, {a, b, c}),
    do: o |> Vec.add(Vec.scale(x, a)) |> Vec.add(Vec.scale(y, b)) |> Vec.add(Vec.scale(z, c))

  # The scale of a bone after the numbers `n`: `{across in x, along,
  # across in z}`. The arms of a primate have their own numbers (the
  # fingers as the hand); its collarbones are the width of the body.
  defp bone_scale(name, n) do
    cond do
      name in ~w(pelvis spine_01 spine_02 spine_03) ->
        {n["body_width"], n["body_length"], n["body_depth"]}

      String.starts_with?(name, "clavicle_") ->
        {n["body_depth"], n["body_width"], n["body_depth"]}

      String.starts_with?(name, ~w(hand_ thumb_ index_ middle_ ring_ pinky_)) ->
        {n["arm_girth"], n["arm_length"], n["arm_girth"] * n["hand_width"]}

      String.starts_with?(name, ~w(upperarm_ lowerarm_)) ->
        {n["arm_girth"], n["arm_length"], n["arm_girth"]}

      name == "neck_01" ->
        {n["neck_girth"], n["neck_length"], n["neck_girth"]}

      name == "head" ->
        {n["head_size"], n["head_size"], n["head_size"]}

      String.starts_with?(name, "tail_") ->
        {n["tail_girth"], n["tail_length"], n["tail_girth"]}

      String.starts_with?(name, "ear_") ->
        {n["ear_size"] * n["ear_width"], n["ear_size"], n["ear_size"] * n["ear_width"]}

      true ->
        {n["leg_girth"], n["leg_length"], n["leg_girth"]}
    end
  end

  # A point as the bone `name` moves it: in the axes of the bone at rest,
  # scaled, and back from the new head of the bone. The front of the head
  # (the muzzle) has its own length and width.
  defp move(name, p, frames, scales, heads, n, len, template) do
    {gx, l, gz} = scales[name]
    {x, y, z} = local(frames[name], p)
    {x, y, z} = if name == "head", do: face({x, y, z}, n, len, template), else: {x, y, z}
    global(frames[name], heads[name], {x * gx, y * l, z * gz})
  end

  # The muzzle and the skull. The head of an animal on four legs is along
  # its bone (from the neck to the nose): the muzzle is the front part of
  # the bone. The head of a primate is up along its bone, and its face is
  # to the front (-z): the template gives its `brow` (a part of the bone),
  # the muzzle is the front of the face under the eyes, and the skull over
  # the brow goes down by `cranium`. The muzzle of a primate goes to the
  # front as a block: all its front by the same distance, so the nose and
  # the lips keep their depth and do not make a point.
  defp face({x, y, z}, n, len, template) do
    f0 = template["muzzle"] * len

    if template["brow"] == nil do
      r = smooth(f0 - 0.15 * len, f0 + 0.15 * len, y)
      w = 1 + (n["muzzle_width"] - 1) * r
      {x * w, y + (n["muzzle_length"] - 1) * max(0.0, y - f0), z * w}
    else
      brow = template["brow"] * len
      r = smooth(f0 - 0.15 * len, f0 + 0.075 * len, -z) * (1 - smooth(brow - 0.3 * len, brow - 0.175 * len, y))
      w = 1 + (n["muzzle_width"] - 1) * r
      y = if y > brow, do: brow + (y - brow) * n["cranium"], else: y
      {x * w, y, z - (n["muzzle_length"] - 1) * r * 0.3 * len}
    end
  end

  # A point turned by the angle t around the axis (a unit vector) through
  # the point o (Rodrigues).
  defp turn(p, o, axis, t) do
    v = Vec.sub(p, o)
    {c, s} = {:math.cos(t), :math.sin(t)}

    v
    |> Vec.scale(c)
    |> Vec.add(Vec.scale(Vec.cross(axis, v), s))
    |> Vec.add(Vec.scale(axis, Vec.dot(axis, v) * (1 - c)))
    |> Vec.add(o)
  end

  defp turn_x(p, o, t) do
    {_, y, z} = Vec.sub(p, o)
    Vec.add(o, {elem(p, 0) - elem(o, 0), y * :math.cos(t) - z * :math.sin(t), y * :math.sin(t) + z * :math.cos(t)})
  end

  # 0 below a, 1 above b, smooth between.
  defp smooth(a, b, v) do
    t = ((v - a) / (b - a)) |> max(0.0) |> min(1.0)
    t * t * (3 - 2 * t)
  end

  @doc """
  The regions of the coat at each point of the template (at rest,
  before the numbers): a region to a list of the part (0 to 1) of each
  point in it. `back` and `belly` are the top and the bottom of the
  body and the neck; `mane` the top of the neck (the crest, where a horse
  has its mane); `legs` the legs; `socks` the paws and the low part of
  the legs; `head` all the head; `face` the muzzle; `lids` the upper
  lids, over the points of `eyes`; `ears` (the bones of
  the ears); `tail` all the tail; `tail_tip` (the last bone of the
  tail).
  """
  def regions(bones, points, weights, eyes \\ []) do
    by = Map.new(bones, &{&1.name, &1})
    frames = Map.new(bones, &{&1.name, frame(&1)})
    head = by["head"]
    len = Vec.len(Vec.sub(head.tail, head.head))
    w = fn bone, i -> weights |> Map.get(bone, %{}) |> Map.get(i, 0.0) end
    sum = fn names, i -> names |> Enum.map(&w.(&1, i)) |> Enum.sum() end
    names = Enum.map(bones, & &1.name)

    legs =
      Enum.filter(
        names,
        &String.starts_with?(
          &1,
          ~w(front_ hind_ upperarm_ lowerarm_ hand_ thigh_ calf_ foot_ ball_ thumb_ index_ middle_ ring_ pinky_)
        )
      )

    feet = Enum.filter(legs, &(&1 =~ ~r/_foot_|^hand_|^foot_|^ball_|^thumb_|^index_|^middle_|^ring_|^pinky_/))
    lower = Enum.filter(legs, &(&1 =~ ~r/_lower_|^lowerarm_|^calf_/))
    trunk = Enum.filter(~w(pelvis spine_01 spine_02 spine_03 neck_01), &Map.has_key?(by, &1))
    tail = Enum.filter(names, &String.starts_with?(&1, "tail_"))
    tail_tip = List.last(tail)
    lids = lids(frames["head"], points, eyes)

    # The height of each point of the body over the bone that moves it
    # most, as a part of the range of the body there.
    zs =
      for {p, i} <- Enum.with_index(points),
          sum.(trunk, i) > 0.5,
          do: elem(local(frames[Enum.max_by(trunk, &w.(&1, i))], p), 2)

    {lo, hi} = Enum.min_max(zs)

    for {p, i} <- Enum.with_index(points), reduce: Map.new(@regions, &{&1, []}) do
      acc ->
        t = sum.(trunk, i)
        z = if t > 0, do: (elem(local(frames[Enum.max_by(trunk, &w.(&1, i))], p), 2) - lo) / (hi - lo), else: 0.5
        {_, hy, hz} = local(frames["head"], p)

        low =
          Enum.sum(
            for b <- lower,
                do: w.(b, i) * smooth(0.5, 0.9, elem(local(frames[b], p), 1) / Vec.len(Vec.sub(by[b].tail, by[b].head)))
          )

        parts = %{
          "back" => t * smooth(0.65, 0.85, z),
          "belly" => t * (1 - smooth(0.2, 0.4, z)),
          "mane" => w.("neck_01", i) * smooth(0.65, 0.85, z),
          "legs" => min(sum.(legs, i), 1.0),
          "socks" => min(sum.(feet, i) + low, 1.0),
          "head" => w.("head", i),
          "face" => w.("head", i) * face_part(Map.has_key?(by, "upperarm_l"), hy, hz, len),
          "lids" => w.("head", i) * lids.(p),
          "ears" => min(w.("ear_l", i) + w.("ear_r", i), 1.0),
          "tail" => min(sum.(tail, i), 1.0),
          "tail_tip" => w.(tail_tip, i)
        }

        Map.new(acc, fn {r, list} -> {r, [min(parts[r], 1.0) | list]} end)
    end
    |> Map.new(fn {r, list} -> {r, Enum.reverse(list)} end)
  end

  # The upper lids: over each eye (the points of `eyes` on its side of
  # the head), in front of its center, as wide as the eye.
  defp lids(_frame, _points, []), do: fn _ -> 0.0 end

  defp lids(frame, points, eyes) do
    eyes =
      for {_, e} <- Enum.group_by(eyes, &(elem(Enum.at(points, &1), 0) > 0)) do
        ps = Enum.map(e, &local(frame, Enum.at(points, &1)))
        c = Vec.scale(Enum.reduce(ps, &Vec.add/2), 1 / length(ps))
        {c, ps |> Enum.map(&Vec.len(Vec.sub(&1, c))) |> Enum.max()}
      end

    fn p ->
      q = local(frame, p)

      eyes
      |> Enum.map(fn {c, r} ->
        {dx, dy, dz} = Vec.sub(q, c)

        smooth(-0.2 * r, 0.3 * r, dy) * (1 - smooth(0.9 * r, 1.5 * r, dy)) * (1 - smooth(0.8 * r, 1.3 * r, abs(dx))) *
          smooth(-0.5 * r, 0.0, -dz)
      end)
      |> Enum.max()
    end
  end

  # The face: the front part of the bone of the head of an animal on four
  # legs, the front of the head of a primate under the brow (as `face/4`).
  defp face_part(false, y, _z, len), do: smooth(0.45 * len, 0.6 * len, y)
  defp face_part(true, y, z, len), do: smooth(0.35 * len, 0.5 * len, -z) * (1 - smooth(0.4 * len, 0.5 * len, y))

  @doc """
  The color of each point: the `base` color, and over it the color of
  each region of `coat` (a region to `[r, g, b]`) in the order of
  `regions/0`, as much as the point is in the region.
  """
  def colors(regions, base, coat) do
    rgb = fn c -> List.to_tuple(Enum.map(c, &(&1 / 1))) end
    blend(regions, rgb.(base), Map.new(coat, fn {r, c} -> {r, rgb.(c)} end), &Vec.lerp/3)
  end

  @doc """
  The length of the fur at each point (m): the `base` length, and over
  it the length of each region of `lengths` (a region to a length), as
  `colors/3`.
  """
  def fur(regions, base, lengths), do: blend(regions, base / 1, lengths, fn a, b, m -> a + (b - a) * m end)

  @doc """
  The direction of the fur at each point, at rest (a unit vector, or
  `{0, 0, 0}` for a point on no bone): the hair lies to the back on the
  body, the neck and the head (from the head to the root of each bone),
  and to the end of each bone on the legs, the arms, the ears and the
  tail. The mean of the bones of the point, by their weights. The skin
  (`World.Rig`) keeps the part of it along the skin.
  """
  def fur_dirs(bones, points, weights) do
    dirs =
      for b <- bones, into: %{} do
        d = Vec.norm(Vec.sub(b.tail, b.head))
        {b.name, if(b.name =~ ~r/^(pelvis|spine_|neck_|head$)/, do: Vec.scale(d, -1.0), else: d)}
      end

    by_point =
      for {b, m} <- weights, {i, w} <- m, reduce: %{} do
        acc -> Map.update(acc, i, Vec.scale(dirs[b], w), &Vec.add(&1, Vec.scale(dirs[b], w)))
      end

    for i <- 0..(length(points) - 1) do
      v = Map.get(by_point, i, {0.0, 0.0, 0.0})
      if Vec.len(v) > 1.0e-9, do: Vec.norm(v), else: {0.0, 0.0, 0.0}
    end
  end

  defp blend(regions, base, values, mix) do
    Enum.reduce(@regions, List.duplicate(base, length(regions["back"])), fn r, list ->
      case values[r] do
        nil -> list
        v -> Enum.zip_with(list, regions[r], &mix.(&1, v, &2))
      end
    end)
  end

  @doc """
  The horns on the head: two curved cones from the top of the skull, up
  and to the back, or out to the sides by `spread` (0 to 1), `length`
  long (m). `head` is the bone of the head
  after the change, `top` the highest points of the head (the roots of
  the horns are the highest point on each side). Gives `{points,
  triangles}` (points `{position, normal}`).
  """
  def horns(head, length, spread, top) do
    # The axes of the horns: to the side of the head, and level (the
    # head can point down).
    {o, x, _, _} = frame(head)
    z = {0.0, 0.0, 1.0}
    y = Vec.cross(z, x)
    n = 8
    steps = 8

    parts =
      for side <- [-1, 1] do
        root = Enum.max_by(Enum.filter(top, &(Vec.dot(Vec.sub(&1, o), x) * side > 0)), &elem(&1, 2))
        r0 = 0.12 * length

        rings =
          for s <- 0..steps do
            t = s / steps
            # Up, then to the back and a little to the side; with a spread,
            # out to the side and to the back, the tips in and up.
            c =
              root
              |> Vec.add(Vec.scale(z, length * ((0.75 - 0.6 * spread) * t + (0.35 * spread - 0.15) * t * t)))
              |> Vec.add(Vec.scale(y, -length * (0.6 + 0.3 * spread) * t * t))
              |> Vec.add(Vec.scale(x, side * length * ((0.15 + 0.7 * spread) * t - 0.25 * spread * t * t)))

            r = r0 * :math.pow(1 - t, 0.8) + 0.002

            for j <- 0..(n - 1) do
              a = 2 * :math.pi() * j / n
              d = Vec.add(Vec.scale(x, :math.cos(a)), Vec.scale(y, :math.sin(a)))
              {Vec.add(c, Vec.scale(d, r)), d}
            end
          end

        k = fn i, j -> i * n + rem(j, n) end

        tris =
          for i <- 0..(steps - 1),
              j <- 0..(n - 1),
              t <- [[k.(i, j), k.(i + 1, j + 1), k.(i + 1, j)], [k.(i, j), k.(i, j + 1), k.(i + 1, j + 1)]],
              do: t

        {List.flatten(rings), tris}
      end

    Enum.reduce(parts, {[], []}, fn {ps, ts}, {all, tris} ->
      {all ++ ps, tris ++ Enum.map(ts, fn t -> Enum.map(t, &(&1 + length(all))) end)}
    end)
  end
end
