# Make the data of a figure from a binary FBX file (version 7.4: the
# export of Blender 2.7): its mesh at rest, its bones and the weights of
# its skin, in one JSON file of priv/.
#
#     mix run scripts/fbx_figure.exs IN.fbx OUT.json "SOURCE" "LICENSE"
#
# The script reads the data only. The JSON has:
#
# - "points": the points of the mesh in the axes of World (x to the right
#   side, y to the front, z up), in the units of the file / 100, with the
#   ground at z = 0 and the middle at x = 0, y = 0;
# - "faces": the faces (lists of point indices);
# - "bones": each bone with weights or with bones with weights under it,
#   parents first: its "name", "parent" and "head" (the point of its
#   joint), and "tail" for a bone with an end node;
# - "weights": a bone to its list of [point, weight];
# - "source", "license".
#
# The mesh is at the frame of its model (translation, rotation XYZ,
# scale), as the bones (the matrix TransformLink of each cluster of the
# skin). The axes of the file are Y up and X to the front (the file of a
# quadruped of Blender 2.7); the script turns them to the axes of World.
defmodule FBXFigure do
  def nodes(<<"Kaydara FBX Binary  ", 0, 0x1A, 0, version::little-32, _::binary>> = bin) when version < 7500,
    do: elem(list(bin, 27, byte_size(bin)), 0)

  defp list(bin, pos, stop) do
    case node(bin, pos) do
      nil ->
        {[], pos + 13}

      {n, next} when next >= stop ->
        {[n], next}

      {n, next} ->
        {more, last} = list(bin, next, stop)
        {[n | more], last}
    end
  end

  defp node(bin, pos) do
    <<_::binary-size(^pos), stop::little-32, count::little-32, size::little-32, len::8, rest::binary>> = bin

    if stop == 0 do
      nil
    else
      <<name::binary-size(^len), _::binary>> = rest
      start = pos + 13 + len
      {props, _} = Enum.map_reduce(List.duplicate(nil, count), start, fn _, p -> prop(bin, p) end)
      children = if start + size < stop, do: elem(list(bin, start + size, stop - 13), 0), else: []
      {{name, props, children}, stop}
    end
  end

  defp prop(bin, p) do
    <<_::binary-size(^p), type::8, rest::binary>> = bin

    case type do
      ?Y -> with <<v::little-signed-16, _::binary>> <- rest, do: {v, p + 3}
      ?C -> with <<v::8, _::binary>> <- rest, do: {v != 0, p + 2}
      ?I -> with <<v::little-signed-32, _::binary>> <- rest, do: {v, p + 5}
      ?F -> with <<v::little-float-32, _::binary>> <- rest, do: {v, p + 5}
      ?D -> with <<v::little-float-64, _::binary>> <- rest, do: {v, p + 9}
      ?L -> with <<v::little-signed-64, _::binary>> <- rest, do: {v, p + 9}
      t when t in [?S, ?R] -> with <<n::little-32, s::binary-size(n), _::binary>> <- rest, do: {s, p + 5 + n}
      t -> array(t, rest, p)
    end
  end

  defp array(t, rest, p) do
    <<_n::little-32, enc::little-32, size::little-32, data::binary-size(size), _::binary>> = rest
    raw = if enc == 1, do: :zlib.uncompress(data), else: data

    values =
      case t do
        ?f -> for <<v::little-float-32 <- raw>>, do: v
        ?d -> for <<v::little-float-64 <- raw>>, do: v
        ?l -> for <<v::little-signed-64 <- raw>>, do: v
        ?i -> for <<v::little-signed-32 <- raw>>, do: v
        ?b -> for <<v::8 <- raw>>, do: v != 0
      end

    {values, p + 13 + size}
  end
end

[input, output, source, license] = System.argv()
nodes = FBXFigure.nodes(File.read!(input))
section = fn name -> nodes |> Enum.find(&(elem(&1, 0) == name)) |> elem(2) end
child = fn {_, _, cs}, name -> Enum.find(cs, &(elem(&1, 0) == name)) end
value = fn n, name -> with {_, [v | _], _} <- child.(n, name), do: v end
clean = fn s -> s |> String.split(<<0, 1>>) |> hd() end
objects = section.("Objects")

props = fn n ->
  {_, _, p70} = child.(n, "Properties70")
  for {_, [k, _, _, _ | v], _} <- p70, into: %{}, do: {k, v}
end

models = for {"Model", [id, name, type | _], _} = n <- objects, into: %{}, do: {id, %{name: clean.(name), type: type, props: props.(n)}}
links = for {"C", ["OO", a, b | _], _} <- section.("Connections"), do: {a, b}
parent = for {a, b} <- links, Map.has_key?(models, a), Map.has_key?(models, b), into: %{}, do: {a, b}
by_name = Map.new(models, fn {id, m} -> {m.name, id} end)

# A point through a matrix of 16 numbers (FBX: the columns one after the
# other).
point = fn m, {x, y, z} ->
  m = List.to_tuple(m)
  {elem(m, 0) * x + elem(m, 4) * y + elem(m, 8) * z + elem(m, 12), elem(m, 1) * x + elem(m, 5) * y + elem(m, 9) * z + elem(m, 13),
   elem(m, 2) * x + elem(m, 6) * y + elem(m, 10) * z + elem(m, 14)}
end

# The frame of a model: translation, rotation XYZ (degrees), scale.
frame = fn m ->
  [tx, ty, tz] = Map.get(m.props, "Lcl Translation", [0.0, 0.0, 0.0])
  [rx, ry, rz] = Map.get(m.props, "Lcl Rotation", [0.0, 0.0, 0.0]) |> Enum.map(&(&1 * :math.pi() / 180))
  [sx, sy, sz] = Map.get(m.props, "Lcl Scaling", [1.0, 1.0, 1.0])

  fn {x, y, z} ->
    {x, y, z} = {x * sx, y * sy, z * sz}
    {y, z} = {y * :math.cos(rx) - z * :math.sin(rx), y * :math.sin(rx) + z * :math.cos(rx)}
    {x, z} = {x * :math.cos(ry) + z * :math.sin(ry), -x * :math.sin(ry) + z * :math.cos(ry)}
    {x, y} = {x * :math.cos(rz) - y * :math.sin(rz), x * :math.sin(rz) + y * :math.cos(rz)}
    {x + tx, y + ty, z + tz}
  end
end

geometry = Enum.find(objects, &(elem(&1, 0) == "Geometry"))
geometry_id = elem(geometry, 1) |> hd()
mesh = models[Enum.find_value(links, fn {a, b} -> if a == geometry_id, do: b end)]
to_global = frame.(mesh)
points = value.(geometry, "Vertices") |> Enum.chunk_every(3) |> Enum.map(&to_global.(List.to_tuple(&1)))

faces =
  value.(geometry, "PolygonVertexIndex")
  |> Enum.chunk_while([], fn i, acc -> if i < 0, do: {:cont, Enum.reverse([-i - 1 | acc]), []}, else: {:cont, [i | acc]} end, fn acc -> {:cont, acc} end)

clusters =
  for {"Deformer", [id, _, "Cluster" | _], _} = n <- objects,
      bone = Enum.find_value(links, fn {a, b} -> if b == id and Map.has_key?(models, a), do: models[a].name end),
      do: %{bone: bone, indexes: value.(n, "Indexes") || [], weights: value.(n, "Weights") || [], link: value.(n, "TransformLink")}

# A bone with no weight and no bone with weights under it (a target of
# inverse kinematics of the file) stays out.
weighted = for c <- clusters, c.indexes != [], into: MapSet.new(), do: c.bone
up = fn name -> parent[by_name[name]] && models[parent[by_name[name]]].name end
keep = for c <- clusters, Enum.any?(weighted, fn w -> Stream.iterate(w, up) |> Enum.take_while(& &1) |> Enum.member?(c.bone) end), into: MapSet.new(), do: c.bone
clusters = Enum.filter(clusters, &(&1.bone in keep))
heads = Map.new(clusters, &{&1.bone, point.(&1.link, {0.0, 0.0, 0.0})})

# The end node of a bone (a child with no cluster): its point in the
# frame of the bone.
tails =
  for c <- clusters,
      kid = Enum.find(Map.keys(parent), fn k -> parent[k] == by_name[c.bone] and not Map.has_key?(heads, models[k].name) end),
      kid != nil,
      into: %{},
      do: {c.bone, point.(c.link, List.to_tuple(Map.get(models[kid].props, "Lcl Translation", [0.0, 0.0, 0.0])))}

# The axes of World: x = Z, y = X, z = Y; the units / 100; the ground at
# z = 0 and the middle at x = 0, y = 0.
turn = fn {x, y, z} -> {z / 100, x / 100, y / 100} end
world = Enum.map(points, turn)
{{x0, y0, z0}, {x1, y1, _}} = World.Vec.bounds(world)
shift = fn p -> World.Vec.sub(turn.(p), {(x0 + x1) / 2, (y0 + y1) / 2, z0}) end
round = fn {x, y, z} -> Enum.map([x, y, z], &Float.round(&1, 5)) end

# The bones, parents first.
names = Enum.map(clusters, & &1.bone)
bone_parent = fn name -> with id when id != nil <- parent[by_name[name]], do: if(models[id].name in names, do: models[id].name) end
ordered = Enum.sort_by(names, fn name -> Stream.iterate(name, bone_parent) |> Enum.take_while(& &1) |> length() end)

data = %{
  "source" => source,
  "license" => license,
  "points" => Enum.map(points, &round.(shift.(&1))),
  "faces" => faces,
  "bones" =>
    for name <- ordered do
      %{"name" => name, "parent" => bone_parent.(name), "head" => round.(shift.(heads[name]))}
      |> then(&if(tails[name], do: Map.put(&1, "tail", round.(shift.(tails[name]))), else: &1))
    end,
  "weights" =>
    for c <- clusters, c.indexes != [], into: %{} do
      {c.bone, Enum.zip_with(c.indexes, c.weights, fn i, w -> [i, Float.round(w, 5)] end)}
    end
}

File.write!(output, JSON.encode!(data))
IO.puts("#{length(data["points"])} points, #{length(faces)} faces, #{length(ordered)} bones")
