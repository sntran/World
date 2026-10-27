defmodule Xuong.GLB do
  @moduledoc """
  The writer of GLB (glTF 2.0, binary) for a `Xuong.Scene`.

  - The axes: a point (x, y, z) of Xưởng is (-x, z, y) in glTF: +Y up and
    the front to +Z. This is a turn, not a mirror, so each triangle keeps
    the order of its corners.
  - One glTF material for each role, from `priv/palette.json` or from the
    `materials` of the scene. Its name is its role.
  - The same scene gives the same bytes.
  """
  alias Xuong.{Frame, Scene}

  @external_resource palette_path = Path.join([__DIR__, "..", "..", "priv", "palette.json"])
  @palette palette_path |> File.read!() |> JSON.decode!() |> Map.fetch!("roles")

  @doc "The palette: a map of each role to its color, roughness and metalness."
  def palette, do: @palette

  @doc "The GLB of a scene, as a binary."
  def encode(%Scene{} = scene) do
    {json, bin} = gltf(scene)
    json_bin = pad(JSON.encode!(json), " ")
    bin = pad(bin, <<0>>)
    total = 12 + 8 + byte_size(json_bin) + if(bin == <<>>, do: 0, else: 8 + byte_size(bin))

    chunk_bin = if bin == <<>>, do: <<>>, else: <<byte_size(bin)::little-32, "BIN", 0, bin::binary>>

    <<"glTF", 2::little-32, total::little-32, byte_size(json_bin)::little-32, "JSON", json_bin::binary,
      chunk_bin::binary>>
  end

  @doc "Write the GLB of a scene to a file."
  def write!(path, %Scene{} = scene) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encode(scene))
  end

  # --- The JSON and the buffer ------------------------------------------------

  defp gltf(%Scene{nodes: nodes} = scene) do
    roles = nodes |> Enum.flat_map(& &1.primitives) |> Enum.map(& &1.material) |> Enum.uniq() |> Enum.sort()
    mat_index = roles |> Enum.with_index() |> Map.new()
    buf = %{bin: <<>>, views: [], accessors: [], images: []}

    {meshes, node_mesh, buf} =
      nodes
      |> Enum.with_index()
      |> Enum.reduce({[], %{}, buf}, fn
        {%{primitives: []}, _i}, acc ->
          acc

        {node, i}, {meshes, map, buf} ->
          {prims, buf} = Enum.map_reduce(node.primitives, buf, &primitive(&1, &2, mat_index))
          {[%{"name" => node.name, "primitives" => prims} | meshes], Map.put(map, i, length(meshes)), buf}
      end)

    {skins, buf} = Enum.map_reduce(scene.skins, buf, &skin/2)
    {animations, buf} = Enum.map_reduce(scene.animations, buf, &animation/2)
    {materials, buf} = Enum.map_reduce(roles, buf, &material(&1, &2, scene.materials))

    children =
      nodes
      |> Enum.with_index()
      |> Enum.filter(&(elem(&1, 0).parent != nil))
      |> Enum.group_by(&elem(&1, 0).parent, &elem(&1, 1))

    roots = for {n, i} <- Enum.with_index(nodes), n.parent == nil, do: i

    json_nodes =
      for {n, i} <- Enum.with_index(nodes) do
        {qx, qy, qz, qw} = Frame.quaternion(gl_frame(n.frame))

        %{"name" => n.name, "translation" => tuple3(gl(n.frame.at)), "rotation" => [qx, qy, qz, qw]}
        |> put_some("mesh", node_mesh[i])
        |> put_some("children", children[i])
        |> put_some("skin", n.skin)
        |> put_some("extras", if(n.extras == %{}, do: nil, else: n.extras))
      end

    json =
      %{
        "asset" => %{"version" => "2.0", "generator" => "Xuong"},
        "scene" => 0,
        "scenes" => [
          %{"name" => scene.name, "nodes" => roots}
          |> put_some("extras", if(scene.extras == %{}, do: nil, else: scene.extras))
        ],
        "nodes" => json_nodes,
        "materials" => materials
      }
      |> put_some("meshes", nonempty(Enum.reverse(meshes)))
      |> put_some("skins", nonempty(skins))
      |> put_some("animations", nonempty(animations))
      |> put_some("images", nonempty(Enum.reverse(buf.images)))
      |> put_some("textures", nonempty(for {_, i} <- Enum.with_index(buf.images), do: %{"source" => i, "sampler" => 0}))
      |> put_some("samplers", if(buf.images == [], do: nil, else: [%{"magFilter" => 9729, "minFilter" => 9987}]))
      |> put_some("accessors", nonempty(Enum.reverse(buf.accessors)))
      |> put_some("bufferViews", nonempty(Enum.reverse(buf.views)))
      |> put_some("buffers", if(buf.bin == <<>>, do: nil, else: [%{"byteLength" => byte_size(pad(buf.bin, <<0>>))}]))

    {json, buf.bin}
  end

  defp primitive(%Scene.Primitive{} = p, buf, mat_index) do
    {pos, buf} = floats(buf, Enum.map(p.positions, &gl/1), "VEC3", 34962, true)
    {nor, buf} = floats(buf, Enum.map(p.normals, &gl/1), "VEC3", 34962, false)
    attrs = %{"POSITION" => pos, "NORMAL" => nor}

    {attrs, buf} =
      if p.uvs, do: with_attr(attrs, "TEXCOORD_0", floats(buf, p.uvs, "VEC2", 34962, false)), else: {attrs, buf}

    {attrs, buf} =
      if p.joints, do: with_attr(attrs, "JOINTS_0", ushorts(buf, p.joints)), else: {attrs, buf}

    {attrs, buf} =
      if p.weights, do: with_attr(attrs, "WEIGHTS_0", floats(buf, p.weights, "VEC4", 34962, false)), else: {attrs, buf}

    {ind, buf} = indices(buf, p.indices, length(p.positions))
    {%{"attributes" => attrs, "indices" => ind, "material" => Map.fetch!(mat_index, p.material)}, buf}
  end

  defp with_attr(attrs, key, {acc, buf}), do: {Map.put(attrs, key, acc), buf}

  defp skin(%{joints: joints, inverse_bind: frames} = s, buf) do
    mats = for f <- frames, do: Frame.matrix(gl_frame(f))
    {acc, buf} = matrices(buf, mats)

    {%{"joints" => joints, "inverseBindMatrices" => acc}
     |> put_some("skeleton", Map.get(s, :skeleton))
     |> put_some("name", Map.get(s, :name)), buf}
  end

  # An animation: channels of rotations (frames) or translations (points)
  # of nodes, at times in seconds.
  defp animation(%{name: name, channels: channels}, buf) do
    {pairs, buf} =
      channels
      |> Enum.with_index()
      |> Enum.map_reduce(buf, fn {%{node: node, path: path, times: times, values: values}, i}, buf ->
        {input, buf} = scalars(buf, times)

        {output, buf} =
          case path do
            :rotation -> floats(buf, for(f <- values, do: Frame.quaternion(gl_frame(f))), "VEC4", nil, false)
            :translation -> floats(buf, Enum.map(values, &gl/1), "VEC3", nil, false)
          end

        {{%{"input" => input, "output" => output, "interpolation" => "LINEAR"},
          %{"sampler" => i, "target" => %{"node" => node, "path" => Atom.to_string(path)}}}, buf}
      end)

    {%{"name" => name, "samplers" => Enum.map(pairs, &elem(&1, 0)), "channels" => Enum.map(pairs, &elem(&1, 1))}, buf}
  end

  defp material(role, buf, overrides) do
    spec =
      Map.get(overrides, role) || Map.get(@palette, Atom.to_string(role)) ||
        %{"color" => [154, 161, 170], "roughness" => 0.6, "metalness" => 0.0}

    spec = Map.new(spec, fn {k, v} -> {to_string(k), v} end)
    [r, g, b] = spec["color"]
    color = for c <- [r, g, b], do: Float.round(srgb_to_linear(c / 255), 5)

    alpha = Map.get(spec, "alpha", 1.0) / 1

    pbr = %{
      "baseColorFactor" => color ++ [alpha],
      "roughnessFactor" => spec["roughness"] / 1,
      "metallicFactor" => spec["metalness"] / 1
    }

    {pbr, buf} =
      case spec["image"] do
        nil ->
          {pbr, buf}

        {mime, data} ->
          view = length(buf.views)
          buf = add_view(buf, data, nil)
          image = length(buf.images)

          {Map.merge(pbr, %{"baseColorFactor" => [1.0, 1.0, 1.0, 1.0], "baseColorTexture" => %{"index" => image}}),
           %{buf | images: [%{"bufferView" => view, "mimeType" => mime} | buf.images]}}
      end

    material = %{
      "name" => Atom.to_string(role),
      "pbrMetallicRoughness" => pbr,
      "doubleSided" => Map.get(spec, "double_sided", false)
    }

    # Glass shows what is behind it.
    {if(alpha < 1.0, do: Map.put(material, "alphaMode", "BLEND"), else: material), buf}
  end

  defp srgb_to_linear(c) when c <= 0.04045, do: c / 12.92
  defp srgb_to_linear(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  # --- Accessors ---------------------------------------------------------------

  defp floats(buf, vals, type, target, bounds?) do
    data = for v <- vals, x <- Tuple.to_list(v), into: <<>>, do: <<x::little-float-32>>
    n = tuple_size(hd(vals))
    acc = %{"componentType" => 5126, "count" => length(vals), "type" => type}

    acc =
      if bounds? do
        cols = for k <- 0..(n - 1), do: Enum.map(vals, &f32(elem(&1, k)))
        Map.merge(acc, %{"min" => Enum.map(cols, &Enum.min/1), "max" => Enum.map(cols, &Enum.max/1)})
      else
        acc
      end

    add_accessor(buf, data, target, acc)
  end

  defp scalars(buf, times) do
    data = for t <- times, into: <<>>, do: <<t / 1::little-float-32>>
    ts = Enum.map(times, &f32(&1 / 1))

    add_accessor(buf, data, nil, %{
      "componentType" => 5126,
      "count" => length(times),
      "type" => "SCALAR",
      "min" => [Enum.min(ts)],
      "max" => [Enum.max(ts)]
    })
  end

  defp ushorts(buf, vals) do
    data = for v <- vals, x <- Tuple.to_list(v), into: <<>>, do: <<x::little-16>>
    add_accessor(buf, data, 34962, %{"componentType" => 5123, "count" => length(vals), "type" => "VEC4"})
  end

  defp matrices(buf, mats) do
    data = for m <- mats, x <- m, into: <<>>, do: <<x / 1::little-float-32>>
    add_accessor(buf, data, nil, %{"componentType" => 5126, "count" => length(mats), "type" => "MAT4"})
  end

  defp indices(buf, idx, count) do
    {data, type} =
      if count <= 65_535,
        do: {for(i <- idx, into: <<>>, do: <<i::little-16>>), 5123},
        else: {for(i <- idx, into: <<>>, do: <<i::little-32>>), 5125}

    add_accessor(buf, data, 34963, %{"componentType" => type, "count" => length(idx), "type" => "SCALAR"})
  end

  defp add_accessor(buf, data, target, acc) do
    view = length(buf.views)
    buf = add_view(buf, data, target)
    {length(buf.accessors), %{buf | accessors: [Map.put(acc, "bufferView", view) | buf.accessors]}}
  end

  defp add_view(buf, data, target) do
    bin = pad(buf.bin, <<0>>)
    view = put_some(%{"buffer" => 0, "byteOffset" => byte_size(bin), "byteLength" => byte_size(data)}, "target", target)
    %{buf | bin: bin <> data, views: [view | buf.views]}
  end

  # --- The axes of glTF --------------------------------------------------------

  @doc "A point or a direction in the axes of glTF."
  def gl({x, y, z}), do: {-x, z, y}

  @doc "A frame in the axes of glTF."
  def gl_frame(%Frame{x: x, y: y, z: z, at: at}),
    do: %Frame{x: Xuong.Vec.neg(gl(x)), y: gl(z), z: gl(y), at: gl(at)}

  defp tuple3({x, y, z}), do: [x, y, z]

  defp f32(x),
    do:
      (
        <<y::little-float-32>> = <<x::little-float-32>>
        y
      )

  defp nonempty([]), do: nil
  defp nonempty(list), do: list
  defp put_some(map, _key, nil), do: map
  defp put_some(map, key, value), do: Map.put(map, key, value)

  defp pad(bin, byte) do
    case rem(byte_size(bin), 4) do
      0 -> bin
      r -> bin <> :binary.copy(byte, 4 - r)
    end
  end
end
