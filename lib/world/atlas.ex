defmodule World.Atlas do
  @moduledoc """
  One set of images for many materials (plan 0020, D12 and D13): the
  images of the bakes of the parts of a model (an order with `"atlas":
  true`), or of all the models of a set (`POST /sets` with `"atlas":
  true`), in one color image, one normal image, one finish image and
  one glow image.

  - **The materials.** A material with the images of a bake (`World.Sculpt.Bake`:
    an image of color with no repeat, and its other maps of the same side)
    goes into the atlas. The materials with the same other values (the
    color, the occlusion, the alpha) become one material: a game draws
    their primitives in one call. A part with no glow image has black
    there (no light), with no normal image a flat normal, with no finish
    image its roughness and its metal (the factors of the material are
    then 1). Another material (a texture that repeats, a photo, a plain
    color) stays as it is.
  - **The places.** Each image is a square with a side of a power of 2.
    The squares go into the atlas, the largest first, each in a free
    square of its own size at a multiple of its side (a buddy
    allocation): so a level of the mipmaps of the atlas never mixes the
    texels of two images, and the fill of the empty texels of each image
    (issue #43) stays at its border. The atlas is the smallest square of
    a side of a power of 2 that holds them. Over #{8192} texels on a
    side, each image goes to half of its side (the mean of 2 by 2 texels),
    until they fit.
  - **The UVs.** The UV of each point of a primitive of such a material
    goes to the place of its image in the atlas.
  - **The primitives.** In a node, the primitives of one material with
    the same attributes become one primitive.
  """
  import Bitwise

  alias World.Scene
  alias World.Scene.Primitive

  # The maps of a bake, the most texels on a side of an atlas, and the
  # value of a texel of each map where a material has no image of it.
  @maps ~w(image normal_image finish_image glow_image)
  @flat {128, 128, 255}

  @doc "The names of the maps in the names of the files of the images of a set (`/s/SET.color.png`)."
  def names, do: %{"image" => "color", "normal_image" => "normal", "finish_image" => "finish", "glow_image" => "glow"}

  # (The most texels on a side: 8192, the size that each GPU of a desktop and a phone of today takes.)
  defp most, do: Application.get_env(:world, :atlas_most, 8192)

  @doc """
  The scene of one model with its images in one atlas (`"atlas": true`
  of an order): the images are in the GLB. `images: "ktx2"` writes them
  as KTX2 (`World.KTX2`).
  """
  def scene(%Scene{} = scene, opts \\ []) do
    {[scene], _images} = scenes([scene], opts)
    scene
  end

  @doc """
  The scenes of a set with their images in one atlas: `{scenes, images}`,
  `images` a map of each map of the atlas (`"image"`, `"normal_image"`,
  `"finish_image"`, `"glow_image"`) to `{mime, bytes}`. With `uri` (a
  function of the name of a map and its extension, `"png"` or `"ktx2"`),
  the materials of the scenes refer to the images by that URL, and the
  GLB files have no image of their own; else the images are in each GLB.
  """
  def scenes(scenes, opts \\ []) do
    ktx2? = Keyword.get(opts, :images) == "ktx2"
    uri = Keyword.get(opts, :uri)

    # The materials of a bake of each scene, by a key of their own: {scene, role}.
    members =
      for {scene, k} <- Enum.with_index(scenes),
          {role, spec} <- Enum.sort_by(scene.materials, &to_string(elem(&1, 0))),
          baked?(spec),
          do: {{k, role}, spec}

    if members == [] do
      {scenes, %{}}
    else
      {members, side, places} = place(members)
      # (The place of the square of each material: the materials with the same images share one.)
      spots = Map.new(members, fn {key, spec} -> {key, places[look(spec)]} end)
      groups = groups(members)
      maps = for m <- @maps, m == "image" or Enum.any?(members, fn {_, spec} -> spec[m] end), do: m
      images = Map.new(maps, &{&1, compose(&1, members, places, side)})

      images =
        if ktx2?,
          do: Map.new(images, fn {m, png} -> {m, {"image/ktx2", ktx2(m, png)}} end),
          else: Map.new(images, fn {m, png} -> {m, {"image/png", png}} end)

      file = fn m ->
        case {uri, images[m]} do
          {nil, file} -> file
          {uri, {mime, _}} -> {:uri, uri.(m, if(mime == "image/ktx2", do: "ktx2", else: "png")), mime}
        end
      end

      scenes =
        for {scene, k} <- Enum.with_index(scenes) do
          mine = for {{^k, role}, _} <- members, into: %{}, do: {role, Map.fetch!(groups, {k, role})}

          materials =
            scene.materials
            |> Map.drop(Map.keys(mine))
            |> Map.merge(
              for {{^k, role}, spec} <- members, into: %{} do
                {mine[role], material(spec, maps, file)}
              end
            )

          nodes =
            for n <- scene.nodes do
              prims =
                for p <- n.primitives do
                  case mine[p.material] do
                    nil -> p
                    group -> %{p | material: group, uvs: moved(p.uvs, spots[{k, p.material}], side)}
                  end
                end

              %{n | primitives: merge(prims)}
            end

          %{scene | materials: materials, nodes: nodes}
        end

      {scenes, images}
    end
  end

  # A material of a bake: an image of color in PNG with no repeat and no
  # transform, and each other map (when it has one) of the same side.
  defp baked?(spec) do
    case spec["image"] do
      {"image/png", png} ->
        side = side(png)

        side != nil and
          not Enum.any?(~w(image_transform image_scale normal_image_scale panel texture), &Map.has_key?(spec, &1)) and
          Enum.all?(tl(@maps), fn m ->
            spec[m] == nil or (match?({"image/png", _}, spec[m]) and side(elem(spec[m], 1)) == side)
          end)

      _ ->
        false
    end
  end

  defp side(png) do
    <<137, "PNG", _::binary-12, w::32, h::32, _::binary>> = png
    if w == h and (w &&& w - 1) == 0, do: w, else: nil
  end

  # The place of the square of the images of each material: `{members,
  # side, places}`, the members with their images at half of their side
  # when the atlas is over the most, the side of the atlas, and the corner
  # and the side of the square of each set of images (`{x, y, s}`, by
  # `look/1`).
  defp place(members) do
    sides = for {_, spec} <- members, into: %{}, do: {look(spec), side(elem(spec["image"], 1))}

    case pack(sides) do
      {:ok, side, places} -> {members, side, Map.new(places, fn {key, {x, y}} -> {key, {x, y, sides[key]}} end)}
      :over -> place(for {key, spec} <- members, do: {key, halve(spec)})
    end
  end

  @doc """
  The places of squares with a side of a power of 2 (a map of a key to
  its side) in the smallest square of a side of a power of 2 that holds
  them: `{:ok, side, places}` (a map of each key to its corner `{x, y}`,
  each at a multiple of its side), or `:over` when the side is over
  8192. The largest go first, then by their keys.
  """
  def pack(sides) do
    order = Enum.sort_by(sides, fn {key, s} -> {-s, key} end)
    area = Enum.sum(for {_, s} <- order, do: s * s)

    side =
      Enum.reduce_while(Stream.iterate(elem(hd(order), 1), &(&1 * 2)), nil, fn s, _ ->
        if s * s >= area, do: {:halt, s}, else: {:cont, nil}
      end)

    if side > most() do
      :over
    else
      # (A buddy allocation: the free squares of each side, from the top left.)
      {places, _free} =
        Enum.map_reduce(order, %{side => [{0, 0}]}, fn {key, s}, free ->
          {corner, free} = take(free, s, side)
          {{key, corner}, free}
        end)

      {:ok, side, Map.new(places)}
    end
  end

  # A free square of a side: the first free one of that side, or a larger one cut in four.
  defp take(free, s, side) do
    case Map.get(free, s, []) do
      [corner | rest] ->
        {corner, Map.put(free, s, rest)}

      [] ->
        {{x, y}, free} = take(free, s * 2, side)
        quarters = [{x + s, y}, {x, y + s}, {x + s, y + s}]
        {{x, y}, Map.update(free, s, quarters, &(&1 ++ quarters))}
    end
  end

  # The images of a material, and its finish when it has no image of it:
  # two materials with the same look have the same texels in the atlas.
  defp look(spec),
    do: {Map.take(spec, @maps), if(spec["finish_image"], do: nil, else: {spec["roughness"], spec["metalness"]})}

  # Each material with the others of the same values in one group: the
  # role of the group (`:atlas`, `:atlas_2`, ...), by the first of its keys.
  defp groups(members) do
    by = Enum.group_by(members, fn {_, spec} -> rest(spec) end, &elem(&1, 0))
    firsts = by |> Enum.map(fn {_, keys} -> keys end) |> Enum.sort_by(&hd/1)

    for {keys, i} <- Enum.with_index(firsts), key <- keys, into: %{} do
      {key, if(i == 0, do: :atlas, else: :"atlas_#{i + 1}")}
    end
  end

  # The values of a material with no images (its finish goes into the finish image).
  defp rest(spec), do: Map.drop(spec, @maps ++ ~w(roughness metalness atlas))

  # The material of a group: its values, and the maps of the atlas (its factors of roughness and metal 1).
  defp material(spec, maps, file) do
    spec
    |> rest()
    |> Map.merge(%{"roughness" => 1.0, "metalness" => 1.0, "atlas" => true})
    |> Map.merge(Map.new(maps, &{&1, file.(&1)}))
  end

  # The image of a map of the atlas: each square at its place, and the
  # value of a material with no image of that map.
  defp compose(map, members, places, side) do
    channels =
      if map == "image" and Enum.any?(members, fn {_, spec} -> channels(spec["image"]) == 4 end), do: 4, else: 3

    squares =
      for {_, spec} <- Enum.uniq_by(members, &look(elem(&1, 1))) do
        {x, y, s} = places[look(spec)]
        {x, y, s, rows(spec, map, s, channels)}
      end

    blank = pixel(if(map == "normal_image", do: @flat, else: {0, 0, 0}), channels)

    rows =
      for row <- 0..(side - 1) do
        # (The squares on this row, from the left, and the blank between them.)
        parts = for {x, y, s, rows} <- squares, row >= y and row < y + s, do: {x, s, elem(rows, row - y)}

        {line, at} =
          parts
          |> Enum.sort()
          |> Enum.reduce({[], 0}, fn {x, s, bytes}, {acc, at} -> {[bytes, :binary.copy(blank, x - at) | acc], x + s} end)

        IO.iodata_to_binary(Enum.reverse([:binary.copy(blank, side - at) | line]))
      end

    World.PNG.encode(rows, channels)
  end

  defp channels({_, png}), do: elem(World.PNG.decode(png), 2)

  # The rows of the image of a map of a material, with `channels`; with no image, its value.
  defp rows(spec, map, side, channels) do
    case spec[map] do
      {_, png} ->
        {_, _, c, rows} = World.PNG.decode(png)
        if c == channels, do: rows, else: rows |> Tuple.to_list() |> Enum.map(&rgba(&1, c, channels)) |> List.to_tuple()

      nil ->
        value =
          case map do
            "normal_image" ->
              @flat

            "glow_image" ->
              {0, 0, 0}

            "finish_image" ->
              {255, round(Map.get(spec, "roughness", 0.6) * 255), round(Map.get(spec, "metalness", 0.0) * 255)}
          end

        List.to_tuple(List.duplicate(:binary.copy(pixel(value, channels), side), side))
    end
  end

  defp pixel({r, g, b}, 3), do: <<r, g, b>>
  defp pixel({r, g, b}, 4), do: <<r, g, b, 255>>

  defp rgba(row, 3, 4), do: for(<<r, g, b <- row>>, into: <<>>, do: <<r, g, b, 255>>)

  # A material with each of its images at half of its side.
  defp halve(spec) do
    Map.new(spec, fn
      {m, {"image/png", png}} when m in @maps ->
        {w, h, c, rows} = World.PNG.decode(png)
        {m, {"image/png", World.PNG.encode(half(rows, w, h, c), c)}}

      other ->
        other
    end)
  end

  defp half(rows, w, h, c) do
    for y <- 0..(div(h, 2) - 1) do
      {r0, r1} = {elem(rows, 2 * y), elem(rows, 2 * y + 1)}

      for x <- 0..(div(w, 2) - 1), k <- 0..(c - 1), into: <<>> do
        s =
          :binary.at(r0, 2 * x * c + k) + :binary.at(r0, (2 * x + 1) * c + k) + :binary.at(r1, 2 * x * c + k) +
            :binary.at(r1, (2 * x + 1) * c + k)

        <<(s + 2) >>> 2>>
      end
    end
  end

  # The UVs of a primitive in the square of its image in the atlas.
  defp moved(nil, _corner, _side), do: nil

  defp moved(uvs, {x, y, s}, side), do: for({u, v} <- uvs, do: {(x + u * s) / side, (y + v * s) / side})

  # The images of KTX2: the color and the glow in sRGB, the normal and the finish linear.
  defp ktx2(map, png), do: World.KTX2.from_png(png, srgb: map in ~w(image glow_image))

  @doc """
  The scene with each image of its materials as KTX2 (`"images": "ktx2"`
  of an order with no atlas, `World.KTX2`): each map of PNG of RGB or
  RGBA whose sides are multiples of 4 (a GPU format has blocks of 4 by 4
  texels). An image that two materials share is made one time.
  """
  def ktx2(%Scene{} = scene) do
    {materials, _made} =
      Enum.map_reduce(Enum.sort_by(scene.materials, &to_string(elem(&1, 0))), %{}, fn {role, spec}, made ->
        {spec, made} =
          Enum.reduce(@maps, {spec, made}, fn m, {spec, made} ->
            with {"image/png", png} <- spec[m], true <- packable?(png) do
              key = {m in ~w(image glow_image), png}
              made = Map.put_new_lazy(made, key, fn -> ktx2(m, png) end)
              {Map.put(spec, m, {"image/ktx2", made[key]}), made}
            else
              _ -> {spec, made}
            end
          end)

        {{role, spec}, made}
      end)

    %{scene | materials: Map.new(materials)}
  end

  # An image of RGB or RGBA (the type 2 or 6 of its header) with sides that are multiples of 4.
  defp packable?(<<137, "PNG", _::binary-12, w::32, h::32, depth, type, _::binary>>),
    do: depth == 8 and type in [2, 6] and rem(w, 4) == 0 and rem(h, 4) == 0

  # The primitives of a node: those of one material with the same attributes become one.
  defp merge(prims) do
    prims
    |> Enum.chunk_by(&{&1.material, shape(&1)})
    |> Enum.flat_map(fn
      [one] -> [one]
      many -> if mergeable?(hd(many)), do: [join(many)], else: many
    end)
  end

  defp shape(%Primitive{} = p),
    do: {p.uvs != nil, p.colors != nil, p.finish != nil, p.uvs2 != nil, p.data != nil, p.joints != nil, p.fur != nil}

  defp mergeable?(%Primitive{} = p), do: p.joints == nil and p.targets == nil and p.fur == nil

  defp join(prims) do
    prims = Enum.map(prims, &Scene.unpack/1)

    {indices, _} =
      Enum.flat_map_reduce(prims, 0, fn p, base -> {Enum.map(p.indices, &(&1 + base)), base + length(p.positions)} end)

    cat = fn field -> if Map.get(hd(prims), field), do: Enum.flat_map(prims, &Map.fetch!(&1, field)) end

    %{
      hd(prims)
      | positions: cat.(:positions),
        normals: cat.(:normals),
        indices: indices,
        uvs: cat.(:uvs),
        colors: cat.(:colors),
        finish: cat.(:finish),
        uvs2: cat.(:uvs2),
        data: cat.(:data)
    }
  end
end
