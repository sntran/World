# Make the mesh of the template of primates (priv/animals/meshes/) from
# the body of MakeHuman (CC0, priv/makehuman/): the low-poly body of a man
# (the mid level of World.People.Human, "male1591"), its skeleton
# "game_engine" and its weights, with a head of a macaque and a tail of
# 8 bones that World adds. The same format as scripts/gltf_figure.exs.
#
#     mix run scripts/primate_template.exs OUT.json
#
# - The body: the numbers of World.People.Human by default, with no
#   clothes and no hair. The same point at a seam of the texture is one
#   point.
# - The head: a smooth skin of World (World.Blob) on the bones "head"
#   and "neck_01", with eyes and nostrils, in place of the head of the
#   person (below).
# - The tail: a tube from the back of the pelvis, down and a little to the
#   back, 0.9 m long (about the height of the body from the seat to the
#   top of the head), 4.5 cm thick at the root and 1.2 cm at the tip, in 8
#   bones (Tail1 to Tail8). A ring of points between two bones follows
#   them both.
alias World.People.Human
alias World.{Blob, Frame, Vec}

[output] = System.argv()
f = World.Detail.with(:mid, fn -> Human.person("primate", clothes: [], hair: nil) end)
[body] = for n <- f.nodes, p <- n.primitives, do: p
names = Enum.map(f.skeleton.bones, & &1.name)
index = names |> Enum.with_index() |> Map.new()
key = fn {x, y, z} -> {round(x * 1.0e5), round(y * 1.0e5), round(z * 1.0e5)} end

# The points of the body, one for each place, and the weights of each.
{places, ids} =
  body.positions
  |> Enum.zip(Enum.zip(body.joints, body.weights))
  |> Enum.reduce({%{}, []}, fn {p, jw}, {places, ids} ->
    k = key.(p)
    places = Map.put_new(places, k, {map_size(places), p, jw})
    {places, [elem(places[k], 0) | ids]}
  end)

ids = ids |> Enum.reverse() |> List.to_tuple()
points = places |> Map.values() |> Enum.sort() |> Enum.map(&elem(&1, 1))

weights =
  for {i, _, {j, w}} <- Map.values(places), {b, k} <- Enum.zip(Tuple.to_list(j), Tuple.to_list(w)), k > 0, reduce: %{} do
    acc -> Map.update(acc, Enum.at(names, b), [[i, k]], &[[i, k] | &1])
  end

faces =
  body.indices
  |> Enum.chunk_every(3)
  |> Enum.map(fn t -> Enum.map(t, &elem(ids, &1)) end)
  |> Enum.filter(&(length(Enum.uniq(&1)) == 3))

# The head of a macaque in place of the head of the person: the faces
# of the person with a point on the bone "head" (a weight of 0.2 or
# more) or over the base of the neck (1.395 m) go, and a smooth skin of
# World (World.Blob) is the head. The parts (from photos of long-tailed
# macaques; the sizes are guesses): a round skull, a brow ridge over the
# eyes, the cheeks, a muzzle that goes to the front under the eyes with
# the nostrils at its front, a jaw with no chin under the muzzle, small
# ears that stand out to the sides, and a short neck that hides the edge
# of the body. Each point of the skin takes the weights of the 4 nearest
# points of the head and the neck of the person, so it moves as the head
# of the person. The eyes are near together, to the front, under the
# brow ridge; the nostrils are two small dark points.
head_w = Map.new(weights["head"], fn [i, w] -> {i, w} end)

# The points of the person above the shoulders and their weights, for
# the weights of the new head (below).
person =
  for {p, i} <- Enum.with_index(points), elem(p, 2) > 1.3 do
    {p, for({b, list} <- weights, b in ~w(spine_03 neck_01 head), [^i, w] <- list, do: {index[b], w})}
  end

faces = Enum.reject(faces, fn t -> Enum.any?(t, &(Map.get(head_w, &1, 0.0) >= 0.2 or elem(Enum.at(points, &1), 2) > 1.395)) end)

# The points that the faces keep, in their order, and the weights.
used = faces |> List.flatten() |> Enum.uniq() |> Enum.sort()
renumber = used |> Enum.with_index() |> Map.new()
points = Enum.map(used, &Enum.at(points, &1))
faces = Enum.map(faces, fn t -> Enum.map(t, &renumber[&1]) end)

weights =
  for {b, list} <- weights, l = for([i, w] <- list, Map.has_key?(renumber, i), do: [renumber[i], w]), l != [], into: %{},
    do: {b, l}

# A body of the skin on the bone `name`: from `a` to `b`, its radius
# {across, up} at each end (in m, at the size of the person), in a group
# (the bodies of two groups join with a blend).
body = fn name, a, b, r0, r1, group ->
  dir = Vec.norm(Vec.sub(b, a))
  up = if abs(elem(dir, 2)) > 0.9, do: {0.0, 1.0, 0.0}, else: {0.0, 0.0, 1.0}
  z = Vec.norm(Vec.sub(up, Vec.scale(dir, Vec.dot(up, dir))))
  %{name: name, head: a, tail: b, radius: {r0, r1}, group: group, frame: Frame.new(a, z, dir)}
end

mirror = fn {x, y, z} -> {-x, y, z} end

# The skull, the brow ridge, the muzzle, the jaw and the neck; the cheeks
# and the ears on each side.
bodies =
  [
    body.("head", {0.0, 0.0, 1.53}, {0.0, 0.05, 1.535}, {0.07, 0.068}, {0.066, 0.064}, "skull"),
    body.("head", {-0.045, 0.098, 1.552}, {0.045, 0.098, 1.552}, {0.016, 0.014}, {0.016, 0.014}, "skull"),
    body.("head", {0.0, 0.07, 1.495}, {0.0, 0.13, 1.482}, {0.034, 0.034}, {0.026, 0.027}, "muzzle"),
    body.("head", {0.0, 0.05, 1.455}, {0.0, 0.11, 1.452}, {0.03, 0.02}, {0.021, 0.015}, "jaw"),
    body.("neck_01", {0.0, 0.01, 1.37}, {0.0, 0.02, 1.47}, {0.058, 0.05}, {0.054, 0.05}, "neck")
  ] ++
    for m <- [& &1, mirror] do
      [
        body.("head", m.({0.042, 0.04, 1.5}), m.({0.036, 0.085, 1.49}), {0.027, 0.027}, {0.022, 0.022}, "skull"),
        body.("head", m.({0.058, -0.004, 1.532}), m.({0.08, -0.026, 1.537}), {0.005, 0.013}, {0.005, 0.016}, "ear")
      ]
    end
    |> List.flatten()

blob_bodies = for b <- bodies, do: Map.put(b, :index, index[b.name])
{skin, skin_tris} = Blob.mesh(blob_bodies, 0.008, 0.018)

# A sphere on the skin: on the ray from `from` along `dir`, its center
# `inside` of its radius under the skin.
sphere = fn from, dir, r, inside ->
  c = Vec.add(Blob.surface(blob_bodies, from, dir, 0.018), Vec.scale(dir, -inside * r))
  {rings, segs} = {6, 10}

  ps =
    for i <- 0..rings, j <- 0..(segs - 1) do
      {a, b} = {:math.pi() * i / rings, 2 * :math.pi() * j / segs}
      Vec.add(c, Vec.scale({:math.sin(a) * :math.cos(b), :math.sin(a) * :math.sin(b), :math.cos(a)}, r))
    end

  k = fn i, j -> i * segs + rem(j, segs) end
  {ps, for(i <- 0..(rings - 1), j <- 0..(segs - 1), t <- [[k.(i, j), k.(i + 1, j), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i, j + 1)]], do: t)}
end

eyes = for x <- [0.02, -0.02], do: sphere.({x, 0.0, 1.528}, {0.0, 1.0, 0.0}, 0.0125, 0.6)
nostrils = for x <- [0.007, -0.007], do: sphere.({x, 0.0, 1.488}, {0.0, 1.0, 0.0}, 0.0045, 0.5)

# The new points of the head: the skin with its weights, and the eyes and
# the nostrils on the bone head. The material of each face: 0 the skin,
# 1 the eyes, 2 the nostrils.
n0 = length(points)

# The weights of a point of the skin: the weights of the 4 nearest points
# of the person, each by 1 / its distance.
near_weights = fn p ->
  near = person |> Enum.map(fn {q, jw} -> {Vec.len(Vec.sub(p, q)), jw} end) |> Enum.sort() |> Enum.take(4)
  ws = for {d, jw} <- near, {j, w} <- jw, do: {j, w / max(d, 1.0e-4)}
  sum = ws |> Enum.map(&elem(&1, 1)) |> Enum.sum()
  ws |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Enum.map(fn {j, l} -> {j, Enum.sum(l) / sum} end)
end

head_parts =
  [{0, Enum.map(skin, fn {p, _, _} -> {p, near_weights.(p)} end), skin_tris}] ++
    for({ps, tris} <- eyes, do: {1, Enum.map(ps, &{&1, [{index["head"], 1.0}]}), tris}) ++
    for {ps, tris} <- nostrils, do: {2, Enum.map(ps, &{&1, [{index["head"], 1.0}]}), tris}

{head_points, head_faces, head_materials, weights, _} =
  Enum.reduce(head_parts, {[], [], [], weights, n0}, fn {m, ps, tris}, {pts, fs, ms, weights, n} ->
    weights =
      ps
      |> Enum.with_index(n)
      |> Enum.reduce(weights, fn {{_, jw}, i}, acc ->
        jw
        |> Enum.filter(fn {_, w} -> w > 0 end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.reduce(acc, fn {j, ws}, acc -> Map.update(acc, Enum.at(names, j), [[i, Enum.sum(ws)]], &[[i, Enum.sum(ws)] | &1]) end)
      end)

    {pts ++ Enum.map(ps, &elem(&1, 0)), fs ++ Enum.map(tris, fn t -> Enum.map(t, &(&1 + n)) end), ms ++ List.duplicate(m, length(tris)), weights,
     n + length(ps)}
  end)

# The tail: its root at the back of the pelvis, at the height of the head
# of the pelvis.
by = Map.new(f.skeleton.bones, &{&1.name, &1})
pelvis = by["pelvis"].head
seat = for [i, w] <- weights["pelvis"], w >= 0.5, do: Enum.at(points, i)
back = seat |> Enum.map(&elem(&1, 1)) |> Enum.min()
root = {0.0, back + 0.03, elem(pelvis, 2)}
dir = Vec.norm({0.0, -0.25, -1.0})
{count, length, sides} = {8, 0.9, 8}
side = {1.0, 0.0, 0.0}
up = Vec.cross(dir, side)
radius = fn t -> 0.045 + (0.012 - 0.045) * t end
n1 = n0 + length(head_points)

rings =
  for k <- 0..count, j <- 0..(sides - 1) do
    t = k / count
    a = 2 * :math.pi() * j / sides
    c = Vec.add(root, Vec.scale(dir, length * t))
    Vec.add(c, Vec.scale(Vec.add(Vec.scale(side, :math.cos(a)), Vec.scale(up, :math.sin(a))), radius.(t)))
  end

tip = Vec.add(root, Vec.scale(dir, length + 0.012))
at = fn k, j -> n1 + k * sides + rem(j, sides) end

tail_faces =
  (for k <- 0..(count - 1), j <- 0..(sides - 1), tri <- [[at.(k, j), at.(k + 1, j), at.(k + 1, j + 1)], [at.(k, j), at.(k + 1, j + 1), at.(k, j + 1)]], do: tri) ++
    for(j <- 0..(sides - 1), do: [at.(count, j), n1 + length(rings), at.(count, j + 1)])

# The faces of the tail go out: the corners of a face turn around its
# normal to the outside.
tail_faces =
  Enum.map(tail_faces, fn [a, b, c] = t ->
    ps = rings ++ [tip]
    [p, q, r] = Enum.map(t, &Enum.at(ps, &1 - n1))
    n = Vec.cross(Vec.sub(q, p), Vec.sub(r, p))
    mid = Vec.scale(Vec.add(Vec.add(p, q), r), 1 / 3)
    axis = Vec.add(root, Vec.scale(dir, Vec.dot(Vec.sub(mid, root), dir)))
    if Vec.dot(n, Vec.sub(mid, axis)) >= 0, do: [a, b, c], else: [a, c, b]
  end)

tail_names = for k <- 1..count, do: "Tail#{k}"

tail_weights =
  for k <- 0..count, j <- 0..(sides - 1), {bone, w} <- (case k do
        0 -> [{"pelvis", 1.0}]
        ^count -> [{"Tail#{count}", 1.0}]
        _ -> [{"Tail#{k}", 0.5}, {"Tail#{k + 1}", 0.5}]
      end), reduce: %{"Tail#{count}" => [[n1 + length(rings), 1.0]]} do
    acc -> Map.update(acc, bone, [[n1 + k * sides + j, w]], &[[n1 + k * sides + j, w] | &1])
  end

weights = Map.merge(weights, tail_weights, fn _, a, b -> a ++ b end)
round = fn {x, y, z} -> Enum.map([x, y, z], &Float.round(&1 / 1, 5)) end

tail_bones =
  for {name, k} <- Enum.with_index(tail_names) do
    %{
      "name" => name,
      "parent" => if(k == 0, do: "pelvis", else: "Tail#{k}"),
      "head" => round.(Vec.add(root, Vec.scale(dir, length * k / count))),
      "tail" => round.(Vec.add(root, Vec.scale(dir, length * (k + 1) / count)))
    }
  end

all = points ++ head_points ++ rings ++ [tip]
tris = faces ++ head_faces ++ tail_faces

data = %{
  "source" =>
    "MakeHuman (CC0): the low-poly body male1591, the skeleton game_engine and its weights (https://github.com/makehumancommunity/mpfb2); the head of a macaque and the tail are of World.",
  "license" => "CC0 1.0 (public domain): https://creativecommons.org/publicdomain/zero/1.0/",
  "points" => Enum.map(all, round),
  "faces" => tris,
  "materials" => [
    %{"name" => "body", "color" => [170, 140, 110]},
    %{"name" => "eye", "color" => [40, 28, 18]},
    %{"name" => "nose", "color" => [40, 30, 28]}
  ],
  "face_materials" =>
    List.duplicate(0, length(faces)) ++ head_materials ++ List.duplicate(0, length(tail_faces)),
  "bones" =>
    for(
      b <- f.skeleton.bones,
      Map.has_key?(weights, b.name) or b.name in ~w(Root),
      do: %{"name" => b.name, "parent" => b.parent, "head" => round.(b.head), "tail" => round.(b.tail)}
    ) ++ tail_bones,
  "weights" => Map.new(weights, fn {b, l} -> {b, l |> Enum.map(fn [i, w] -> [i, Float.round(w / 1, 5)] end) |> Enum.sort()} end)
}

File.write!(output, JSON.encode!(data))
IO.puts("#{length(all)} points, #{length(tris)} faces, #{length(data["bones"])} bones")
