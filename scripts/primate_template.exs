# Make the mesh of the template of primates (priv/animals/meshes/) from
# the low-poly macaque of BigMaQ (a rhesus macaque, MIT; the template
# mesh came from MPI-IS, see CREDITS.md):
#
#     mix run scripts/primate_template.exs macaque_LOWPOLY.json OUT.json
#
# The file is pose_reconstruction/data/Mesh/macaque_LOWPOLY.json of
# https://github.com/martinivis/BigMaQ (commit a92d2d0, SHA-256
# 0cbf5966...6261d5d). The same format as scripts/gltf_figure.exs.
#
# - The axes: the file has y up and z to the front; World has z up, y to
#   the front, and the left side at -x.
# - The bones: the 115 bones of the file go to the bones of World.Animals.
#   Primate (the bones of a person). A bone of the file with no bone of
#   World (the eyes, the nose, the ends of the fingers, the toes) gives
#   its weights to the bone of World above it.
# - The pose at rest: the file is on four limbs, and the body plan needs
#   a body that stands as a person (its pose on four limbs starts from
#   that). The pelvis turns the body up, the legs and the arms turn back
#   down, the hands turn down with the palms to the body (as the hands of
#   a person), and the neck and the head turn so the face is to the front.
# - The points at rest: each point is where the skin of World (linear
#   blend skinning) must start, so that the same turns back give the
#   point of the file. So the animal on four limbs has the shape of the
#   file, with no thin joints.
# - The eyes: a sphere at each eye of the file (the material eye).
# - The size: the head and the body 0.5 m long.
alias World.People.Human
alias World.Vec

[input, output] = System.argv()
file = input |> File.read!() |> JSON.decode!()

# A point of the file in the axes of World.
axes = fn [x, y, z] -> {-x, z, y} end
v = fn %{"x" => x, "y" => y, "z" => z} -> axes.([x, y, z]) end

# The bone of World of each bone of the file.
side = fn s -> if s == "Left", do: "l", else: "r" end

world_bone = fn name ->
  case Regex.run(~r/^(Left|Right)(.+)$/, name) do
    [_, s, "Shoulder"] -> "clavicle_#{side.(s)}"
    [_, s, "Arm"] -> "upperarm_#{side.(s)}"
    [_, s, "ForeArm"] -> "lowerarm_#{side.(s)}"
    [_, s, "Hand"] -> "hand_#{side.(s)}"
    [_, s, "UpLeg"] -> "thigh_#{side.(s)}"
    [_, s, "Leg"] -> "calf_#{side.(s)}"
    [_, s, "Foot"] -> "foot_#{side.(s)}"
    [_, s, "ToeBase"] -> "ball_#{side.(s)}"
    [_, s, "Hand" <> finger] ->
      case Regex.run(~r/^(Thumb|Index|Middle|Ring|Pinky)([1-3])$/, finger) do
        [_, f, n] -> "#{String.downcase(f)}_0#{n}_#{side.(s)}"
        nil -> nil
      end

    _ ->
      case name do
        "Hips" -> "pelvis"
        "Spine" -> "spine_01"
        "Spine1" -> "spine_02"
        "Spine3" -> "spine_03"
        "Neck" -> "neck_01"
        "Head" -> "head"
        "Tail" -> "tail_01"
        "Tail" <> n -> "tail_0#{String.to_integer(n) + 1}"
        _ -> nil
      end
  end
end

file_bones = Map.new(file["bones"], &{&1["name"], &1})

# The last bone of the tail of the file has almost no weights (0.002 at
# most): its weights go to the bone above it.
most = for %{"weights" => ws} <- file["deform_weights"], {b, w} <- ws, reduce: %{}, do: (acc -> Map.update(acc, b, w, &max(&1, w)))
kids = Enum.group_by(file["bones"], & &1["parent"], & &1["name"])
light = fn name -> Map.get(most, name, 0.0) < 0.05 and Map.get(kids, name, []) == [] end
world_bone = fn name -> if light.(name), do: nil, else: world_bone.(name) end

owner = fn name ->
  Stream.iterate(name, &file_bones[&1]["parent"]) |> Enum.take_while(& &1) |> Enum.find_value(world_bone)
end

# The bones of World: the head of each at the head of its bone of the
# file; its parent the bone of World above it.
bones =
  for b <- file["bones"], name = world_bone.(b["name"]), name != nil do
    parent = b["parent"] && owner.(b["parent"])
    %{name: name, file: b["name"], parent: parent, head: v.(b["head"])}
  end

# The weights of the bones of World at each point.
points = Enum.map(file["V"], axes)

point_weights =
  for %{"vertex_index" => i, "weights" => ws} <- file["deform_weights"], into: %{} do
    ws =
      ws
      |> Enum.group_by(fn {b, _} -> owner.(b) end, fn {_, w} -> w end)
      |> Enum.map(fn {b, l} -> {b, Enum.sum(l)} end)
      |> Enum.filter(fn {_, w} -> w > 0 end)

    sum = ws |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    {i, Enum.map(ws, fn {b, w} -> {b, w / sum} end)}
  end

by = Map.new(bones, &{&1.name, &1})
at = fn file_name -> v.(file_bones[file_name]["head"]) end

# Turns: a turn is {matrix, move} (p -> m p + t). The turn of each bone
# from the file to the pose at rest; a turn of a bone turns all the
# bones under it.
mat = fn {a, b, c}, {x, y, z} -> {Vec.dot(a, {x, y, z}), Vec.dot(b, {x, y, z}), Vec.dot(c, {x, y, z})} end
transpose = fn {{a, b, c}, {d, e, f}, {g, h, i}} -> {{a, d, g}, {b, e, h}, {c, f, i}} end
mul = fn m, n -> transpose.(n) |> then(fn {c1, c2, c3} -> {mat.(m, c1), mat.(m, c2), mat.(m, c3)} end) |> transpose.() end
apply_turn = fn {m, t}, p -> Vec.add(mat.(m, p), t) end
compose = fn {m2, t2}, {m1, t1} -> {mul.(m2, m1), Vec.add(mat.(m2, t1), t2)} end

rotation = fn axis, deg ->
  {x, y, z} = Vec.norm(axis)
  a = deg * :math.pi() / 180
  {c, s} = {:math.cos(a), :math.sin(a)}
  k = 1 - c

  {{c + x * x * k, x * y * k - z * s, x * z * k + y * s}, {y * x * k + z * s, c + y * y * k, y * z * k - x * s},
   {z * x * k - y * s, z * y * k + x * s, c + z * z * k}}
end

under = fn root ->
  Enum.filter(bones, fn b -> Stream.iterate(b.name, &by[&1].parent) |> Enum.take_while(& &1) |> Enum.member?(root) end)
  |> Enum.map(& &1.name)
end

id = {{{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}}, {0.0, 0.0, 0.0}}

# A turn of `root` and the bones under it: by `deg` around `axis`, at the
# head of `root` where it is now.
turn = fn turns, root, axis, deg ->
  pivot = apply_turn.(turns[root], by[root].head)
  m = rotation.(axis, deg)
  r = {m, Vec.sub(pivot, mat.(m, pivot))}
  Enum.reduce(under.(root), turns, fn b, acc -> Map.update!(acc, b, &compose.(r, &1)) end)
end

now = fn turns, name, p -> apply_turn.(turns[name], p) end
turns = Map.new(bones, &{&1.name, id})

# The body up, the legs and the arms down again, the neck and the head
# to the front.
turns = turn.(turns, "pelvis", {1.0, 0.0, 0.0}, 90)
turns = Enum.reduce(~w(thigh_l thigh_r upperarm_l upperarm_r), turns, &turn.(&2, &1, {1.0, 0.0, 0.0}, -90))
turns = turns |> turn.("neck_01", {1.0, 0.0, 0.0}, -20) |> turn.("head", {1.0, 0.0, 0.0}, -40)

# The hands of a person (the pose at rest of the body plan): along the
# hand from the wrist to the root of the middle finger, and across from
# the root of the little finger to the root of the index finger.
person = World.Detail.with(:mid, fn -> Human.person("primate", clothes: [], hair: nil) end)
human = Map.new(person.skeleton.bones, &{&1.name, &1})

turns =
  Enum.reduce(~w(l r), turns, fn s, turns ->
    hand = "hand_#{s}"
    {fs, ss} = if s == "l", do: {"Left", "l"}, else: {"Right", "r"}
    wrist = now.(turns, hand, by[hand].head)
    along = Vec.norm(Vec.sub(now.(turns, hand, at.("#{fs}HandMiddle1")), wrist))
    want = Vec.norm(Vec.sub(human["middle_01_#{ss}"].head, human[hand].head))
    axis = Vec.cross(along, want)
    deg = :math.acos(Vec.dot(along, want) |> max(-1.0) |> min(1.0)) * 180 / :math.pi()
    turns = if Vec.len(axis) > 1.0e-9, do: turn.(turns, hand, axis, deg), else: turns

    # The palm to the body: a turn of the forearm around its length.
    elbow = now.(turns, "lowerarm_#{s}", by["lowerarm_#{s}"].head)
    arm = Vec.norm(Vec.sub(now.(turns, hand, by[hand].head), elbow))
    flat = fn u -> Vec.norm(Vec.sub(u, Vec.scale(arm, Vec.dot(u, arm)))) end
    across = flat.(Vec.sub(now.(turns, hand, at.("#{fs}HandIndex1")), now.(turns, hand, at.("#{fs}HandPinky1"))))
    goal = flat.(Vec.sub(human["index_01_#{ss}"].head, human["pinky_01_#{ss}"].head))
    sign = if Vec.dot(Vec.cross(across, goal), arm) >= 0, do: 1, else: -1
    deg = sign * :math.acos(Vec.dot(across, goal) |> max(-1.0) |> min(1.0)) * 180 / :math.pi()
    turn.(turns, "lowerarm_#{s}", arm, deg)
  end)

# The points at rest: the point p of World skin (the turns back from the
# rest, each by its weight) must give the point of the file q:
# sum(w R_b^T (p - t_b)) = q, so A p = q + c with A = sum(w R_b^T) and
# c = sum(w R_b^T t_b).
inverse = fn {{a, b, c}, {d, e, f}, {g, h, i}} ->
  det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)

  {{(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det},
   {(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det},
   {(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det}}
end

add_m = fn {a1, b1, c1}, {a2, b2, c2} -> {Vec.add(a1, a2), Vec.add(b1, b2), Vec.add(c1, c2)} end
scale_m = fn {a, b, c}, k -> {Vec.scale(a, k), Vec.scale(b, k), Vec.scale(c, k)} end
zero = {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}}

rest =
  for {q, i} <- Enum.with_index(points) do
    {a, c} =
      Enum.reduce(point_weights[i], {zero, {0.0, 0.0, 0.0}}, fn {b, w}, {a, c} ->
        {m, t} = turns[b]
        rt = transpose.(m)
        {add_m.(a, scale_m.(rt, w)), Vec.add(c, Vec.scale(mat.(rt, t), w))}
      end)

    mat.(inverse.(a), Vec.add(q, c))
  end

# The bones at rest. The tail of a bone with no next bone of the plan:
# the end of the middle finger for a hand, the tip of the toes for a
# ball, the end of the finger for the last bone of a finger, the end of
# the tail (its points with a weight of 0.1 or more: the last bone of
# the tail has few), and up from the joint for the head (the head of a person is
# up along its bone, to the top of the skull).
weights_of = fn name, least -> for {i, ws} <- point_weights, {^name, w} <- ws, w >= least, do: Enum.at(rest, i) end
tip = fn name, dir, least -> name |> weights_of.(least) |> Enum.max_by(&Vec.dot(&1, dir)) end

heads = Map.new(bones, fn b -> {b.name, now.(turns, b.name, b.head)} end)

ends =
  for b <- bones, into: %{} do
    file_end =
      case Regex.run(~r/^(thumb|index|middle|ring|pinky)_03_(l|r)$/, b.name) do
        [_, f, s] -> at.("#{if s == "l", do: "Left", else: "Right"}Hand#{String.capitalize(f)}4")
        nil -> nil
      end

    t =
      cond do
        file_end -> now.(turns, b.name, file_end)
        b.name in ~w(hand_l hand_r) -> now.(turns, b.name, at.(if b.name == "hand_l", do: "LeftHandMiddle1", else: "RightHandMiddle1"))
        b.name in ~w(ball_l ball_r) -> tip.(b.name, {0.0, 1.0, 0.0}, 0.5)
        b.name == "head" -> Vec.add(heads["head"], {0.0, 0.0, Vec.dot(Vec.sub(tip.("head", {0.0, 0.0, 1.0}, 0.5), heads["head"]), {0.0, 0.0, 1.0})})
        String.starts_with?(b.name, "tail_") and not Enum.any?(bones, &(&1.parent == b.name)) -> tip.(b.name, Vec.sub(heads[b.name], heads[b.parent]), 0.1)
        true -> nil
      end

    {b.name, t}
  end

# The size: the head and the body 0.5 m long (from the top of the head to
# the lowest point of the pelvis), on the ground at z = 0.
seat = weights_of.("pelvis", 0.5) |> Enum.map(&elem(&1, 2)) |> Enum.min()
top = rest |> Enum.map(&elem(&1, 2)) |> Enum.max()
k = 0.5 / (top - seat)
ground = rest |> Enum.map(&elem(&1, 2)) |> Enum.min()
fit = fn {x, y, z} -> {x * k, y * k, (z - ground) * k} end

# The eyes: a sphere in each socket of the file.
eye = fn {c, r} ->
  {rings, segs} = {6, 10}

  ps =
    for i <- 0..rings, j <- 0..(segs - 1) do
      {a, b} = {:math.pi() * i / rings, 2 * :math.pi() * j / segs}
      Vec.add(c, Vec.scale({:math.sin(a) * :math.cos(b), :math.sin(a) * :math.sin(b), :math.cos(a)}, r))
    end

  ix = fn i, j -> i * segs + rem(j, segs) end
  {ps, for(i <- 0..(rings - 1), j <- 0..(segs - 1), t <- [[ix.(i, j), ix.(i + 1, j), ix.(i + 1, j + 1)], [ix.(i, j), ix.(i + 1, j + 1), ix.(i, j + 1)]], do: t)}
end

# The lids of the file are closed: the eye moves to the front, so a part
# of it shows. Its radius is 1.1 times the distance from the center of
# the eye of the file to the nearest point of the skin; it goes out of
# the skin in front of it by 0.35 of its radius.
socket = fn name ->
  c = now.(turns, "head", at.(name))
  r = 1.1 * (rest |> Enum.map(&Vec.len(Vec.sub(&1, c))) |> Enum.min())

  # The face looks to the front (y) at rest.
  dir = {0.0, 1.0, 0.0}
  pts = List.to_tuple(rest)

  # The distance along `dir` to the skin (Moller and Trumbore).
  front =
    file["F"]
    |> Enum.flat_map(fn [a, b, cc, d] -> [[a, b, cc], [a, cc, d]] end)
    |> Enum.flat_map(fn [a, b, cc] ->
      {p0, p1, p2} = {elem(pts, a), elem(pts, b), elem(pts, cc)}
      {e1, e2} = {Vec.sub(p1, p0), Vec.sub(p2, p0)}
      h = Vec.cross(dir, e2)
      det = Vec.dot(e1, h)

      with true <- abs(det) > 1.0e-12,
           s = Vec.sub(c, p0),
           u = Vec.dot(s, h) / det,
           true <- u >= 0 and u <= 1,
           q = Vec.cross(s, e1),
           w = Vec.dot(dir, q) / det,
           true <- w >= 0 and u + w <= 1,
           t = Vec.dot(e2, q) / det,
           true <- t > 0 do
        [t]
      else
        _ -> []
      end
    end)
    |> Enum.min()

  {Vec.add(c, Vec.scale(dir, front - 0.65 * r)), r}
end

n0 = length(rest)

{eye_points, eye_faces} =
  Enum.reduce(~w(LeftEye RightEye), {[], []}, fn name, {ps, fs} ->
    {p, f} = eye.(socket.(name))
    n = n0 + length(ps)
    {ps ++ p, fs ++ Enum.map(f, fn t -> Enum.map(t, &(&1 + n)) end)}
  end)

faces = Enum.flat_map(file["F"], fn [a, b, c, d] -> [[a, b, c], [a, c, d]] end)
all = Enum.map(rest ++ eye_points, fit)
round = fn {x, y, z} -> Enum.map([x, y, z], &Float.round(&1 / 1, 5)) end

# A rotation matrix as a quaternion [x, y, z, w].
quaternion = fn {{m00, m01, m02}, {m10, m11, m12}, {m20, m21, m22}} ->
  tr = m00 + m11 + m22

  cond do
    tr > 0 ->
      s = :math.sqrt(tr + 1.0) * 2
      [(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s]

    m00 > m11 and m00 > m22 ->
      s = :math.sqrt(1.0 + m00 - m11 - m22) * 2
      [0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s]

    m11 > m22 ->
      s = :math.sqrt(1.0 + m11 - m00 - m22) * 2
      [(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s]

    true ->
      s = :math.sqrt(1.0 + m22 - m00 - m11) * 2
      [(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s]
  end
end

weights =
  (for {i, ws} <- point_weights, {b, w} <- ws, w2 = Float.round(w / 1, 5), w2 > 0, do: {b, [i, w2]}) ++
    for(i <- n0..(length(all) - 1)//1, do: {"head", [i, 1.0]})

data = %{
  "source" =>
    "BigMaQ (https://github.com/martinivis/BigMaQ, commit a92d2d0): the low-poly template mesh of a rhesus macaque, its 115 bones and its weights; the template mesh came from the Max Planck Institute for Intelligent Systems and M. J. Black. World turns it to the pose at rest of the body plan and adds the eyes.",
  "license" => "MIT (the license of the repository of BigMaQ): https://github.com/martinivis/BigMaQ/blob/main/LICENSE",
  "points" => Enum.map(all, round),
  "faces" => faces ++ eye_faces,
  "materials" => [%{"name" => "body", "color" => [170, 140, 110]}, %{"name" => "eye", "color" => [40, 28, 18]}],
  "face_materials" => List.duplicate(0, length(faces)) ++ List.duplicate(1, length(eye_faces)),
  "bones" =>
    for b <- bones do
      %{"name" => b.name, "parent" => b.parent, "head" => round.(fit.(heads[b.name]))}
      |> then(&if(ends[b.name], do: Map.put(&1, "tail", round.(fit.(ends[b.name]))), else: &1))
    end,
  "weights" => weights |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Map.new(fn {b, l} -> {b, Enum.sort(l)} end),
  # For the clips of BigMaQ (scripts/bigmaq_clips.exs): the bone of the
  # file of each bone, its turn from the file to the pose at rest (a
  # quaternion x, y, z, w, in the axes of World), and the units of the
  # mesh for each unit of the file.
  "file" => %{
    "bones" => Map.new(bones, &{&1.name, &1.file}),
    "turns" => Map.new(bones, fn b -> {b.name, turns[b.name] |> elem(0) |> quaternion.() |> Enum.map(&Float.round(&1, 6))} end),
    "scale" => Float.round(k, 8)
  }
}

File.write!(output, JSON.encode!(data))
IO.puts("#{length(all)} points, #{length(data["faces"])} faces, #{length(data["bones"])} bones")
