# Make the data of a figure from a glTF file with a skin (one mesh, one
# skin; the buffers in the file or next to it): its mesh at rest, its
# bones and the weights of its skin, in one JSON file of priv/. The same
# format as scripts/fbx_figure.exs.
#
#     mix run scripts/gltf_figure.exs IN.gltf OUT.json "SOURCE" "LICENSE" [FRONT]
#
# FRONT is the axis of the file to the front of the animal: x, -x, y,
# -y, z or -z (z by default, the front of glTF). Up is +y.
#
# - The points of the mesh are at the bind pose of the skin. The same
#   point in two primitives (at the border of two materials, or with two
#   normals) is one point.
# - A bone is at the inverse of its inverse bind matrix. A bone with no
#   weight and no bone with weights under it (a target of inverse
#   kinematics) stays out.
# - A material has its name and its color (the base color, in sRGB 0 to
#   255).
# - The axes of World: z up, y to the front, x = y x z; the ground at
#   z = 0 and the middle at x = 0, y = 0.
Code.require_file("gltf.exs", __DIR__)

[input, output, source, license | rest] = System.argv()
gltf = GLTF.load(input)
read = &GLTF.read(gltf, &1)

nodes = gltf["nodes"]
skin = hd(gltf["skins"])
joints = skin["joints"]
parent = GLTF.parents(gltf)

# The head of a bone: the translation of the inverse of its inverse bind
# matrix (columns first): -R^T t for a matrix of a turn R and a move t.
heads =
  read.(skin["inverseBindMatrices"])
  |> Enum.zip(joints)
  |> Map.new(fn {m, j} ->
    m = Tuple.to_list(m)
    [r0, r1, r2] = for c <- 0..2, do: Enum.slice(m, c * 4, 3)
    t = Enum.slice(m, 12, 3)
    # The inverse of the 3 x 3 part times t.
    det = fn [a, b, c], [d, e, f], [g, h, i] -> a * (e * i - f * h) - d * (b * i - c * h) + g * (b * f - c * e) end
    cols = [r0, r1, r2]
    d = det.(r0, r1, r2)

    solve =
      for k <- 0..2 do
        det.(List.replace_at(cols, k, t) |> Enum.at(0), List.replace_at(cols, k, t) |> Enum.at(1), List.replace_at(cols, k, t) |> Enum.at(2)) / d
      end

    {j, solve |> Enum.map(&(-&1)) |> List.to_tuple()}
  end)

# The primitives: the points (one point for each place), the triangles,
# the material of each triangle, the weights of each point.
mesh = Enum.find(nodes, &Map.has_key?(&1, "mesh"))
prims = Enum.at(gltf["meshes"], mesh["mesh"])["primitives"]
key = fn {x, y, z} -> {round(x * 1.0e5), round(y * 1.0e5), round(z * 1.0e5)} end

{places, faces, face_materials, weights, _} =
  Enum.reduce(prims, {%{}, [], [], %{}, 0}, fn p, {places, faces, mats, weights, _} ->
    ps = read.(p["attributes"]["POSITION"])
    js = read.(p["attributes"]["JOINTS_0"])
    ws = read.(p["attributes"]["WEIGHTS_0"])

    {places, ids, weights} =
      Enum.zip([ps, js, ws])
      |> Enum.reduce({places, [], weights}, fn {pos, j, w}, {places, ids, weights} ->
        k = key.(pos)
        {places, id} = if Map.has_key?(places, k), do: {places, elem(places[k], 0)}, else: {Map.put(places, k, {map_size(places), pos}), map_size(places)}

        weights =
          for {jj, ww} <- Enum.zip(Tuple.to_list(j), Tuple.to_list(w)), ww > 0, reduce: weights do
            acc -> Map.put(acc, {Enum.at(joints, jj), id}, ww)
          end

        {places, [id | ids], weights}
      end)

    ids = ids |> Enum.reverse() |> List.to_tuple()
    tris = read.(p["indices"]) |> Enum.chunk_every(3) |> Enum.map(fn t -> Enum.map(t, &elem(ids, &1)) end)
    {places, faces ++ tris, mats ++ List.duplicate(p["material"] || 0, length(tris)), weights, 0}
  end)

points = places |> Map.values() |> Enum.sort() |> Enum.map(&elem(&1, 1))
# A triangle with two corners at one place (a seam) goes.
{faces, face_materials} = faces |> Enum.zip(face_materials) |> Enum.filter(fn {t, _} -> length(Enum.uniq(t)) == 3 end) |> Enum.unzip()

# The bones with weights, and the bones above them.
weighted = for {{j, _}, _} <- weights, into: MapSet.new(), do: j
up = fn j -> parent[j] end
keep = for j <- joints, Enum.any?(weighted, fn w -> Stream.iterate(w, up) |> Enum.take_while(& &1) |> Enum.member?(j) end), do: j
name = fn j -> Enum.at(nodes, j)["name"] end
bone_parent = fn j -> Stream.iterate(parent[j], up) |> Enum.take_while(& &1) |> Enum.find(&(&1 in keep)) end
ordered = Enum.sort_by(keep, fn j -> Stream.iterate(j, bone_parent) |> Enum.take_while(& &1) |> length() end)

# The axes of World.
{sign, axis} =
  case rest do
    ["-" <> a] -> {-1, a}
    [a] -> {1, a}
    [] -> {1, "z"}
  end

front = List.to_tuple(for a <- ~w(x y z), do: if(a == axis, do: sign * 1.0, else: 0.0))
up_axis = {0.0, 1.0, 0.0}
right = World.Vec.cross(front, up_axis)
turn = fn p -> {World.Vec.dot(p, right), World.Vec.dot(p, front), World.Vec.dot(p, up_axis)} end
world = Enum.map(points, turn)
{{x0, y0, z0}, {x1, y1, _}} = World.Vec.bounds(world)
shift = fn p -> World.Vec.sub(turn.(p), {(x0 + x1) / 2, (y0 + y1) / 2, z0}) end
round = fn {x, y, z} -> Enum.map([x, y, z], &Float.round(&1 / 1, 5)) end
srgb = fn c -> if c <= 0.0031308, do: 12.92 * c, else: 1.055 * :math.pow(c, 1 / 2.4) - 0.055 end

data = %{
  "source" => source,
  "license" => license,
  "points" => Enum.map(points, &round.(shift.(&1))),
  "faces" => faces,
  "materials" =>
    for m <- gltf["materials"] do
      [r, g, b | _] = get_in(m, ["pbrMetallicRoughness", "baseColorFactor"]) || [1, 1, 1, 1]
      %{"name" => m["name"], "color" => Enum.map([r, g, b], &round(255 * srgb.(&1)))}
    end,
  "face_materials" => face_materials,
  "bones" =>
    for j <- ordered do
      %{"name" => name.(j), "parent" => (p = bone_parent.(j)) && name.(p), "head" => round.(shift.(heads[j]))}
    end,
  "weights" =>
    weights
    |> Enum.group_by(fn {{j, _}, _} -> name.(j) end, fn {{_, i}, w} -> [i, Float.round(w, 5)] end)
    |> Map.new(fn {b, l} -> {b, Enum.sort(l)} end)
}

File.write!(output, JSON.encode!(data))
IO.puts("#{length(points)} points, #{length(faces)} faces, #{length(ordered)} bones, #{length(data["materials"])} materials")
