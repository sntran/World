# Make the clips of a template from the animations of its glTF file: for
# each bone of World, its turn at each time, in one JSON file of priv/.
#
#     mix run scripts/gltf_clips.exs IN.gltf TEMPLATE.json OUT.json "SOURCE" "LICENSE" [FRONT]
#
# TEMPLATE.json is the template (priv/animals/templates/): its bones of
# World and the bone of the file of each (the first of a list). FRONT is
# the axis of the file to the front of the animal, as in
# scripts/gltf_figure.exs (z by default).
#
# - The clips: Walk (walk), Gallop (run), Idle (idle) and Eating (eat).
#   A clip of more than 2 s has every second key of the file.
# - The turn of a bone of World at a time is the mean turn of the bones of
#   the file that give it their weights (each by its weights), from the
#   pose at rest, in the axes of World (a quaternion: x, y, z, w); a bone
#   with no weights has the turn of its own bone of the file. The
#   mesh of the template (priv/animals/meshes/) gives the weights. The
#   pelvis also has its move from its place at rest, in the units of the
#   mesh.
# - The speed (in the units of the mesh for each second): the mean speed
#   to the back of the lowest paw, on the ground, when the animal moves
#   in place. An app moves the animal at this speed so the paws do not
#   slide.
Code.require_file("gltf.exs", __DIR__)

[input, template, output, source, license | rest] = System.argv()
gltf = GLTF.load(input)
t = template |> File.read!() |> JSON.decode!()
names = gltf["nodes"] |> Enum.with_index() |> Map.new(fn {n, i} -> {n["name"], i} end)
mesh = Path.join([Path.dirname(template), "..", "meshes", t["mesh"] <> ".json"]) |> File.read!() |> JSON.decode!()
to_world = for {world, files} <- t["bones"], file <- List.wrap(files), into: %{}, do: {file, world}
file_parent = Map.new(mesh["bones"], &{&1["name"], &1["parent"]})

# The bones of the file of each bone of World, with their weights: a bone
# of the file gives its weights to its own bone of World, or to the bone
# of World of the nearest bone above it (as World.Animals).
owner = fn file -> Stream.iterate(file, &file_parent[&1]) |> Enum.take_while(& &1) |> Enum.find_value(&to_world[&1]) end

weighted =
  Enum.group_by(mesh["weights"], fn {file, _} -> owner.(file) end, fn {file, list} ->
    {names[file], Enum.sum(Enum.map(list, &List.last/1))}
  end)

# A bone of World with no weights (the end of a tail) has the turn of its
# own bone of the file.
bones = Map.new(t["bones"], fn {world, file} -> {world, weighted[world] || [{names[hd(List.wrap(file))], 1.0}]} end)

# The paw of each foot: the bone of the file with the most weight.
paws = for side <- ~w(l r), part <- ~w(front hind), do: bones["#{part}_foot_#{side}"] |> Enum.max_by(&elem(&1, 1)) |> elem(0)
pelvis = names[hd(List.wrap(t["bones"]["pelvis"]))]

# The mean of turns (quaternions), each with its weight.
mean = fn list ->
  {q0, _} = hd(list)

  {x, y, z, w} =
    Enum.reduce(list, {0.0, 0.0, 0.0, 0.0}, fn {{a, b, c, d} = q, k}, {x, y, z, w} ->
      k = if GLTF.dot(q, q0) < 0, do: -k, else: k
      {x + k * a, y + k * b, z + k * c, w + k * d}
    end)

  l = :math.sqrt(x * x + y * y + z * z + w * w)
  {x / l, y / l, z / l, w / l}
end

# The axes of World: x = front x up, y the front, z up (+y of the file).
{sign, axis} =
  case rest do
    ["-" <> a] -> {-1, a}
    [a] -> {1, a}
    [] -> {1, "z"}
  end

front = List.to_tuple(for a <- ~w(x y z), do: if(a == axis, do: sign * 1.0, else: 0.0))
up = {0.0, 1.0, 0.0}
right = World.Vec.cross(front, up)
turn = fn p -> {World.Vec.dot(p, right), World.Vec.dot(p, front), World.Vec.dot(p, up)} end
# A turn around an axis is the same turn around the axis in World.
turn_q = fn {x, y, z, w} ->
  {a, b, c} = turn.({x, y, z})
  {a, b, c, w}
end
round = fn values, n -> Enum.map(values, &Float.round(&1 / 1, n)) end

rest_world = GLTF.world(gltf)

clips =
  for {world_name, file_name} <- [{"walk", "Walk"}, {"run", "Gallop"}, {"idle", "Idle"}, {"eat", "Eating"}],
      a = Enum.find(gltf["animations"], &(&1["name"] == file_name)),
      into: %{} do
    times = GLTF.read(gltf, hd(a["samplers"])["input"])
    values = Enum.map(a["samplers"], &List.to_tuple(GLTF.read(gltf, &1["output"])))
    step = if List.last(times) > 2, do: 2, else: 1
    keys = Enum.take_every(0..(length(times) - 1), step)

    poses =
      for k <- keys do
        local =
          for c <- a["channels"], reduce: %{} do
            acc ->
              v = values |> Enum.at(c["sampler"]) |> elem(k) |> Tuple.to_list()
              Map.update(acc, c["target"]["node"], %{c["target"]["path"] => v}, &Map.put(&1, c["target"]["path"], v))
          end

        GLTF.world(gltf, local)
      end

    ts = for k <- keys, do: Enum.at(times, k) - hd(times)

    turns =
      Map.new(bones, fn {world_name, list} ->
        {world_name,
         for w <- poses do
           q = mean.(for {i, k} <- list, do: {GLTF.qmul(elem(w[i], 1), GLTF.conj(elem(rest_world[i], 1))), k})
           round.(Tuple.to_list(turn_q.(q)), 4)
         end}
      end)

    {p0, _, _} = rest_world[pelvis]
    moves = for w <- poses, {p, _, _} = w[pelvis], do: round.(Tuple.to_list(turn.(GLTF.sub(p, p0))), 4)

    # The paw nearest the ground at each time, and its move to the back to
    # the next time.
    low = fn w, i -> elem(turn.(elem(w[i], 0)), 2) end
    ground = for w <- poses, i <- paws, reduce: :infinity, do: (acc -> min(acc, low.(w, i)))
    # A paw on the ground: less than 2% of the height of the pelvis above
    # the lowest place of the paws.
    near = 0.02 * elem(turn.(p0), 2)

    speeds =
      for [{w0, t0}, {w1, t1}] <- Enum.chunk_every(Enum.zip(poses, ts), 2, 1, :discard),
          i <- paws,
          low.(w0, i) < ground + near and low.(w1, i) < ground + near,
          do: -elem(turn.(GLTF.sub(elem(w1[i], 0), elem(w0[i], 0))), 1) / (t1 - t0)

    # The middle value: a paw that lands or lifts moves less.
    speed =
      if world_name in ~w(walk run),
        do: speeds |> Enum.sort() |> Enum.at(div(length(speeds), 2)) |> Float.round(4),
        else: 0.0
    {world_name, %{"length" => Float.round(List.last(ts), 4), "times" => round.(ts, 4), "bones" => turns, "pelvis" => moves, "speed" => speed}}
  end

File.write!(output, JSON.encode!(%{"source" => source, "license" => license, "clips" => clips}))

for {name, c} <- Enum.sort(clips),
    do: IO.puts("#{name}: #{c["length"]} s, #{length(c["times"])} times, speed #{c["speed"]}")
