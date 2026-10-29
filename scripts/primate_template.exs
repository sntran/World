# Make the mesh of the template of primates (priv/animals/meshes/) from
# the body of MakeHuman (CC0, priv/makehuman/): the low-poly body of a man
# (the mid level of World.People.Human, "male1591"), its skeleton
# "game_engine" and its weights, the low-poly eyes, and a tail of 8
# bones that World adds. The same format as scripts/gltf_figure.exs.
#
#     mix run scripts/primate_template.exs OUT.json
#
# - The body: the numbers of World.People.Human by default, with no
#   clothes and no hair. The same point at a seam of the texture is one
#   point.
# - The eyes: the asset "low-poly" of MakeHuman on the body, on the bone
#   "head".
# - The tail: a tube from the back of the pelvis, down and a little to the
#   back, 0.9 m long (about the height of the body from the seat to the
#   top of the head), 4.5 cm thick at the root and 1.2 cm at the tip, in 8
#   bones (Tail1 to Tail8). A ring of points between two bones follows
#   them both.
alias World.People.{Data, Human}
alias World.Vec

[output] = System.argv()
o = %{gender: 1.0, age: 30, muscle: 0.5, weight: 0.5, height: 0.5, race: %{"asian" => 1.0}}
f = World.Detail.with(:mid, fn -> Human.person("primate", clothes: [], hair: nil) end)
[body] = for n <- f.nodes, p <- n.primitives, do: p
names = Enum.map(f.skeleton.bones, & &1.name)
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

# The eyes, as World.People.Human fits an asset: the sum of three points
# of the body with their weights, and an offset in the scale of the body.
base = Data.base()
arr = :array.from_list(Tuple.to_list(base.points))

morphed =
  Human.target_weights(o)
  |> Enum.reduce(arr, fn {name, w}, arr ->
    Enum.reduce(Data.target(name), arr, fn {i, {dx, dy, dz}}, arr ->
      {x, y, z} = :array.get(i, arr)
      :array.set(i, {x + w * dx, y + w * dy, z + w * dz}, arr)
    end)
  end)
  |> :array.to_list()
  |> List.to_tuple()

ground = (for f <- base.groups["body"], {v, _} <- f, do: elem(elem(morphed, v), 1)) |> Enum.min() |> Kernel.*(0.1)
eyes = Data.asset("eyes", "low-poly")

scale = fn axis, k ->
  with {a, b, d} <- Map.get(eyes.fit.scales, axis, 1.0), do: abs(elem(elem(morphed, a), k) - elem(elem(morphed, b), k)) / d
end

s = {scale.("x_scale", 0), scale.("y_scale", 1), scale.("z_scale", 2)}

eye_points =
  for {vs, ws, {dx, dy, dz}} <- Tuple.to_list(eyes.fit.refs) do
    p = Enum.zip(vs, ws) |> Enum.map(fn {v, w} -> Vec.scale(elem(morphed, v), w) end) |> Enum.reduce(&Vec.add/2)
    p = Vec.add(p, {dx * elem(s, 0), dy * elem(s, 1), dz * elem(s, 2)})
    Vec.sub(Human.to_world(p), {0.0, 0.0, ground})
  end

n0 = length(points)

eye_faces =
  for f <- eyes.mesh.groups |> Map.values() |> Enum.concat(),
      [a | rest] = Enum.map(f, &(elem(&1, 0) + n0)),
      [b, c] <- Enum.chunk_every(rest, 2, 1, :discard),
      do: [a, b, c]

weights = Map.update!(weights, "head", &(&1 ++ for(i <- n0..(n0 + length(eye_points) - 1), do: [i, 1.0])))

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
n1 = n0 + length(eye_points)

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

all = points ++ eye_points ++ rings ++ [tip]
tris = faces ++ eye_faces ++ tail_faces

data = %{
  "source" =>
    "MakeHuman (CC0): the low-poly body male1591, the skeleton game_engine and its weights, and the low-poly eyes (https://github.com/makehumancommunity/mpfb2); the tail is of World.",
  "license" => "CC0 1.0 (public domain): https://creativecommons.org/publicdomain/zero/1.0/",
  "points" => Enum.map(all, round),
  "faces" => tris,
  "materials" => [%{"name" => "body", "color" => [170, 140, 110]}, %{"name" => "eye", "color" => [40, 28, 18]}],
  "face_materials" =>
    List.duplicate(0, length(faces)) ++ List.duplicate(1, length(eye_faces)) ++ List.duplicate(0, length(tail_faces)),
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
