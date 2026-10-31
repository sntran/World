# Make the clips of the template of primates (priv/animals/clips/) from
# the pose reconstructions of BigMaQ (real rhesus macaques; CC BY 4.0):
#
#     mix run scripts/bigmaq_clips.exs reconstructions.zip macaque_LOWPOLY.json priv/animals/clips/primate.json
#
# reconstructions.zip is the file of https://zenodo.org/records/20663410
# (BigMaQ_latest_pose_reconstructions/ and dataset_overview.csv), and
# macaque_LOWPOLY.json the mesh of scripts/primate_template.exs. The same
# format as scripts/gltf_clips.exs.
#
# - The files of the poses (action_params_*.pth) are files of PyTorch: a
#   pickle and the data of its tensors. A small reader takes only the
#   tensors and the dictionaries from the pickle, and stops at any other
#   thing (a pickle can run code).
# - The poses: the turn of 27 bones of the file (axis and angle, in the
#   axes of the file), the turn and the move of all the body, at 40
#   frames each second. The turn of a bone of the file is the turn of its
#   parent and then its own turn (as SMPL). The mesh is in tenths of the
#   unit of the room (meters), its hips at the place that BigMaQ gives.
# - The room has z up. The clip turns around z, so the animal walks to
#   the front of World (y).
# - The turn of a bone of World: the turn of its bone of the file, from
#   the pose at rest of the template (the mesh gives the turns of
#   scripts/primate_template.exs), in the axes of World. The pelvis also
#   has its move from its place at rest, in the units of the mesh, with
#   the move to the front at the speed of the clip taken away.
# - A clip that loops: the last pose goes to the first, linearly in time
#   over the clip, so the loop has no jump.
# - The feet: the paws are the roots of the middle fingers and toes; the
#   height of each over its ground (the height under which it is for 0.3
#   of the clip: in a walk a paw is on the ground for more than half of
#   the step, and rolls on it), in the units of the mesh.
[zip, mesh, output] = System.argv()

alias World.Vec

# The clips: a clip of World from frames of an action of BigMaQ (its row
# in dataset_overview.csv, the individual, the first and the last frame,
# each `step` frame), with the ground on the feet or on the body (the
# lowest point of the skin), and its turn around z from its move or (with
# `face`) from its head. The environment variable CLIPS (names with
# commas) makes only those clips.
# - The walk: the cleanest straight cycle of a walk on the ground in the
#   file (from one step of the left foot to the next; all four paws on
#   the ground for 0.58 to 0.77 of the cycle).
# - The run: the fastest straight cycle (1.5 m/s in the file, a turn of
#   9 degrees; the paws on the ground for 0.06 to 0.44 of the cycle).
# - The sit: 4 s of an animal that rests, labelled "Resting" only: the
#   back up, the hips still and 16 cm over the paws, the tail on the
#   ground (in other sits of the file the tail goes down through the
#   floor).
# The file has no clean jump: the animals in the room hop and turn by 60
# to 180 degrees, onto and off things. The jump stays the jump of the
# body plan. It has no climb cycle: the tracks with the label
# "Climbing" are leaps up to a ledge and pull-ups (TODO.md). The climb
# stays the climb of the body plan.
#
# The folder of an action in the zip is the number of its row in
# dataset_overview.csv from 0 (not the first column of the file).
clips =
  Enum.map(
    [
      %{name: "walk", action: 458, individual: "G", from: 157, to: 183, loop: true},
      %{name: "run", action: 203, individual: "L", from: 58, to: 76, loop: true},
      %{name: "sit", action: 415, individual: "G", from: 40, to: 200, loop: true, ground: "body", step: 2, face: true}
    ]
    |> Enum.filter(&(System.get_env("CLIPS") in [nil, ""] or &1.name in String.split(System.get_env("CLIPS"), ","))),
    &Map.merge(%{ground: "feet", step: 1, face: false}, &1)
  )

# A strict reader of the pickle of PyTorch: dictionaries, tuples,
# strings, numbers, and the tensors of torch._utils._rebuild_tensor_v2.
defmodule Pickle do
  @allowed [{"torch._utils", "_rebuild_tensor_v2"}, {"collections", "OrderedDict"}] ++
             for(t <- ~w(FloatStorage DoubleStorage LongStorage IntStorage BoolStorage), do: {"torch", t})

  def load(bin), do: run(bin, [], %{})

  defp run(<<0x80, _, rest::binary>>, s, m), do: run(rest, s, m)
  defp run(<<"}", rest::binary>>, s, m), do: run(rest, [%{} | s], m)
  defp run(<<")", rest::binary>>, s, m), do: run(rest, [{} | s], m)
  defp run(<<"(", rest::binary>>, s, m), do: run(rest, [:mark | s], m)
  defp run(<<"N", rest::binary>>, s, m), do: run(rest, [nil | s], m)
  defp run(<<0x88, rest::binary>>, s, m), do: run(rest, [true | s], m)
  defp run(<<0x89, rest::binary>>, s, m), do: run(rest, [false | s], m)
  defp run(<<"q", i, rest::binary>>, [t | _] = s, m), do: run(rest, s, Map.put(m, i, t))
  defp run(<<"r", i::little-32, rest::binary>>, [t | _] = s, m), do: run(rest, s, Map.put(m, i, t))
  defp run(<<"h", i, rest::binary>>, s, m), do: run(rest, [m[i] | s], m)
  defp run(<<"j", i::little-32, rest::binary>>, s, m), do: run(rest, [m[i] | s], m)
  defp run(<<"K", i, rest::binary>>, s, m), do: run(rest, [i | s], m)
  defp run(<<"M", i::little-16, rest::binary>>, s, m), do: run(rest, [i | s], m)
  defp run(<<"J", i::little-signed-32, rest::binary>>, s, m), do: run(rest, [i | s], m)
  defp run(<<"G", f::big-float-64, rest::binary>>, s, m), do: run(rest, [f | s], m)
  defp run(<<"X", n::little-32, t::binary-size(n), rest::binary>>, s, m), do: run(rest, [t | s], m)
  defp run(<<0x8C, n, t::binary-size(n), rest::binary>>, s, m), do: run(rest, [t | s], m)

  defp run(<<"c", rest::binary>>, s, m) do
    [mod, name, rest] = String.split(rest, "\n", parts: 3)
    unless {mod, name} in @allowed, do: raise("the pickle has #{mod}.#{name}")
    run(rest, [{:global, mod, name} | s], m)
  end

  defp run(<<0x85, rest::binary>>, [a | s], m), do: run(rest, [{a} | s], m)
  defp run(<<0x86, rest::binary>>, [b, a | s], m), do: run(rest, [{a, b} | s], m)
  defp run(<<0x87, rest::binary>>, [c, b, a | s], m), do: run(rest, [{a, b, c} | s], m)

  defp run(<<"t", rest::binary>>, s, m) do
    {items, [:mark | s]} = Enum.split_while(s, &(&1 != :mark))
    run(rest, [items |> Enum.reverse() |> List.to_tuple() | s], m)
  end

  defp run(<<"Q", rest::binary>>, [{"storage", {:global, "torch", type}, key, _, _} | s], m),
    do: run(rest, [{:storage, type, key} | s], m)

  defp run(<<"R", rest::binary>>, [args, f | s], m), do: run(rest, [reduce(f, args) | s], m)

  defp run(<<"u", rest::binary>>, s, m) do
    {items, [:mark, dict | s]} = Enum.split_while(s, &(&1 != :mark))
    pairs = items |> Enum.reverse() |> Enum.chunk_every(2) |> Map.new(fn [k, v] -> {k, v} end)
    run(rest, [Map.merge(dict, pairs) | s], m)
  end

  defp run(<<"s", rest::binary>>, [v, k, dict | s], m), do: run(rest, [Map.put(dict, k, v) | s], m)
  defp run(<<".", _::binary>>, [top | _], _), do: top
  defp run(<<op, _::binary>>, _, _), do: raise("the pickle has the opcode #{op}")

  defp reduce({:global, "collections", "OrderedDict"}, {}), do: %{}

  defp reduce({:global, "torch._utils", "_rebuild_tensor_v2"}, {{:storage, type, key}, offset, size, _stride, _, _}),
    do: {:tensor, type, key, offset, Tuple.to_list(size)}
end

# The tensors of a file of PyTorch (a zip): name to {shape, a flat list}.
read_pth = fn bin ->
  {:ok, files} = :zip.unzip(bin, [:memory])
  files = Map.new(files, fn {n, b} -> {to_string(n), b} end)
  root = files |> Map.keys() |> hd() |> String.split("/") |> hd()

  for {name, {:tensor, type, key, offset, size}} <- Pickle.load(files["#{root}/data.pkl"]), into: %{} do
    raw = files["#{root}/data/#{key}"]
    count = Enum.product(size)

    values =
      case type do
        "FloatStorage" -> for <<v::little-float-32 <- raw>>, do: v
        "DoubleStorage" -> for <<v::little-float-64 <- raw>>, do: v
        _ -> []
      end

    {name, {size, Enum.slice(values, offset, count)}}
  end
end

entry = fn action, individual ->
  name = ~c"BigMaQ_latest_pose_reconstructions/#{action}/action_params_#{individual}_06.pth"
  {:ok, [{_, bin}]} = :zip.unzip(String.to_charlist(zip), [:memory, {:file_list, [name]}])
  read_pth.(bin)
end

# The mesh of BigMaQ (its joints and their parents) and the template.
file = mesh |> File.read!() |> JSON.decode!()
template = Path.join([:code.priv_dir(:world), "animals", "meshes", "primate.json"]) |> File.read!() |> JSON.decode!()
names = file["joint_to_index"] |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
index = file["joint_to_index"]
parents = hd(file["kintree_table"])
target = {3.9462e-11, 2.4515e-01, -1.9256e-01}
joints = Enum.map(file["J"], &List.to_tuple/1)
j0 = hd(joints)
# The joints in the units of the room, the hips at the place of BigMaQ.
joints = joints |> Enum.map(&Vec.add(Vec.scale(Vec.sub(&1, j0), 0.1), target)) |> List.to_tuple()

opt = ~w(Hips Spine Spine1 Spine2 Spine3 Neck Head LeftShoulder LeftArm LeftForeArm LeftHand RightShoulder RightArm RightForeArm RightHand LeftUpLeg LeftLeg LeftFoot Tail Tail1 Tail2 Tail3 Tail4 Tail5 RightUpLeg RightLeg RightFoot)

# Matrices 3 x 3 as tuples of rows.
mat = fn {a, b, c}, v -> {Vec.dot(a, v), Vec.dot(b, v), Vec.dot(c, v)} end
transpose = fn {{a, b, c}, {d, e, f}, {g, h, i}} -> {{a, d, g}, {b, e, h}, {c, f, i}} end
mul = fn m, n -> n |> transpose.() |> then(fn {c1, c2, c3} -> transpose.({mat.(m, c1), mat.(m, c2), mat.(m, c3)}) end) end
id = {{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}}

rodrigues = fn {x, y, z} = v ->
  a = Vec.len(v)

  if a < 1.0e-12 do
    id
  else
    {x, y, z} = {x / a, y / a, z / a}
    {c, s} = {:math.cos(a), :math.sin(a)}
    k = 1 - c

    {{c + x * x * k, x * y * k - z * s, x * z * k + y * s}, {y * x * k + z * s, c + y * y * k, y * z * k - x * s},
     {z * x * k - y * s, z * y * k + x * s, c + z * z * k}}
  end
end

quaternion = fn {{m00, m01, m02}, {m10, m11, m12}, {m20, m21, m22}} ->
  tr = m00 + m11 + m22

  q =
    cond do
      tr > 0 ->
        s = :math.sqrt(tr + 1.0) * 2
        {(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s}

      m00 > m11 and m00 > m22 ->
        s = :math.sqrt(1.0 + m00 - m11 - m22) * 2
        {0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s}

      m11 > m22 ->
        s = :math.sqrt(1.0 + m11 - m00 - m22) * 2
        {(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s}

      true ->
        s = :math.sqrt(1.0 + m22 - m00 - m11) * 2
        {(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s}
    end

  # w >= 0, so near turns have near quaternions.
  {x, y, z, w} = q
  if w < 0, do: [-x, -y, -z, -w], else: [x, y, z, w]
end

from_quaternion = fn [x, y, z, w] ->
  {{1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)},
   {2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)},
   {2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)}}
end

# The turn and the place of each joint of the file in the room.
pose = fn turns, global, t ->
  local = Map.new(Enum.zip(opt, turns), fn {n, v} -> {index[n], rodrigues.(v)} end)

  Enum.reduce(0..(length(names) - 1), {%{}, %{}}, fn i, {g, p} ->
    l = Map.get(local, i, id)

    case Enum.at(parents, i) do
      parent when parent < 0 ->
        {Map.put(g, i, mul.(global, l)), Map.put(p, i, Vec.add(mat.(global, elem(joints, i)), t))}

      parent ->
        off = Vec.sub(elem(joints, i), elem(joints, parent))
        {Map.put(g, i, mul.(g[parent], l)), Map.put(p, i, Vec.add(p[parent], mat.(g[parent], off)))}
    end
  end)
end

# The axes of the file to the axes of World: x to -x, y to z, z to y.
c = {{-1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, {0.0, 1.0, 0.0}}
k = template["file"]["scale"] * 10
rest_turns = Map.new(template["file"]["turns"], fn {b, q} -> {b, from_quaternion.(q)} end)
file_bones = template["file"]["bones"]
# The head of each bone at rest, and the head of the bone after it (the
# middle finger) or its tail (the toes).
head_of = Map.new(template["bones"], &{&1["name"], &1["head"]})
next_of = %{
  "middle_01_l" => head_of["middle_02_l"],
  "middle_01_r" => head_of["middle_02_r"],
  "ball_l" => Enum.find(template["bones"], &(&1["name"] == "ball_l"))["tail"],
  "ball_r" => Enum.find(template["bones"], &(&1["name"] == "ball_r"))["tail"]
}

pelvis_rest = template["bones"] |> Enum.find(&(&1["name"] == "pelvis")) |> Map.fetch!("head") |> List.to_tuple()
paws = %{"foot_l" => "LeftFootMiddle1", "foot_r" => "RightFootMiddle1", "hand_l" => "LeftHandMiddle1", "hand_r" => "RightHandMiddle1"}
fps = 40
round = fn v -> Float.round(v / 1, 4) end

made =
  for spec <- clips, into: %{} do
    data = entry.(spec.action, spec.individual)
    n = spec.to - spec.from
    frames = spec.from..spec.to//spec.step
    at = fn name, f -> data[name] |> elem(1) |> Enum.slice(f * 3, 3) |> List.to_tuple() end
    body = fn f -> data["body_pose"] |> elem(1) |> Enum.slice(f * 81, 81) |> Enum.chunk_every(3) |> Enum.map(&List.to_tuple/1) end

    # The loop: the turns of the last frame go to the turns of the first.
    fix = fn f, now, first, last ->
      if spec.loop, do: Vec.add(now, Vec.scale(Vec.sub(first, last), (f - spec.from) / n)), else: now
    end

    posed =
      for f <- frames do
        turns = Enum.zip_with([body.(f), body.(spec.from), body.(spec.to)], fn [a, b, l] -> fix.(f, a, b, l) end)
        global = rodrigues.(fix.(f, at.("R", f), at.("R", spec.from), at.("R", spec.to)))
        pose.(turns, global, at.("t", f))
      end

    # The turn around z: the walk to y (a clip that does not move: the
    # head to y).
    hips = Enum.map(posed, fn {_, p} -> p[0] end)
    {_, first} = hd(posed)

    {dx, dy, _} =
      if spec.face, do: Vec.sub(first[index["Head"]], first[0]), else: Vec.sub(List.last(hips), hd(hips))

    yaw = :math.atan2(dx, dy)
    y = {{:math.cos(yaw), -:math.sin(yaw), 0.0}, {:math.sin(yaw), :math.cos(yaw), 0.0}, {0.0, 0.0, 1.0}}
    distance = Vec.len(Vec.sub(List.last(hips), hd(hips)) |> then(fn {x, y, _} -> {x, y, 0.0} end))
    speed = if spec.loop and not spec.face, do: distance / (n / fps), else: 0.0

    # The ground of each paw: in a walk a paw is on the ground for more
    # than half of the step, and it rolls on the ground (its root moves up
    # and down by 1 to 2 cm): its ground is the height under which it is
    # for 0.3 of the clip. The ground of the clip: the lowest of them.
    lowest =
      Map.new(paws, fn {b, j} ->
        hs = posed |> Enum.map(fn {_, p} -> elem(p[index[j]], 2) end) |> Enum.sort()
        {b, Enum.at(hs, round(0.3 * (length(hs) - 1)))}
      end)

    ground = lowest |> Map.values() |> Enum.min()

    turn_of = fn g, b -> g[index[file_bones[b]]] |> then(&mul.(y, &1)) |> mul.(c) |> mul.(transpose.(rest_turns[b])) end

    # The fingers and the toes lie level: BigMaQ does not turn them, so
    # they go on along the hand and the foot, down to the ground. All the
    # fingers of a hand (the toes of a foot) turn at their roots by the
    # turn that makes the middle finger (the toes) level.
    level = fn g, root ->
      {from, to} = {List.to_tuple(head_of[root]), List.to_tuple(next_of[root])}
      d = mat.(turn_of.(g, root), Vec.sub(to, from))
      {dx, dy, _} = d
      flat = Vec.norm({dx, dy, 0.0})
      axis = Vec.cross(Vec.norm(d), flat)
      angle = :math.atan2(Vec.len(axis), Vec.dot(Vec.norm(d), flat))
      if Vec.len(axis) < 1.0e-9, do: id, else: rodrigues.(Vec.scale(Vec.norm(axis), angle))
    end

    bones =
      Map.new(file_bones, fn {b, _} ->
        {b,
         for {g, _} <- posed do
           turn = turn_of.(g, b)

           turn =
             case Regex.run(~r/^(?:thumb|index|middle|ring|pinky)_0\d_(l|r)$|^ball_(l|r)$/, b) do
               [_, s] -> mul.(level.(g, "middle_01_#{s}"), turn)
               [_, "", s] -> mul.(level.(g, "ball_#{s}"), turn)
               nil -> turn
             end

           turn |> quaternion.() |> Enum.map(round)
         end}
      end)

    # The move of the pelvis: on the ground of World, in place (the walk
    # to the front taken away), its height over the ground of the clip.
    pelvis =
      for {{_, p}, f} <- Enum.zip(posed, frames) do
        {x, yy, _} = Vec.scale(mat.(y, Vec.sub(p[0], hd(hips))), k)
        z = (elem(p[0], 2) - ground) * k
        [round.(x), round.(yy - speed * k * (f - spec.from) / fps), round.(z - elem(pelvis_rest, 2))]
      end

    feet = Map.new(paws, fn {b, j} -> {b, for({_, p} <- posed, do: round.(max(elem(p[index[j]], 2) - lowest[b], 0.0) * k))} end)

    {spec.name,
     %{
       "times" => for(f <- frames, do: round.((f - spec.from) / fps)),
       "length" => round.(n / fps),
       "bones" => bones,
       "pelvis" => pelvis,
       "speed" => round.(speed * k),
       "loop" => spec.loop,
       "ground" => spec.ground,
       "feet_from" => "ground",
       "feet" => feet
     }}
  end

File.write!(
  output,
  JSON.encode!(%{
    "source" =>
      "BigMaQ (L. Martini and others), pose reconstructions (https://zenodo.org/records/20663410): rhesus macaques, 40 frames each second; the walk is action 458, individual G, frames 157 to 183; the run is action 203, individual L, frames 58 to 76; the sit is action 415, individual G, frames 40 to 200 (each second frame). Changed by World (scripts/bigmaq_clips.exs): on the bones of World, the loops closed, the fingers and the toes level.",
    "license" => "CC BY 4.0: https://creativecommons.org/licenses/by/4.0/",
    "clips" => made
  })
)

for {name, c} <- made, do: IO.puts("#{name}: #{c["length"]} s, #{length(c["times"])} times, speed #{c["speed"]}")
