# Make the mesh of the template of fish (priv/animals/meshes/) from the
# bones of World: a smooth skin around a chain of bones (World.Blob),
# fins as thin plates, and two eyes. The same format as
# scripts/gltf_figure.exs.
#
#     mix run scripts/fish_template.exs OUT.json
#
# - The fish is 1 m long from the snout to the end of the tail fin, with
#   the body of a carp: the deepest part of the body 0.27 of the length,
#   its width 0.45 of its depth, a head of 0.22 of the length, and a thin
#   stalk in front of the tail fin. The numbers of a species change it.
# - The bones, from the front to the back: head, spine_01, pelvis (the
#   root), tail_01 to tail_04 (tail_04 holds the tail fin).
# - The fins: a dorsal fin, a forked tail fin, an anal fin, and a pair of
#   pectoral fins and of pelvic fins. A fin is a plate 4 mm thick; each
#   point follows the bones near it along the body.
# - The eyes: a sphere on each side of the head.
alias World.{Blob, Frame, Vec}

[output] = System.argv()

# The axis of the body is at z0; y is to the front, the snout at y = 0.5.
z0 = 0.2

bone = fn name, parent, y0, y1, r0, r1 ->
  head = {0.0, y0, z0}
  tail = {0.0, y1, z0}
  dir = Vec.norm(Vec.sub(tail, head))
  # One group: the body has no bumps at the joints.
  %{name: name, parent: parent, head: head, tail: tail, radius: {r0, r1}, group: "body", frame: Frame.new(head, {0.0, 0.0, 1.0}, dir)}
end

# The half width and the half depth of the body at each bone end.
bones = [
  bone.("pelvis", nil, -0.04, 0.12, {0.06, 0.135}, {0.062, 0.135}),
  bone.("spine_01", "pelvis", 0.12, 0.28, {0.062, 0.135}, {0.056, 0.115}),
  bone.("head", "spine_01", 0.28, 0.47, {0.056, 0.115}, {0.03, 0.045}),
  bone.("tail_01", "pelvis", -0.04, -0.17, {0.06, 0.135}, {0.045, 0.1}),
  bone.("tail_02", "tail_01", -0.17, -0.28, {0.045, 0.1}, {0.02, 0.042}),
  bone.("tail_03", "tail_02", -0.28, -0.34, {0.02, 0.042}, {0.01, 0.028}),
  bone.("tail_04", "tail_03", -0.34, -0.5, {0.006, 0.01}, {0.002, 0.004})
]

index = bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
body = Enum.reject(bones, &(&1.name == "tail_04"))
{skin, skin_tris} = Blob.mesh(Enum.map(body, &Map.put(&1, :index, index[&1.name])), 0.02, 0.03)

# The weights of a point of a fin: the two bones of the chain nearest to
# it along the body, by its place between their middles.
chain = ~w(head spine_01 pelvis tail_01 tail_02 tail_03 tail_04)
mids = for n <- chain, b = Enum.find(bones, &(&1.name == n)), do: {n, (elem(b.head, 1) + elem(b.tail, 1)) / 2}

along = fn {_, y, _} ->
  case Enum.chunk_every(mids, 2, 1, :discard) |> Enum.find(fn [{_, a}, {_, b}] -> y <= a and y >= b end) do
    [{n0, a}, {n1, b}] -> Enum.filter([{n0, (y - b) / (a - b)}, {n1, (a - y) / (a - b)}], &(elem(&1, 1) > 0))
    nil -> [{if(y > 0, do: "head", else: "tail_04"), 1.0}]
  end
end

# A fin: an outline in its plane (u along the body, v out of the body),
# from its base on the body, as a fan from its first point, 4 mm thick.
fin = fn outline, place ->
  t = 0.002
  n = length(outline)

  layer = fn side ->
    for {u, v} <- outline do
      {p, normal} = place.(u, v)
      {Vec.add(p, Vec.scale(normal, side * t)), Vec.scale(normal, side)}
    end
  end

  points = layer.(1.0) ++ layer.(-1.0)

  tris =
    for(i <- 1..(n - 2), do: [0, i, i + 1]) ++
      for(i <- 1..(n - 2), do: [n, n + i + 1, n + i]) ++
      for i <- 0..(n - 1), j = rem(i + 1, n), t <- [[i, n + i, n + j], [i, n + j, j]], do: t

  {points, tris}
end

top = fn y -> z0 + 0.13 * (1 - :math.pow(y / 0.5, 2)) end
in_plane = fn u, v -> {{0.0, u, v}, {1.0, 0.0, 0.0}} end

fins = [
  # The dorsal fin: high at its front, then long and low, over the last
  # two thirds of the body.
  fin.([{0.13, 0.0}, {0.1, 0.1}, {0.05, 0.065}, {-0.18, 0.035}, {-0.24, 0.0}], fn u, v ->
    {p, n} = in_plane.(u, v)
    {Vec.add(p, {0.0, 0.0, top.(u) - 0.01}), n}
  end),
  # The tail fin: forked, on the stalk of the tail.
  fin.([{-0.32, 0.0}, {-0.33, 0.03}, {-0.5, 0.17}, {-0.45, 0.07}, {-0.42, 0.0}, {-0.45, -0.07}, {-0.5, -0.17}, {-0.33, -0.03}], fn u, v ->
    {p, n} = in_plane.(u, v)
    {Vec.add(p, {0.0, 0.0, z0}), n}
  end),
  # The anal fin.
  fin.([{-0.13, 0.0}, {-0.16, -0.07}, {-0.22, -0.06}, {-0.23, 0.0}], fn u, v ->
    {p, n} = in_plane.(u, v)
    {Vec.add(p, {0.0, 0.0, z0 - 0.08}), n}
  end)
] ++
  for side <- [-1.0, 1.0],
      {y, z, len} <- [{0.26, z0 - 0.08, 0.13}, {0.02, z0 - 0.12, 0.1}] do
    # A pectoral fin (behind the head) and a pelvic fin (under the belly),
    # to the back and out, down a little.
    out = Vec.norm({side * 0.6, -1.0, -0.35})
    normal = Vec.norm(Vec.cross(out, {0.0, 1.0, 0.0}))

    fin.([{0.0, 0.0}, {0.0, 0.03}, {len, 0.035}, {len * 0.8, -0.01}], fn u, v ->
      {Vec.add({side * 0.045, y, z}, Vec.add(Vec.scale(out, u), {0.0, v, 0.0})), normal}
    end)
  end

# The eyes: a sphere on each side of the head, on the skin.
eye = fn side ->
  c = {side * 0.035, 0.4, z0 + 0.025}
  r = 0.018
  rings = 8
  segs = 12

  points =
    for i <- 0..rings, j <- 0..(segs - 1) do
      {a, b} = {:math.pi() * i / rings, 2 * :math.pi() * j / segs}
      n = {:math.sin(a) * :math.cos(b), :math.sin(a) * :math.sin(b), :math.cos(a)}
      {Vec.add(c, Vec.scale(n, r)), n}
    end

  k = fn i, j -> i * segs + rem(j, segs) end
  tris = for i <- 0..(rings - 1), j <- 0..(segs - 1), t <- [[k.(i, j), k.(i + 1, j), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i, j + 1)]], do: t
  {points, tris}
end

# All the parts in one mesh: the points, the faces with their material,
# the weights.
parts =
  [{0, Enum.map(skin, fn {p, _, w} -> {p, w} end), skin_tris}] ++
    for({points, tris} <- fins, do: {1, Enum.map(points, fn {p, _} -> {p, along.(p)} end), tris}) ++
    for side <- [-1.0, 1.0], {points, tris} = eye.(side), do: {2, Enum.map(points, fn {p, _} -> {p, [{"head", 1.0}]} end), tris}

{points, faces, materials, weights, _} =
  Enum.reduce(parts, {[], [], [], %{}, 0}, fn {m, ps, tris}, {points, faces, mats, weights, n} ->
    weights =
      ps
      |> Enum.with_index(n)
      |> Enum.reduce(weights, fn {{_, w}, i}, acc ->
        list =
          case w do
            {joints, ws} -> for {j, x} <- Enum.zip(Tuple.to_list(joints), Tuple.to_list(ws)), x > 0, do: {Enum.at(bones, j).name, x}
            list -> list
          end

        Enum.reduce(list, acc, fn {b, x}, acc -> Map.update(acc, b, [[i, x]], &[[i, x] | &1]) end)
      end)

    {points ++ Enum.map(ps, &elem(&1, 0)), faces ++ Enum.map(tris, fn t -> Enum.map(t, &(&1 + n)) end),
     mats ++ List.duplicate(m, length(tris)), weights, n + length(ps)}
  end)

# The ground at the lowest point.
low = points |> Enum.map(&elem(&1, 2)) |> Enum.min()
round = fn {x, y, z} -> Enum.map([x, y, z - low], &Float.round(&1 / 1, 5)) end

data = %{
  "source" => "World: a smooth skin around the bones of World (World.Blob), fins and eyes (scripts/fish_template.exs).",
  "license" => "AGPL-3.0, as World",
  "points" => Enum.map(points, round),
  "faces" => faces,
  "materials" => [
    %{"name" => "body", "color" => [150, 130, 70]},
    %{"name" => "fins", "color" => [120, 100, 60]},
    %{"name" => "eye", "color" => [20, 20, 20]}
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
