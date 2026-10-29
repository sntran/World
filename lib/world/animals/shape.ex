defmodule World.Animals.Shape do
  @moduledoc """
  The shape of a four-legged animal from numbers: one template mesh (a
  dog), and a species is its numbers. So a new species needs no mesh.

  Each number changes the bones at rest and the skin around them. A
  bone has a scale along it (its length) and across it (its girth):
  each point of the skin moves with the bones that move it, by its
  weights, so the skin stays smooth at the joints. A bone under another
  bone moves with the end of its parent. Some numbers change one part:
  the muzzle (the front of the head), the ears (turned up and pointed),
  the tail (turned down), the paws (hooves). After the change, the
  lowest point of the paws is on the ground. A body much deeper than
  the legs are long can go below the ground: the presets do not.

  | Number | Range | What it changes |
  |---|---|---|
  | `body_length` | 0.6 to 1.8 | The length of the back (the bones `pelvis` and `spine_01`). |
  | `body_width`, `body_depth` | 0.6 to 1.8 | The width and the depth of the body. |
  | `leg_length` | 0.5 to 1.6 | The length of the legs. |
  | `leg_girth` | 0.5 to 1.8 | The thickness of the legs. |
  | `neck_length`, `neck_girth` | 0.4 to 1.8 | The neck. |
  | `head_size` | 0.6 to 1.6 | All the head. |
  | `muzzle_length` | 0.3 to 1.8 | The front of the head, from the eyes to the nose. |
  | `muzzle_width` | 0.6 to 1.8 | The width and the depth of the front of the head. |
  | `ear_size` | 0.5 to 2.0 | The ears. |
  | `ear_up` | 0 to 1 | 0: the ears fold down to the sides (the template); 1: up. |
  | `ear_point` | 0 to 1 | 1: the ears narrow to a point. |
  | `tail_length` | 0.1 to 2.0 | The tail. |
  | `tail_girth` | 0.4 to 3.0 | The thickness of the tail. |
  | `tail_down` | -30 to 150 | Degrees: more turns the tail down (0: up as in the template). |
  | `hooves` | 0 to 1 | 1: each paw is a narrow, short hoof. |
  | `horns` | 0 to 1.5 | The length of the horns, in lengths of the head (0: no horns). |

  The coat: a color for each region of the skin, with soft edges between
  the regions (`regions/3`, `colors/3`).
  """
  alias World.Vec

  @numbers %{
    "body_length" => {0.6, 1.8, 1.0},
    "body_width" => {0.6, 1.8, 1.0},
    "body_depth" => {0.6, 1.8, 1.0},
    "leg_length" => {0.5, 1.6, 1.0},
    "leg_girth" => {0.5, 1.8, 1.0},
    "neck_length" => {0.4, 1.8, 1.0},
    "neck_girth" => {0.4, 1.8, 1.0},
    "head_size" => {0.6, 1.6, 1.0},
    "muzzle_length" => {0.3, 1.8, 1.0},
    "muzzle_width" => {0.6, 1.8, 1.0},
    "ear_size" => {0.5, 2.0, 1.0},
    "ear_up" => {0.0, 1.0, 0.0},
    "ear_point" => {0.0, 1.0, 0.0},
    "tail_length" => {0.1, 2.0, 1.0},
    "tail_girth" => {0.4, 3.0, 1.0},
    "tail_down" => {-30.0, 150.0, 0.0},
    "hooves" => {0.0, 1.0, 0.0},
    "horns" => {0.0, 1.5, 0.0}
  }

  @regions ~w(back belly legs socks head face ears tail_tip hooves)

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
  starts) and `ears` (`x` and `z`: the ears are the points of the head
  farther than `x` to the side and higher than `z` above the head; `y`:
  the middle of the root of an ear along the head; in lengths of the
  head). Gives `{bones, points}`.
  """
  def apply(bones, points, weights, n, template) do
    n = Map.merge(Map.new(@numbers, fn {k, {_, _, d}} -> {k, d} end), n)
    by = Map.new(bones, &{&1.name, &1})
    frames = Map.new(bones, &{&1.name, frame(&1)})
    scales = Map.new(bones, &{&1.name, scale(&1.name, n)})
    head = by["head"]
    len = Vec.len(Vec.sub(head.tail, head.head))

    # The ears turn before the bones move them.
    points = ears(points, frames["head"], len, n, template["ears"])

    # The new head of each bone: the end of its parent after the change.
    heads =
      Enum.reduce(bones, %{}, fn b, acc ->
        h = if b.parent, do: move(b.parent, b.head, frames, scales, acc, n, len, template), else: b.head
        Map.put(acc, b.name, h)
      end)

    tails = Map.new(bones, &{&1.name, move(&1.name, &1.tail, frames, scales, heads, n, len, template)})

    by_point =
      for {bone, m} <- weights,
          {i, w} <- m,
          reduce: %{},
          do: (acc -> Map.update(acc, i, [{bone, w}], &[{bone, w} | &1]))

    moved =
      points
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        ws = Map.get(by_point, i, [{"pelvis", 1.0}])
        sum = ws |> Enum.map(&elem(&1, 1)) |> Enum.sum()

        Enum.reduce(ws, {0.0, 0.0, 0.0}, fn {b, w}, acc ->
          Vec.add(acc, Vec.scale(move(b, p, frames, scales, heads, n, len, template), w / sum))
        end)
      end)

    # The tail turns down around the root of the tail.
    tail_bones = for b <- bones, String.starts_with?(b.name, "tail_"), do: b.name
    pivot = heads["tail_01"]
    turn = &turn_x(&1, pivot, n["tail_down"] * :math.pi() / 180)

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

    # The paws on the ground: the lowest point of the feet.
    feet = for b <- bones, String.contains?(b.name, "_foot_"), {i, w} <- Map.get(weights, b.name, %{}), w >= 0.5, do: i
    ground = feet |> Enum.map(&elem(Enum.at(moved, &1), 2)) |> Enum.min()
    down = &Vec.sub(&1, {0.0, 0.0, ground})
    {Enum.map(bones, &%{&1 | head: down.(&1.head), tail: down.(&1.tail)}), Enum.map(moved, down)}
  end

  # The frame of a bone: its head, and its axes x (to the side), y (along
  # the bone) and z.
  defp frame(b) do
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

  # The scale of a bone: {across in x, along, across in z}.
  defp scale(name, n) do
    cond do
      name in ~w(pelvis spine_01) ->
        {n["body_width"], n["body_length"], n["body_depth"]}

      name == "neck_01" ->
        {n["neck_girth"], n["neck_length"], n["neck_girth"]}

      name == "head" ->
        {n["head_size"], n["head_size"], n["head_size"]}

      String.starts_with?(name, "tail_") ->
        {n["tail_girth"], n["tail_length"], n["tail_girth"]}

      String.contains?(name, "_foot_") ->
        {n["leg_girth"] * (1 - 0.35 * n["hooves"]), 1 - 0.45 * n["hooves"], n["leg_girth"]}

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

    {x, y, z} =
      if name == "head" do
        y0 = template["muzzle"] * len
        r = smooth(y0 - 0.15 * len, y0 + 0.15 * len, y)
        w = 1 + (n["muzzle_width"] - 1) * r
        {x * w, y + (n["muzzle_length"] - 1) * max(0.0, y - y0), z * w}
      else
        {x, y, z}
      end

    global(frames[name], heads[name], {x * gx, y * l, z * gz})
  end

  # The ears: turned up around their root (on the axis along the head) by
  # `ear_up`, larger by `ear_size`, and narrower to the tip by
  # `ear_point`. A point near the root moves less.
  defp ears(points, head, len, n, rule) do
    {x0, z0} = {rule["x"] * len, rule["z"] * len}

    Enum.map(points, fn p ->
      {x, y, z} = local(head, p)
      m = smooth(x0, x0 + 0.12 * len, abs(x)) * smooth(z0 - 0.1 * len, z0, z)

      if m == 0 do
        p
      else
        side = if x < 0, do: -1, else: 1
        {a, b, c} = {abs(x) - x0, y, z - z0}
        # Along the ear (a), its width (b, around the middle of the root),
        # and its thickness (c).
        k = n["ear_size"]
        {a, c} = {a * k, c * k}
        b = rule["y"] * len + (b - rule["y"] * len) * k * (1 - n["ear_point"] * min(a / (0.5 * len), 1.0))
        t = n["ear_up"] * 80 * :math.pi() / 180
        {a, c} = {a * :math.cos(t) - c * :math.sin(t), a * :math.sin(t) + c * :math.cos(t)}
        Vec.lerp(p, global(head, elem(head, 0), {side * (x0 + a), b, z0 + c}), m)
      end
    end)
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
  body and the neck; `legs` the legs; `socks` the paws and the low part
  of the legs; `head` all the head; `face` the muzzle; `ears`; `tail_tip`; `hooves` the
  paws when the animal has hooves.
  """
  def regions(bones, points, weights, template) do
    ears = template["ears"]
    by = Map.new(bones, &{&1.name, &1})
    frames = Map.new(bones, &{&1.name, frame(&1)})
    head = by["head"]
    len = Vec.len(Vec.sub(head.tail, head.head))
    w = fn bone, i -> weights |> Map.get(bone, %{}) |> Map.get(i, 0.0) end
    sum = fn names, i -> names |> Enum.map(&w.(&1, i)) |> Enum.sum() end
    names = Enum.map(bones, & &1.name)
    legs = Enum.filter(names, &(String.starts_with?(&1, "front_") or String.starts_with?(&1, "hind_")))
    feet = Enum.filter(legs, &String.contains?(&1, "_foot_"))
    lower = Enum.filter(legs, &String.contains?(&1, "_lower_"))
    trunk = ~w(pelvis spine_01 neck_01)

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
        {hx, hy, hz} = local(frames["head"], p)

        low =
          Enum.sum(
            for b <- lower,
                do: w.(b, i) * smooth(0.5, 0.9, elem(local(frames[b], p), 1) / Vec.len(Vec.sub(by[b].tail, by[b].head)))
          )

        parts = %{
          "back" => t * smooth(0.65, 0.85, z),
          "belly" => t * (1 - smooth(0.2, 0.4, z)),
          "legs" => min(sum.(legs, i), 1.0),
          "socks" => min(sum.(feet, i) + low, 1.0),
          "head" => w.("head", i),
          "face" => w.("head", i) * smooth(0.45 * len, 0.6 * len, hy),
          "ears" =>
            w.("head", i) * smooth(ears["x"] * len, (ears["x"] + 0.06) * len, abs(hx)) *
              smooth((ears["z"] - 0.1) * len, ears["z"] * len, hz),
          "tail_tip" => w.("tail_04", i),
          "hooves" => min(sum.(feet, i), 1.0)
        }

        Map.new(acc, fn {r, list} -> {r, [parts[r] | list]} end)
    end
    |> Map.new(fn {r, list} -> {r, Enum.reverse(list)} end)
  end

  @doc """
  The color of each point: the `base` color, and over it the color of
  each region of `coat` (a region to `[r, g, b]`) in the order of
  `regions/0`, as much as the point is in the region.
  """
  def colors(regions, base, coat) do
    n = length(regions["back"])

    Enum.reduce(@regions, List.duplicate(List.to_tuple(Enum.map(base, &(&1 / 1))), n), fn r, colors ->
      case coat[r] do
        nil -> colors
        c -> Enum.zip_with(colors, regions[r], fn col, m -> Vec.lerp(col, List.to_tuple(Enum.map(c, &(&1 / 1))), m) end)
      end
    end)
  end

  @doc """
  The horns on the head: two curved cones from the top of the skull, up
  and to the back, `length` long (m). `head` is the bone of the head
  after the change, `top` the highest points of the head (the roots of
  the horns are the highest point on each side). Gives `{points,
  triangles}` (points `{position, normal}`).
  """
  def horns(head, length, top) do
    {o, x, y, z} = frame(head)
    n = 8
    steps = 8

    parts =
      for side <- [-1, 1] do
        root = Enum.max_by(Enum.filter(top, &(Vec.dot(Vec.sub(&1, o), x) * side > 0)), &elem(&1, 2))
        r0 = 0.12 * length

        rings =
          for s <- 0..steps do
            t = s / steps
            # Up, then to the back and a little to the side.
            c =
              root
              |> Vec.add(Vec.scale(z, length * (0.75 * t - 0.15 * t * t)))
              |> Vec.add(Vec.scale(y, -length * 0.6 * t * t))
              |> Vec.add(Vec.scale(x, side * length * 0.15 * t))

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
