# Make the data of a figure from a binary FBX file (version 7.4: the
# export of Blender 2.7): its mesh at rest, its bones and the weights of
# its skin, in one JSON file of priv/.
#
#     mix run scripts/fbx_figure.exs IN.fbx OUT.json "SOURCE" "LICENSE" [FRONT]
#
# FRONT is the axis of the file to the front of the animal: x, -x, y,
# -y, z or -z (x by default: a quadruped of Blender 2.7). The up axis
# comes from the settings of the file.
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
# The mesh and the bones are in the axes of the file at the bind pose:
# a bone at the matrix TransformLink of its cluster of the skin, the
# mesh at TransformLink x Transform (the same for each cluster). The
# script turns them to the axes of World: z up, y to the front, x = y x
# z.
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

  @doc """
  The pixels of a PNG file (8 bits, RGB or RGBA, not interlaced):
  `{width, height, pixel}`, with `pixel.(x, y)` the `{r, g, b}` of a
  pixel.
  """
  def png(<<137, "PNG", 13, 10, 26, 10, chunks::binary>>) do
    parts = chunks(chunks)
    <<w::32, h::32, 8, type, 0, 0, 0>> = parts["IHDR"]
    n = if type == 6, do: 4, else: 3
    raw = :zlib.uncompress(parts["IDAT"])
    rows = for y <- 0..(h - 1), do: binary_part(raw, y * (w * n + 1), w * n + 1)

    {lines, _} =
      Enum.map_reduce(rows, :binary.copy(<<0>>, w * n), fn <<filter, line::binary>>, above ->
        out = unfilter(filter, line, above, n)
        {out, out}
      end)

    lines = List.to_tuple(lines)
    {w, h, fn x, y -> {:binary.at(elem(lines, y), x * n), :binary.at(elem(lines, y), x * n + 1), :binary.at(elem(lines, y), x * n + 2)} end}
  end

  defp chunks(<<len::32, type::binary-4, data::binary-size(len), _crc::32, rest::binary>>),
    do: Map.update(chunks(rest), type, data, &(data <> &1))

  defp chunks(<<>>), do: %{}

  # The bytes of a line from its filter (PNG: None, Sub, Up, Average,
  # Paeth), the line above, and the bytes in a pixel.
  defp unfilter(filter, line, above, n) do
    {out, _} =
      line
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.reduce({[], {}}, fn {x, i}, {acc, _} ->
        a = if i >= n, do: Enum.at(acc, n - 1), else: 0
        b = :binary.at(above, i)
        c = if i >= n, do: :binary.at(above, i - n), else: 0

        v =
          case filter do
            0 -> x
            1 -> x + a
            2 -> x + b
            3 -> x + div(a + b, 2)
            4 -> x + paeth(a, b, c)
          end

        {[rem(v, 256) | acc], {}}
      end)

    out |> Enum.reverse() |> :binary.list_to_bin()
  end

  defp paeth(a, b, c) do
    p = a + b - c
    {pa, pb, pc} = {abs(p - a), abs(p - b), abs(p - c)}

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end
end

[input, output, source, license | rest] = System.argv()
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

geometry = Enum.find(objects, &(elem(&1, 0) == "Geometry"))
vertices = value.(geometry, "Vertices") |> Enum.chunk_every(3) |> Enum.map(&List.to_tuple/1)

faces =
  value.(geometry, "PolygonVertexIndex")
  |> Enum.chunk_while([], fn i, acc -> if i < 0, do: {:cont, Enum.reverse([-i - 1 | acc]), []}, else: {:cont, [i | acc]} end, fn acc -> {:cont, acc} end)

clusters =
  for {"Deformer", [id, _, "Cluster" | _], _} = n <- objects,
      bone = Enum.find_value(links, fn {a, b} -> if b == id and Map.has_key?(models, a), do: models[a].name end),
      do: %{
        bone: bone,
        indexes: value.(n, "Indexes") || [],
        weights: value.(n, "Weights") || [],
        link: value.(n, "TransformLink"),
        transform: value.(n, "Transform")
      }

# A bone with no weight and no bone with weights under it (a target of
# inverse kinematics of the file) stays out.
weighted = for c <- clusters, c.indexes != [], into: MapSet.new(), do: c.bone
up = fn name -> parent[by_name[name]] && models[parent[by_name[name]]].name end
keep = for c <- clusters, Enum.any?(weighted, fn w -> Stream.iterate(w, up) |> Enum.take_while(& &1) |> Enum.member?(c.bone) end), into: MapSet.new(), do: c.bone
clusters = Enum.filter(clusters, &(&1.bone in keep))

# The product of two matrices of 16 numbers (columns first).
times = fn a, b ->
  {a, b} = {List.to_tuple(a), List.to_tuple(b)}
  for c <- 0..3, r <- 0..3, do: Enum.sum(for k <- 0..3, do: elem(a, k * 4 + r) * elem(b, c * 4 + k))
end

[c | _] = Enum.filter(clusters, & &1.transform)
points = Enum.map(vertices, &point.(times.(c.link, c.transform), &1))
heads = Map.new(clusters, &{&1.bone, point.(&1.link, {0.0, 0.0, 0.0})})

# The end node of a bone (a child with no cluster): its point in the
# frame of the bone.
tails =
  for c <- clusters,
      kid = Enum.find(Map.keys(parent), fn k -> parent[k] == by_name[c.bone] and not Map.has_key?(heads, models[k].name) end),
      kid != nil,
      into: %{},
      do: {c.bone, point.(c.link, List.to_tuple(Map.get(models[kid].props, "Lcl Translation", [0.0, 0.0, 0.0])))}

# The axes of World; the units / 100; the ground at z = 0 and the middle
# at x = 0, y = 0.
{_, _, settings} = child.({nil, nil, section.("GlobalSettings")}, "Properties70")
setting = fn name -> Enum.find_value(settings, fn {_, [k | v], _} -> if k == name, do: List.last(v) end) end
axis = fn i, sign -> List.to_tuple(for j <- 0..2, do: if(i == j, do: sign * 1.0, else: 0.0)) end
up = axis.(setting.("UpAxis"), setting.("UpAxisSign"))
{sign, name} = case rest do
  ["-" <> a] -> {-1, a}
  [a] -> {1, a}
  [] -> {1, "x"}
end
front = axis.(Enum.find_index(~w(x y z), &(&1 == name)), sign)
right = World.Vec.cross(front, up)
turn = fn p -> {World.Vec.dot(p, right) / 100, World.Vec.dot(p, front) / 100, World.Vec.dot(p, up) / 100} end
world = Enum.map(points, turn)
{{x0, y0, z0}, {x1, y1, _}} = World.Vec.bounds(world)
shift = fn p -> World.Vec.sub(turn.(p), {(x0 + x1) / 2, (y0 + y1) / 2, z0}) end
round = fn {x, y, z} -> Enum.map([x, y, z], &Float.round(&1, 5)) end

# The material of each face: the materials of the mesh in the order of
# their links to its model, and the index of the material of each face.
# A material with a texture (its diffuse color) is a few materials: the
# colors of the texture at the middles of its faces (in the coordinates
# of the texture, each in its tile), in groups of near colors (k-means,
# 3 groups).
mesh_id = Enum.find_value(links, fn {a, b} -> if a == hd(elem(geometry, 1)), do: b end)
object = fn id -> Enum.find(objects, &match?({_, [^id | _], _}, &1)) end
material_ids = for {a, b} <- links, b == mesh_id, match?({"Material", _, _}, object.(a)), do: a

face_materials =
  case child.(geometry, "LayerElementMaterial") do
    nil -> List.duplicate(0, length(faces))
    layer -> if value.(layer, "MappingInformationType") == "AllSame", do: List.duplicate(hd(value.(layer, "Materials")), length(faces)), else: value.(layer, "Materials")
  end

texture = fn id ->
  Enum.find_value(section.("Connections"), fn
    {"C", ["OP", t, ^id, "DiffuseColor"], _} -> t
    _ -> nil
  end)
  |> case do
    nil -> nil
    t -> t |> object.() |> value.("FileName") |> String.split(["/", "\\"]) |> List.last() |> then(&Path.join(Path.dirname(input), &1))
  end
end

uvs =
  case child.(geometry, "LayerElementUV") do
    nil -> nil
    layer -> {value.(layer, "UV") |> Enum.chunk_every(2) |> List.to_tuple(), value.(layer, "UVIndex")}
  end

# The coordinates of the texture at the middle of each face.
middles =
  if uvs do
    {table, index} = uvs
    {mids, _} = Enum.map_reduce(faces, index, fn f, left -> {here, more} = Enum.split(left, length(f)); {here |> Enum.map(&elem(table, &1)) |> Enum.zip_with(&(Enum.sum(&1) / length(f))), more} end)
    mids
  end

kmeans = fn colors, k ->
  start = colors |> Enum.uniq() |> Enum.sort() |> then(&Enum.take_every(&1, max(div(length(&1), k), 1))) |> Enum.take(k)
  dist = fn {a, b, c}, {d, e, f} -> (a - d) ** 2 + (b - e) ** 2 + (c - f) ** 2 end
  near = fn centers, c -> centers |> Enum.with_index() |> Enum.min_by(fn {m, _} -> dist.(m, c) end) |> elem(1) end

  Enum.reduce(1..20, start, fn _, centers ->
    groups = Enum.group_by(colors, &near.(centers, &1))
    for {m, i} <- Enum.with_index(centers), do: (case groups[i] do
      nil -> m
      g -> Enum.reduce(g, {0, 0, 0}, fn {a, b, c}, {d, e, f} -> {a + d, b + e, c + f} end) |> then(fn {a, b, c} -> {a / length(g), b / length(g), c / length(g)} end)
    end)
  end)
  |> then(&{&1, near})
end

{materials, face_materials} =
  material_ids
  |> Enum.with_index()
  |> Enum.reduce({[], face_materials}, fn {id, i}, {list, fms} ->
    name = clean.(elem(object.(id), 1) |> Enum.at(1))
    file = texture.(id)

    if file && middles && File.exists?(file) do
      {w, h, pixel} = FBXFigure.png(File.read!(file))
      at = fn [u, v] -> pixel.(min(trunc((u - Float.floor(u)) * w), w - 1), min(trunc((1 - (v - Float.floor(v))) * h), h - 1)) end
      mine = for {{m, mid}, f} <- Enum.with_index(Enum.zip(fms, middles)), m == i, do: {f, at.(mid)}
      {centers, near} = kmeans.(Enum.map(mine, &elem(&1, 1)), 3)
      base = length(list)
      own = Map.new(mine, fn {f, c} -> {f, {:at, base + near.(centers, c)}} end)
      added = for {c, k} <- Enum.with_index(centers), do: %{"name" => "#{name}.#{k}", "color" => c |> Tuple.to_list() |> Enum.map(&round/1)}
      {list ++ added, fms |> Enum.with_index() |> Enum.map(fn {m, f} -> Map.get(own, f, if(m == i, do: {:at, base}, else: m)) end)}
    else
      {list ++ [%{"name" => name}], Enum.map(fms, fn m -> if m == i, do: {:at, length(list)}, else: m end)}
    end
  end)

face_materials = Enum.map(face_materials, fn {:at, m} -> m; m -> m end)

# The bones, parents first.
names = Enum.map(clusters, & &1.bone)
bone_parent = fn name -> with id when id != nil <- parent[by_name[name]], do: if(models[id].name in names, do: models[id].name) end
ordered = Enum.sort_by(names, fn name -> Stream.iterate(name, bone_parent) |> Enum.take_while(& &1) |> length() end)

data = %{
  "source" => source,
  "license" => license,
  "points" => Enum.map(points, &round.(shift.(&1))),
  "faces" => faces,
  "materials" => materials,
  "face_materials" => face_materials,
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
