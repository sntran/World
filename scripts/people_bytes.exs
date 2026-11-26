# The bytes of a person for the projects (plan 0021, R7): one person (a man of 35, as a project orders him) at mid
# and at far, by part (the JSON, the mesh, the skin, the clips, the pictures), with no clip, with the walks, and with
# the routines; and a set of six people, each GLB alone and with one atlas of their pictures (plan 0020, step 4).
#
#   MIX_ENV=test mix run scripts/people_bytes.exs

# The bytes of each part of a GLB: each buffer view counts one time, in the first part that uses it.
parts = fn bin ->
  <<"glTF", 2::little-32, _total::little-32, length::little-32, "JSON", json::binary-size(length), rest::binary>> = bin
  j = JSON.decode!(json)
  data = with <<n::little-32, "BIN", 0, _::binary>> <- rest, do: n, else: (_ -> 0)
  views = j["bufferViews"] || []
  view = fn a -> Enum.at(j["accessors"], a)["bufferView"] end

  mesh =
    for m <- j["meshes"] || [],
        p <- m["primitives"],
        a <- Map.values(p["attributes"]) ++ List.wrap(p["indices"]) ++ Enum.flat_map(p["targets"] || [], &Map.values/1),
        do: view.(a)

  skin = for s <- j["skins"] || [], a <- List.wrap(s["inverseBindMatrices"]), do: view.(a)
  clips = for a <- j["animations"] || [], s <- a["samplers"], x <- [s["input"], s["output"]], do: view.(x)
  images = for i <- j["images"] || [], i["bufferView"], do: i["bufferView"]
  bytes = fn list -> list |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.map(&Enum.at(views, &1)["byteLength"]) |> Enum.sum() end
  {m, s, c, i} = {bytes.(mesh), bytes.(skin -- mesh), bytes.(clips -- (mesh ++ skin)), bytes.(images)}

  %{
    total: byte_size(bin),
    json: length,
    mesh: m,
    skin: s,
    clips: c,
    images: i,
    other: data - m - s - c - i,
    names: Enum.map(j["animations"] || [], & &1["name"]),
    count: length(j["images"] || [])
  }
end

kb = fn b -> :erlang.float_to_binary(b / 1024, decimals: 1) end

IO.puts("| Level | Clips | All (KB) | JSON | Mesh | Skin | Clips | Pictures |\n|---|---|---|---|---|---|---|---|")

for level <- ["mid", "far"],
    anims <- [[], ["walk"], ["walk", "stroll", "idle"], ["tai_chi", "yoga", "aerobics"]] do
  order = %{"blueprint" => "person", "options" => %{"age" => 35, "height" => 0.55, "animations" => anims}}

  case World.Orders.build(order, level, "glb") do
    {:ok, bin} ->
      p = parts.(bin)
      cells = [p.total, p.json, p.mesh, p.skin, p.clips, p.images] |> Enum.map(kb) |> Enum.join(" | ")
      IO.puts("| #{level} | #{Enum.join(p.names, ", ")} | #{cells} (#{p.count}) |")

    {:error, _} ->
      IO.puts("| #{level} | #{Enum.join(anims, ", ")} | no such clips here |")
  end
end

# A set of six people, each with the walk.
people =
  for {gender, age, k} <- [{1.0, 30, 1}, {0.0, 28, 2}, {1.0, 62, 3}, {0.0, 45, 4}, {1.0, 19, 5}, {0.0, 70, 6}],
      do: %{"gender" => gender, "age" => age, "weight" => 0.4 + 0.03 * k, "animations" => ["walk"]}

for level <- ["mid", "far"] do
  scenes =
    for o <- people do
      {:ok, scene} = World.Orders.scene(%{"blueprint" => "person", "options" => o}, level)
      scene
    end

  alone = scenes |> Enum.map(&byte_size(World.GLB.encode(&1))) |> Enum.sum()
  pictures = scenes |> Enum.map(&parts.(World.GLB.encode(&1)).images) |> Enum.sum()
  {atlased, images} = World.Atlas.scenes(scenes, uri: fn m, ext -> "set.#{m}.#{ext}" end)
  glbs = atlased |> Enum.map(&byte_size(World.GLB.encode(&1))) |> Enum.sum()
  atlas = images |> Map.values() |> Enum.map(fn {_, b} -> byte_size(b) end) |> Enum.sum()

  IO.puts(
    "A set of 6 at #{level}: #{kb.(alone)} KB alone (#{kb.(pictures)} KB of pictures); " <>
      "with one atlas #{kb.(glbs + atlas)} KB (the GLB files #{kb.(glbs)} KB, the atlas #{kb.(atlas)} KB)"
  )
end
