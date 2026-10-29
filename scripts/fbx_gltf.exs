# Make a glTF file from a binary FBX file (version 7.x) with one mesh on
# a skin: the mesh at rest, the bones, the weights of the skin and the
# materials. Then scripts/gltf_figure.exs reads the glTF file. The clips
# of the FBX file stay out.
#
#     mix run scripts/fbx_gltf.exs IN.fbx OUT.gltf
#
# - A node of the glTF file is a model of the FBX file (a mesh, a bone or
#   an empty), with its move, its turn (the turn before the turn, then
#   the turn: X, then Y, then Z) and its scale. A model with a pivot or a
#   turn order that is not X, Y, Z stops the script.
# - The points of the mesh are at the place of the mesh in the scene. A
#   polygon is a fan of triangles from its first corner. The triangles
#   of each material are one primitive.
# - The bones of the skin are the models of its clusters, at their bind
#   pose (the matrix TransformLink of the cluster). The 4 largest weights
#   of a point stay, with a sum of 1.
# - The color of a material is its DiffuseColor.
defmodule FBX do
  @doc "The nodes of a binary FBX file: a list of `{name, properties, nodes}`."
  def parse(<<"Kaydara FBX Binary  ", 0, 0x1A, 0, version::little-32, _::binary>> = bin) do
    nodes(bin, 27, byte_size(bin), if(version >= 7500, do: 64, else: 32))
  end

  defp nodes(bin, at, stop, w) do
    head = div(w, 8) * 3 + 1

    with true <- at + head <= stop,
         <<_::binary-size(^at), finish::little-size(^w), count::little-size(^w), length::little-size(^w), n::8,
           name::binary-size(n), _::binary>>
         when finish > 0 <- bin do
      start = at + head + n
      {props, _} = props(bin, start, count, [])
      children = if start + length < finish, do: nodes(bin, start + length, finish, w), else: []
      [{name, props, children} | nodes(bin, finish, stop, w)]
    else
      _ -> []
    end
  end

  defp props(_, at, 0, acc), do: {Enum.reverse(acc), at}

  defp props(bin, at, n, acc) do
    <<_::binary-size(^at), type::8, rest::binary>> = bin

    {value, size} =
      case {type, rest} do
        {?C, <<v::8, _::binary>>} ->
          {v != 0, 1}

        {?Y, <<v::little-signed-16, _::binary>>} ->
          {v, 2}

        {?I, <<v::little-signed-32, _::binary>>} ->
          {v, 4}

        {?F, <<v::little-float-32, _::binary>>} ->
          {v, 4}

        {?D, <<v::little-float-64, _::binary>>} ->
          {v, 8}

        {?L, <<v::little-signed-64, _::binary>>} ->
          {v, 8}

        {t, <<l::little-32, v::binary-size(l), _::binary>>} when t in [?S, ?R] ->
          {v, 4 + l}

        {t, <<_::little-32, enc::little-32, l::little-32, data::binary-size(l), _::binary>>} ->
          {array(t, enc, data), 12 + l}
      end

    props(bin, at + 1 + size, n - 1, [value | acc])
  end

  defp array(type, 1, data), do: array(type, 0, :zlib.uncompress(data))
  defp array(?f, 0, data), do: for(<<v::little-float-32 <- data>>, do: v)
  defp array(?d, 0, data), do: for(<<v::little-float-64 <- data>>, do: v)
  defp array(?l, 0, data), do: for(<<v::little-signed-64 <- data>>, do: v)
  defp array(?i, 0, data), do: for(<<v::little-signed-32 <- data>>, do: v)
  defp array(?b, 0, data), do: for(<<v::8 <- data>>, do: v)

  @doc "The first child of a node with a name, or nil."
  def child({_, _, children}, name), do: Enum.find(children, &(elem(&1, 0) == name))

  @doc "The values of the property of a node (Properties70) with a name, or nil."
  def prop(node, name) do
    with {_, _, ps} <- child(node, "Properties70"),
         {_, [_, _, _, _ | v], _} <- Enum.find(ps, &(hd(elem(&1, 1)) == name)),
         do: v
  end

  # Matrices of 4 x 4 as a list of rows.
  def mul(a, b), do: for(r <- a, do: for(c <- Enum.zip_with(b, & &1), do: Enum.sum(Enum.zip_with(r, c, &*/2))))

  def apply(m, {x, y, z}),
    do: m |> Enum.take(3) |> Enum.map(fn [a, b, c, d] -> a * x + b * y + c * z + d end) |> List.to_tuple()

  def move([x, y, z]), do: [[1, 0, 0, x], [0, 1, 0, y], [0, 0, 1, z], [0, 0, 0, 1]]
  def scale([x, y, z]), do: [[x, 0, 0, 0], [0, y, 0, 0], [0, 0, z, 0], [0, 0, 0, 1]]

  # A turn X, then Y, then Z (in degrees): Rz Ry Rx.
  def turn([x, y, z]) do
    [x, y, z] = Enum.map([x, y, z], &(&1 * :math.pi() / 180))
    {cx, sx, cy, sy, cz, sz} = {:math.cos(x), :math.sin(x), :math.cos(y), :math.sin(y), :math.cos(z), :math.sin(z)}
    rx = [[1, 0, 0, 0], [0, cx, -sx, 0], [0, sx, cx, 0], [0, 0, 0, 1]]
    ry = [[cy, 0, sy, 0], [0, 1, 0, 0], [-sy, 0, cy, 0], [0, 0, 0, 1]]
    rz = [[cz, -sz, 0, 0], [sz, cz, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    mul(rz, mul(ry, rx))
  end

  # The quaternion (x, y, z, w) of the turn part of a matrix.
  def quaternion([[a, b, c, _], [d, e, f, _], [g, h, i, _] | _]) do
    t = a + e + i

    q =
      cond do
        t > 0 ->
          s = 2 * :math.sqrt(t + 1)
          [(h - f) / s, (c - g) / s, (d - b) / s, s / 4]

        a > e and a > i ->
          s = 2 * :math.sqrt(1 + a - e - i)
          [s / 4, (b + d) / s, (c + g) / s, (h - f) / s]

        e > i ->
          s = 2 * :math.sqrt(1 + e - a - i)
          [(b + d) / s, s / 4, (f + h) / s, (c - g) / s]

        true ->
          s = 2 * :math.sqrt(1 + i - a - e)
          [(c + g) / s, (f + h) / s, s / 4, (d - b) / s]
      end

    n = :math.sqrt(Enum.sum(Enum.map(q, &(&1 * &1))))
    Enum.map(q, &(&1 / n))
  end

  # The inverse of a matrix of a turn, a scale on each axis of the turn
  # and a move: the columns of the 3 x 3 part are at right angles.
  def inverse(m) do
    cols = for k <- 0..2, do: Enum.map(Enum.take(m, 3), &Enum.at(&1, k))
    rows = Enum.map(cols, fn c -> Enum.map(c, &(&1 / Enum.sum(Enum.map(c, fn v -> v * v end)))) end)
    t = Enum.map(Enum.take(m, 3), &Enum.at(&1, 3))
    Enum.map(rows, fn r -> r ++ [-Enum.sum(Enum.zip_with(r, t, &*/2))] end) ++ [[0, 0, 0, 1]]
  end
end

[input, output] = System.argv()
tree = input |> File.read!() |> FBX.parse()
objects = tree |> Enum.find(&(elem(&1, 0) == "Objects")) |> elem(2) |> Map.new(fn {_, [id | _], _} = o -> {id, o} end)

links =
  for {"C", [kind, child, parent | prop], _} <- Enum.find(tree, &(elem(&1, 0) == "Connections")) |> elem(2),
      do: {kind, child, parent, prop}

kind = fn id -> elem(objects[id], 0) end
name = fn id -> objects[id] |> elem(1) |> Enum.at(1) |> String.split(<<0, 1>>) |> hd() end
children = fn id, k -> for {"OO", c, ^id, _} <- links, objects[c] && kind.(c) == k, do: c end
model? = fn id -> objects[id] && kind.(id) == "Model" end
parent = for {"OO", c, p, _} <- links, model?.(c), p == 0 or model?.(p), into: %{}, do: {c, p}

# The models, parents first; the matrix of each to its parent.
models = for {id, {"Model", _, _}} <- objects, do: id
depth = fn id -> Stream.iterate(id, &parent[&1]) |> Enum.take_while(&(&1 && &1 != 0)) |> length() end
models = Enum.sort_by(models, &{depth.(&1), name.(&1)})

local =
  Map.new(models, fn id ->
    o = objects[id]

    for p <- ~w(RotationPivot ScalingPivot RotationOffset ScalingOffset GeometricTranslation GeometricRotation),
        v = FBX.prop(o, p),
        v != [0.0, 0.0, 0.0] do
      raise "the model #{name.(id)} has #{p} #{inspect(v)}"
    end

    if (FBX.prop(o, "RotationOrder") || [0]) != [0],
      do: raise("the model #{name.(id)} has a turn order that is not X, Y, Z")

    t = FBX.prop(o, "Lcl Translation") || [0.0, 0.0, 0.0]

    r =
      FBX.mul(
        FBX.turn(FBX.prop(o, "PreRotation") || [0.0, 0.0, 0.0]),
        FBX.turn(FBX.prop(o, "Lcl Rotation") || [0.0, 0.0, 0.0])
      )

    s = FBX.prop(o, "Lcl Scaling") || [1.0, 1.0, 1.0]
    {id, {t, r, s}}
  end)

global =
  Enum.reduce(models, %{}, fn id, acc ->
    {t, r, s} = local[id]
    m = FBX.mul(FBX.move(t), FBX.mul(r, FBX.scale(s)))
    Map.put(acc, id, if(acc[parent[id]], do: FBX.mul(acc[parent[id]], m), else: m))
  end)

# The mesh: the model with a geometry and a skin.
[{geometry, mesh}] = for {"OO", g, m, _} <- links, objects[g] && kind.(g) == "Geometry", do: {g, m}
geo = objects[geometry]

places =
  geo
  |> FBX.child("Vertices")
  |> elem(1)
  |> hd()
  |> Enum.chunk_every(3)
  |> Enum.map(&FBX.apply(global[mesh], List.to_tuple(&1)))

polygons =
  geo
  |> FBX.child("PolygonVertexIndex")
  |> elem(1)
  |> hd()
  |> Enum.chunk_while(
    [],
    fn i, acc -> if i < 0, do: {:cont, Enum.reverse([-i - 1 | acc]), []}, else: {:cont, [i | acc]} end,
    &{:cont, &1}
  )

face_materials =
  case FBX.child(geo, "LayerElementMaterial") do
    nil ->
      List.duplicate(0, length(polygons))

    layer ->
      layer
      |> FBX.child("Materials")
      |> elem(1)
      |> hd()
      |> then(&if(length(&1) == 1, do: List.duplicate(hd(&1), length(polygons)), else: &1))
  end

materials = children.(mesh, "Material") |> Enum.reverse()
[skin] = for {"OO", s, ^geometry, _} <- links, kind.(s) == "Deformer", do: s
clusters = for {"OO", c, ^skin, _} <- links, do: c
bone = Map.new(clusters, fn c -> {c, hd(for {"OO", b, ^c, _} <- links, do: b)} end)
joints = Enum.filter(models, &(&1 in Map.values(bone)))

# The place of a bone at rest is its bind pose (TransformLink: FBX
# lists the matrix by columns), not its place in the file (the pose of
# a frame of a clip). The matrix of a model to its parent comes from the
# places in the scene.
link = fn c ->
  objects[c] |> FBX.child("TransformLink") |> elem(1) |> hd() |> Enum.chunk_every(4) |> Enum.zip_with(& &1)
end

global = Map.merge(global, Map.new(clusters, &{bone[&1], link.(&1)}))

local =
  Map.new(models, fn id ->
    m = if global[parent[id]], do: FBX.mul(FBX.inverse(global[parent[id]]), global[id]), else: global[id]
    s = for k <- 0..2, do: :math.sqrt(Enum.sum(for r <- Enum.take(m, 3), do: Enum.at(r, k) ** 2))
    r = Enum.map(m, fn row -> Enum.with_index(row, fn v, k -> if k < 3, do: v / Enum.at(s, k), else: v end) end)
    {id, {Enum.map(Enum.take(m, 3), &Enum.at(&1, 3)), r, s}}
  end)

weights =
  for c <- clusters,
      i = FBX.child(objects[c], "Indexes"),
      j = Enum.find_index(joints, &(&1 == bone[c])),
      {p, w} <- Enum.zip(hd(elem(i, 1)), hd(elem(FBX.child(objects[c], "Weights"), 1))),
      reduce: %{} do
    acc -> Map.update(acc, p, [{w, j}], &[{w, j} | &1])
  end

skin_of = fn p ->
  list = (weights[p] || []) |> Enum.sort(:desc) |> Enum.take(4)
  sum = Enum.sum(Enum.map(list, &elem(&1, 0)))
  list = list ++ List.duplicate({0.0, 0}, 4 - length(list))
  {Enum.map(list, &elem(&1, 1)), Enum.map(list, &if(sum > 0, do: elem(&1, 0) / sum, else: 0.0))}
end

# The binary buffer: the points, the joints, the weights, then the
# triangles of each material.
f32 = fn l -> for v <- l, into: <<>>, do: <<v::little-float-32>> end
pos = f32.(Enum.flat_map(places, &Tuple.to_list/1))
skins = Enum.map(0..(length(places) - 1), skin_of)
js = for {j, _} <- skins, v <- j, into: <<>>, do: <<v::little-16>>
ws = f32.(Enum.flat_map(skins, &elem(&1, 1)))

tris =
  for {poly, m} <- Enum.zip(polygons, face_materials),
      [a | rest] = poly,
      [b, c] <- Enum.chunk_every(rest, 2, 1, :discard),
      do: {m, [a, b, c]}

by_material = Enum.group_by(tris, &elem(&1, 0), &elem(&1, 1)) |> Enum.sort()

ibm =
  f32.(Enum.flat_map(joints, fn j -> j |> then(&FBX.inverse(global[&1])) |> Enum.zip_with(& &1) |> List.flatten() end))

{views, buffer} =
  [pos, js, ws, ibm | for({_, t} <- by_material, do: for(v <- List.flatten(t), into: <<>>, do: <<v::little-32>>))]
  |> Enum.map_reduce(<<>>, fn data, acc ->
    {%{"buffer" => 0, "byteOffset" => byte_size(acc), "byteLength" => byte_size(data)}, acc <> data}
  end)

n = length(places)
{x, y, z} = Enum.reduce(places, fn {a, b, c}, {d, e, f} -> {min(a, d), min(b, e), min(c, f)} end)
{x1, y1, z1} = Enum.reduce(places, fn {a, b, c}, {d, e, f} -> {max(a, d), max(b, e), max(c, f)} end)

accessors =
  [
    %{
      "bufferView" => 0,
      "componentType" => 5126,
      "count" => n,
      "type" => "VEC3",
      "min" => [x, y, z],
      "max" => [x1, y1, z1]
    },
    %{"bufferView" => 1, "componentType" => 5123, "count" => n, "type" => "VEC4"},
    %{"bufferView" => 2, "componentType" => 5126, "count" => n, "type" => "VEC4"},
    %{"bufferView" => 3, "componentType" => 5126, "count" => length(joints), "type" => "MAT4"}
  ] ++
    for(
      {{_, t}, k} <- Enum.with_index(by_material),
      do: %{"bufferView" => 4 + k, "componentType" => 5125, "count" => 3 * length(t), "type" => "SCALAR"}
    )

index = models |> Enum.with_index() |> Map.new()

node = fn id ->
  {t, r, s} = local[id]
  base = %{"name" => name.(id), "translation" => t, "rotation" => FBX.quaternion(r), "scale" => s}
  kids = for c <- models, parent[c] == id, do: index[c]
  base = if kids == [], do: base, else: Map.put(base, "children", kids)
  if id == mesh, do: Map.merge(base, %{"mesh" => 0, "skin" => 0}), else: base
end

gltf = %{
  "asset" => %{"version" => "2.0", "generator" => "scripts/fbx_gltf.exs"},
  "scene" => 0,
  "scenes" => [%{"nodes" => for(id <- models, parent[id] in [nil, 0], do: index[id])}],
  "nodes" => Enum.map(models, node),
  "meshes" => [
    %{
      "primitives" =>
        for {{m, _}, k} <- Enum.with_index(by_material) do
          %{"attributes" => %{"POSITION" => 0, "JOINTS_0" => 1, "WEIGHTS_0" => 2}, "indices" => 4 + k, "material" => m}
        end
    }
  ],
  "skins" => [%{"joints" => Enum.map(joints, &index[&1]), "inverseBindMatrices" => 3}],
  "materials" =>
    for id <- materials do
      [r, g, b] = FBX.prop(objects[id], "DiffuseColor") || [1.0, 1.0, 1.0]
      %{"name" => name.(id), "pbrMetallicRoughness" => %{"baseColorFactor" => [r, g, b, 1.0]}}
    end,
  "accessors" => accessors,
  "bufferViews" => views,
  "buffers" => [
    %{"byteLength" => byte_size(buffer), "uri" => "data:application/octet-stream;base64," <> Base.encode64(buffer)}
  ]
}

File.write!(output, JSON.encode!(gltf))
IO.puts("#{n} points, #{length(tris)} triangles, #{length(joints)} bones, #{length(materials)} materials")
