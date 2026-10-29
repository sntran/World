# Make the mesh of the template of birds (priv/animals/meshes/) from the
# bones of World: a smooth skin around the bones (World.Blob), plates
# for the wings, the tail, the comb and the wattles, a beak, legs and
# toes, and two eyes. The same format as scripts/gltf_figure.exs.
#
#     mix run scripts/bird_template.exs OUT.json
#
# - The bird has the body of a hen, about 0.45 m high at the top of the
#   comb: a body 0.3 m long, a neck up to the head, a short beak. The
#   numbers of a species change it (a duck: a longer, wider beak, shorter
#   legs).
# - The bones: pelvis (the root, the back of the body), spine_01 (the
#   breast), neck_01, head, beak, tail_01; for each side the wing (upperarm,
#   lowerarm, hand: folded along the body, to the back) and the leg
#   (thigh in the body, calf: the drumstick, foot: the bare shank, ball:
#   the toes).
# - The body, the neck and the head, the tail, each wing and each leg are
#   groups of the smooth skin, with a blend of 2 cm between them. The shanks are a
#   skin of their own (the material skin), as the toes.
# - The wings are flat bodies on the sides of the body, in groups of
#   their own (folded: the wing opens with its bones). The plates: the tail
#   is a fan of feathers, up and to the back; the comb is on the head, the
#   wattles under the beak.
alias World.{Blob, Frame, Vec}

[output] = System.argv()

bone = fn name, parent, head, tail, r0, r1, group ->
  dir = Vec.norm(Vec.sub(tail, head))
  up = if abs(elem(dir, 2)) > 0.9, do: {0.0, 1.0, 0.0}, else: {0.0, 0.0, 1.0}
  z = Vec.norm(Vec.sub(up, Vec.scale(dir, Vec.dot(up, dir))))
  %{name: name, parent: parent, head: head, tail: tail, radius: {r0, r1}, group: group, frame: Frame.new(head, z, dir)}
end

mirror = fn {x, y, z} -> {-x, y, z} end

side_bones = fn s, m ->
  [
    bone.("upperarm_#{s}", "spine_01", m.({0.07, 0.07, 0.25}), m.({0.08, 0.0, 0.24}), {0.014, 0.035}, {0.015, 0.042}, "wing_#{s}"),
    bone.("lowerarm_#{s}", "upperarm_#{s}", m.({0.08, 0.0, 0.24}), m.({0.08, -0.07, 0.235}), {0.015, 0.042}, {0.012, 0.035}, "wing_#{s}"),
    bone.("hand_#{s}", "lowerarm_#{s}", m.({0.08, -0.07, 0.235}), m.({0.07, -0.15, 0.245}), {0.012, 0.035}, {0.005, 0.012}, "wing_#{s}"),
    bone.("thigh_#{s}", "pelvis", m.({0.04, -0.03, 0.2}), m.({0.045, 0.02, 0.15}), {0.035, 0.035}, {0.03, 0.03}, "leg_#{s}"),
    bone.("calf_#{s}", "thigh_#{s}", m.({0.045, 0.02, 0.15}), m.({0.045, -0.01, 0.085}), {0.028, 0.03}, {0.012, 0.012}, "leg_#{s}"),
    bone.("foot_#{s}", "calf_#{s}", m.({0.045, -0.01, 0.085}), m.({0.045, 0.005, 0.008}), {0.007, 0.007}, {0.007, 0.007}, "shank_#{s}"),
    bone.("ball_#{s}", "foot_#{s}", m.({0.045, 0.005, 0.008}), m.({0.045, 0.06, 0.006}), {0.005, 0.005}, {0.004, 0.004}, nil)
  ]
end

bones =
  [
    bone.("pelvis", nil, {0.0, -0.12, 0.23}, {0.0, 0.0, 0.22}, {0.07, 0.075}, {0.08, 0.09}, "body"),
    bone.("spine_01", "pelvis", {0.0, 0.0, 0.22}, {0.0, 0.1, 0.26}, {0.08, 0.09}, {0.055, 0.06}, "body"),
    bone.("neck_01", "spine_01", {0.0, 0.1, 0.28}, {0.0, 0.14, 0.37}, {0.04, 0.045}, {0.03, 0.032}, "head"),
    bone.("head", "neck_01", {0.0, 0.14, 0.37}, {0.0, 0.19, 0.372}, {0.03, 0.032}, {0.015, 0.017}, "head"),
    bone.("beak", "head", {0.0, 0.19, 0.372}, {0.0, 0.228, 0.362}, {0.0, 0.0}, {0.0, 0.0}, nil),
    bone.("tail_01", "pelvis", {0.0, -0.12, 0.25}, {0.0, -0.17, 0.33}, {0.04, 0.04}, {0.02, 0.02}, "tail")
  ] ++ side_bones.("l", & &1) ++ side_bones.("r", mirror)

index = bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
by = Map.new(bones, &{&1.name, &1})
indexed = fn names -> for n <- names, do: Map.put(by[n], :index, index[n]) end

# The feathered skin, and the bare shanks.
skin =
  ~w(pelvis spine_01 neck_01 head tail_01 thigh_l calf_l thigh_r calf_r upperarm_l lowerarm_l hand_l upperarm_r lowerarm_r hand_r)
  |> indexed.()
  |> Blob.mesh(0.014, 0.02)
shanks = Blob.mesh(indexed.(~w(foot_l foot_r)), 0.004, 0.004)

# A plate: an outline in its plane, as a fan from its first point, `t`
# thick; `place` gives the point and the normal of a corner.
plate = fn outline, t, place ->
  n = length(outline)

  layer = fn side ->
    for {u, v} <- outline do
      {p, normal} = place.(u, v)
      Vec.add(p, Vec.scale(normal, side * t / 2))
    end
  end

  tris =
    for(i <- 1..(n - 2), do: [0, i, i + 1]) ++
      for(i <- 1..(n - 2), do: [n, n + i + 1, n + i]) ++
      for i <- 0..(n - 1), j = rem(i + 1, n), t <- [[i, n + i, n + j], [i, n + j, j]], do: t

  {layer.(1.0) ++ layer.(-1.0), tris}
end

# A plate in a plane x = constant (u along y, v along z).
side_plate = fn outline, x, t -> plate.(outline, t, fn u, v -> {{x, u, v}, {1.0, 0.0, 0.0}} end) end

# A tube from a to b, radius r (a toe), or a cone to a point (the beak).
tube = fn a, b, r0, r1 ->
  dir = Vec.norm(Vec.sub(b, a))
  side = Vec.norm(Vec.cross(dir, {0.0, 0.0, 1.0}))
  up = Vec.cross(side, dir)
  n = 8

  ring = fn c, r ->
    for j <- 0..(n - 1) do
      a = 2 * :math.pi() * j / n
      Vec.add(c, Vec.add(Vec.scale(side, r * :math.cos(a)), Vec.scale(up, r * :math.sin(a))))
    end
  end

  points = ring.(a, r0) ++ ring.(b, max(r1, 1.0e-4)) ++ [Vec.add(b, Vec.scale(dir, r1)), Vec.sub(a, Vec.scale(dir, r0))]
  k = fn i, j -> i * n + rem(j, n) end

  tris =
    for(j <- 0..(n - 1), t <- [[k.(0, j), k.(0, j + 1), k.(1, j + 1)], [k.(0, j), k.(1, j + 1), k.(1, j)]], do: t) ++
      for(j <- 0..(n - 1), do: [k.(1, j), k.(1, j + 1), 2 * n]) ++ for(j <- 0..(n - 1), do: [k.(0, j + 1), k.(0, j), 2 * n + 1])

  {points, tris}
end

# The beak: a wedge from its root to a blunt tip, wider than deep: rings
# of half sizes (x, z) from the root to the tip.
beak = fn a, b ->
  dir = Vec.norm(Vec.sub(b, a))
  side = {1.0, 0.0, 0.0}
  up = Vec.cross(side, dir)
  n = 10
  sizes = [{0.0, {0.013, 0.011}}, {0.6, {0.009, 0.006}}, {1.0, {0.005, 0.003}}]

  rings =
    for {t, {rx, rz}} <- sizes, j <- 0..(n - 1) do
      c = Vec.lerp(a, b, t)
      w = 2 * :math.pi() * j / n
      Vec.add(c, Vec.add(Vec.scale(side, rx * :math.cos(w)), Vec.scale(up, rz * :math.sin(w))))
    end

  k = fn i, j -> i * n + rem(j, n) end
  tip = Vec.add(b, Vec.scale(dir, 0.003))

  tris =
    for(i <- 0..1, j <- 0..(n - 1), t <- [[k.(i, j), k.(i, j + 1), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i + 1, j)]], do: t) ++
      for(j <- 0..(n - 1), do: [k.(2, j), k.(2, j + 1), 3 * n])

  {rings ++ [tip], tris}
end

# The eyes: a sphere on each side of the head.
sphere = fn c, r ->
  {rings, segs} = {6, 10}

  points =
    for i <- 0..rings, j <- 0..(segs - 1) do
      {a, b} = {:math.pi() * i / rings, 2 * :math.pi() * j / segs}
      Vec.add(c, Vec.scale({:math.sin(a) * :math.cos(b), :math.sin(a) * :math.sin(b), :math.cos(a)}, r))
    end

  k = fn i, j -> i * segs + rem(j, segs) end
  {points, for(i <- 0..(rings - 1), j <- 0..(segs - 1), t <- [[k.(i, j), k.(i + 1, j), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i, j + 1)]], do: t)}
end

toes = fn s, m ->
  base = m.({0.045, 0.005, 0.005})

  [
    {"ball_#{s}", tube.(base, m.({0.045, 0.065, 0.005}), 0.005, 0.003)},
    {"ball_#{s}", tube.(base, m.({0.075, 0.05, 0.005}), 0.005, 0.003)},
    {"ball_#{s}", tube.(base, m.({0.015, 0.05, 0.005}), 0.005, 0.003)},
    {"foot_#{s}", tube.(base, m.({0.045, -0.03, 0.005}), 0.005, 0.003)}
  ]
end

# The parts: {material, bone or nil (the weights of the skin), {points, triangles}}.
{skin_points, skin_tris} = skin
{shank_points, shank_tris} = shanks

parts =
  [{0, nil, {skin_points, skin_tris}}, {1, nil, {shank_points, shank_tris}}] ++
    [
      {0, "tail_01", side_plate.([{-0.1, 0.24}, {-0.12, 0.32}, {-0.16, 0.4}, {-0.2, 0.41}, {-0.23, 0.37}, {-0.21, 0.29}, {-0.15, 0.23}], 0.0, 0.01)},
      {2, "beak", beak.({0.0, 0.19, 0.372}, {0.0, 0.228, 0.362})},
      {3, "head", side_plate.([{0.13, 0.395}, {0.14, 0.425}, {0.155, 0.415}, {0.165, 0.435}, {0.18, 0.42}, {0.195, 0.43}, {0.2, 0.405}, {0.19, 0.39}], 0.0, 0.004)},
      {3, "head", side_plate.([{0.18, 0.355}, {0.2, 0.355}, {0.2, 0.33}, {0.185, 0.325}], 0.0, 0.004)}
    ] ++
    for({b, geo} <- toes.("l", & &1) ++ toes.("r", mirror), do: {1, b, geo}) ++
    for x <- [0.024, -0.024], do: {4, "head", sphere.({x, 0.168, 0.382}, 0.008)}

{points, faces, materials, weights, _} =
  Enum.reduce(parts, {[], [], [], %{}, 0}, fn {m, b, {ps, tris}}, {points, faces, mats, weights, n} ->
    {ps, ws} =
      case b do
        nil ->
          {Enum.map(ps, &elem(&1, 0)),
           Enum.map(ps, fn {_, _, {js, xs}} ->
             for {j, x} <- Enum.zip(Tuple.to_list(js), Tuple.to_list(xs)), x > 0, do: {Enum.at(bones, j).name, x}
           end)}

        b ->
          {ps, List.duplicate([{b, 1.0}], length(ps))}
      end

    weights =
      ws
      |> Enum.with_index(n)
      |> Enum.reduce(weights, fn {list, i}, acc ->
        Enum.reduce(list, acc, fn {b, x}, acc -> Map.update(acc, b, [[i, x]], &[[i, x] | &1]) end)
      end)

    {points ++ ps, faces ++ Enum.map(tris, fn t -> Enum.map(t, &(&1 + n)) end), mats ++ List.duplicate(m, length(tris)), weights,
     n + length(ps)}
  end)

low = points |> Enum.map(&elem(&1, 2)) |> Enum.min()
round = fn {x, y, z} -> Enum.map([x, y, z - low], &Float.round(&1 / 1, 5)) end

data = %{
  "source" => "World: a smooth skin around the bones of World (World.Blob), plates, a beak, toes and eyes (scripts/bird_template.exs).",
  "license" => "AGPL-3.0, as World",
  "points" => Enum.map(points, round),
  "faces" => faces,
  "materials" => [
    %{"name" => "feathers", "color" => [150, 100, 60]},
    %{"name" => "legs", "color" => [200, 170, 80]},
    %{"name" => "beak", "color" => [210, 180, 90]},
    %{"name" => "comb", "color" => [190, 40, 40]},
    %{"name" => "eye", "color" => [30, 20, 10]}
  ],
  "face_materials" => materials,
  "bones" => for(b <- bones, do: %{"name" => b.name, "parent" => b.parent, "head" => round.(b.head)}),
  "weights" =>
    Map.new(weights, fn {b, l} ->
      {b, for([i, w] <- Enum.sort(l), w = Float.round(w / 1, 5), w > 0, do: [i, w])}
    end)
}

File.write!(output, JSON.encode!(data))
IO.puts("#{length(points)} points, #{length(faces)} faces, #{length(bones)} bones")
