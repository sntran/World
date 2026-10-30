# Make the mesh of the template of primates (priv/animals/meshes/) from
# the low-poly macaque of BigMaQ (a rhesus macaque, MIT; the template
# mesh came from MPI-IS, see CREDITS.md):
#
#     mix run scripts/primate_template.exs macaque_LOWPOLY.json OUT.json
#     ARMS=up TAIL=no mix run scripts/primate_template.exs macaque_LOWPOLY.json OUT.json
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
# - The eyes: a sphere at each eye of the file, a pupil (the material
#   eye) and an iris (the material iris).
# - The size: the head and the body 0.5 m long.
# - With ARMS=up, the arms at rest go up, not down (a primate that walks
#   upright with its arms up, the gibbon: the skin of the shoulders does
#   not fold, as the arms turn little from the rest). With TAIL=no, the
#   faces of the tail go, the hole at its root has a cap, and the tail
#   has no bones (its weights go to the pelvis).
alias World.People.Human
alias World.Vec

[input, output] = System.argv()
up? = System.get_env("ARMS") == "up"
no_tail? = System.get_env("TAIL") == "no"
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
world_bone = fn name ->
  if light.(name) or (no_tail? and String.starts_with?(name, "Tail")), do: nil, else: world_bone.(name)
end

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

# The body up, the legs and the arms down again (the arms up with
# ARMS=up), the neck and the head to the front.
turns = turn.(turns, "pelvis", {1.0, 0.0, 0.0}, 90)
turns = Enum.reduce(~w(thigh_l thigh_r), turns, &turn.(&2, &1, {1.0, 0.0, 0.0}, -90))
turns = Enum.reduce(~w(upperarm_l upperarm_r), turns, &turn.(&2, &1, {1.0, 0.0, 0.0}, if(up?, do: 90, else: -90)))
turns = turns |> turn.("neck_01", {1.0, 0.0, 0.0}, -20) |> turn.("head", {1.0, 0.0, 0.0}, -40)

# The hands of a person (the pose at rest of the body plan): along the
# hand from the wrist to the root of the middle finger (with the arms up:
# along the forearm), and across from the root of the little finger to
# the root of the index finger.
person = World.Detail.with(:mid, fn -> Human.person("primate", clothes: [], hair: nil) end)
human = Map.new(person.skeleton.bones, &{&1.name, &1})

turns =
  Enum.reduce(~w(l r), turns, fn s, turns ->
    hand = "hand_#{s}"
    {fs, ss} = if s == "l", do: {"Left", "l"}, else: {"Right", "r"}
    wrist = now.(turns, hand, by[hand].head)
    along = Vec.norm(Vec.sub(now.(turns, hand, at.("#{fs}HandMiddle1")), wrist))
    want =
      if up?,
        do: Vec.norm(Vec.sub(wrist, now.(turns, "lowerarm_#{s}", by["lowerarm_#{s}"].head))),
        else: Vec.norm(Vec.sub(human["middle_01_#{ss}"].head, human[hand].head))

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

# With ARMS=up, the points between the trunk and an arm (a weight on the
# upper arm from 0.02 to 0.98) fold where the arm turns up: 30 steps of
# smoothing (each point to the mean of the points next to it on the
# faces) make the skin of the armpit smooth. The other points stay.
rest =
  if up? do
    near =
      Enum.reduce(file["F"], %{}, fn face, acc ->
        Enum.reduce(Enum.zip(face, tl(face) ++ [hd(face)]), acc, fn {a, b}, acc ->
          acc |> Map.update(a, MapSet.new([b]), &MapSet.put(&1, b)) |> Map.update(b, MapSet.new([a]), &MapSet.put(&1, a))
        end)
      end)

    loose =
      for {i, ws} <- point_weights,
          arm = ws |> Enum.filter(fn {b, _} -> String.starts_with?(b, "upperarm_") end) |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
          arm > 0.02 and arm < 0.98,
          do: i

    Enum.reduce(1..30, List.to_tuple(rest), fn _, ps ->
      Enum.reduce(loose, ps, fn i, acc ->
        ns = Enum.map(near[i], &elem(ps, &1))
        put_elem(acc, i, ns |> Enum.reduce(&Vec.add/2) |> Vec.scale(1 / length(ns)))
      end)
    end)
    |> Tuple.to_list()
  else
    rest
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
top = "head" |> weights_of.(0.5) |> Enum.map(&elem(&1, 2)) |> Enum.max()
k = 0.5 / (top - seat)
ground = rest |> Enum.map(&elem(&1, 2)) |> Enum.min()
fit = fn {x, y, z} -> {x * k, y * k, (z - ground) * k} end

# The eyes: a sphere in each socket of the file, with its pole to the
# front (y). The faces of the first ring (to 15 degrees from the pole)
# are the pupil (the material eye), the other faces are the iris (the
# material iris): the eye of a macaque shows almost no white.
eye = fn {c, r} ->
  {rings, segs} = {12, 10}

  ps =
    for i <- 0..rings, j <- 0..(segs - 1) do
      {a, b} = {:math.pi() * i / rings, 2 * :math.pi() * j / segs}
      Vec.add(c, Vec.scale({:math.sin(a) * :math.sin(b), :math.cos(a), :math.sin(a) * :math.cos(b)}, r))
    end

  ix = fn i, j -> i * segs + rem(j, segs) end

  {ps,
   for(
     i <- 0..(rings - 1),
     j <- 0..(segs - 1),
     t <- [[ix.(i, j), ix.(i + 1, j), ix.(i + 1, j + 1)], [ix.(i, j), ix.(i + 1, j + 1), ix.(i, j + 1)]],
     do: {t, if(i == 0, do: 1, else: 2)}
   )}
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
    {ps ++ p, fs ++ Enum.map(f, fn {t, m} -> {Enum.map(t, &(&1 + n)), m} end)}
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

tris = faces ++ Enum.map(eye_faces, &elem(&1, 0))
mats = List.duplicate(0, length(faces)) ++ Enum.map(eye_faces, &elem(&1, 1))

# The face (in the units of the mesh at rest, on the head of the file):
# the lips meet in a fold about 1.5 cm deep. The line of the bottom of
# the fold goes down from the middle (z 0.606) to 1.5 cm to the side
# (0.594), then up to the corner of the mouth (2.6 cm, 0.615); the jaw
# turns around a line across the head in front of the ears (y 0.02, z
# 0.625); the brows are over the eyes (z 0.669 to 0.69).
head_w = for {i, ws} <- point_weights, {"head", w} <- ws, into: %{}, do: {i, w}
pts = List.to_tuple(all)
smooth = fn a, b, x -> t = min(max((x - a) / (b - a), 0.0), 1.0); t * t * (3 - 2 * t) end

line =
  fn x ->
    xs = [{0.0, 0.6061}, {0.0043, 0.603}, {0.0092, 0.5999}, {0.015, 0.594}, {0.0189, 0.5944}, {0.0227, 0.6048}, {0.0262, 0.615}]
    x = min(abs(x), 0.0262)
    [{x0, z0}, {x1, z1}] = xs |> Enum.chunk_every(2, 1, :discard) |> Enum.find(fn [{a, _}, {b, _}] -> x >= a and x <= b end)
    z0 + (z1 - z0) * (x - x0) / (x1 - x0)
  end

# The line between the jaw and the face: the lip line to the corner of
# the mouth (y 0.076), then back to the hinge.
cut = fn {x, y, _} ->
  edge = line.(x)
  if y >= 0.076, do: edge, else: 0.625 + (edge - 0.625) * smooth.(0.02, 0.076, y)
end

front = fn x ->
  for(i <- Map.keys(head_w), {px, py, pz} = elem(pts, i), abs(abs(px) - abs(x)) < 0.003, abs(pz - line.(px)) < 0.012, do: py)
  |> Enum.max(fn -> 0.0 end)
end

# The normal of each point of the skin (the sum of the normals of its
# faces): the inside of the fold of the lips faces up or down, the crease
# of the cheek faces to the side.
normal =
  Enum.zip(tris, mats)
  |> Enum.filter(fn {_, m} -> m == 0 end)
  |> Enum.reduce(%{}, fn {[a, b, c], _}, acc ->
    n = Vec.cross(Vec.sub(elem(pts, b), elem(pts, a)), Vec.sub(elem(pts, c), elem(pts, a)))
    Enum.reduce([a, b, c], acc, fn i, acc -> Map.update(acc, i, n, &Vec.add(&1, n)) end)
  end)

face =
  for {i, hw} <- head_w, hw > 0.0, into: %{} do
    {x, y, z} = elem(pts, i)
    {_, _, nz} = Vec.norm(Map.get(normal, i, {0.0, 0.0, 1.0}))
    inside? = abs(x) < 0.024 and abs(z - line.(x)) < 0.012 and abs(nz) > 0.5
    {i, %{hw: hw, x: x, y: y, z: z, lip: z - line.(x), depth: if(inside?, do: front.(x) - y, else: 0.0)}}
  end

turn_jaw = fn {_, y, z}, deg ->
  {dy, dz} = {y - 0.02, z - 0.625}
  a = deg * :math.pi() / 180
  {0.0, dy * :math.cos(a) + dz * :math.sin(a) - dy, dz * :math.cos(a) - dy * :math.sin(a) - dz}
end

near_lips = fn f -> f.hw * (1 - smooth.(0.006, 0.016, abs(f.lip))) * (1 - smooth.(0.024, 0.03, abs(f.x))) * smooth.(0.05, 0.07, f.y) end

shapes = %{
  # The jaw opens 18 degrees: the points under the line, in front of the
  # hinge, by their weight on the head (the throat stays).
  "jaw_open" =>
    for {i, f} <- face, w = f.hw * smooth.(-0.001, 0.003, cut.({f.x, f.y, f.z}) - f.z) * smooth.(0.0, 0.02, f.y), w > 0, into: %{} do
      {i, Vec.scale(turn_jaw.({f.x, f.y, f.z}, 18), w)}
    end,
  # The fear grimace: the corners of the mouth go back 6 mm, the upper lip
  # up 3 mm and the lower lip down 4 mm.
  "lips_back" =>
    for {i, f} <- face, w = near_lips.(f), w > 0, into: %{} do
      {i, Vec.scale({0.0, -0.006 * smooth.(0.008, 0.026, abs(f.x)), if(f.lip >= 0, do: 0.003, else: -0.004)}, w)}
    end,
  # The lip-smack: the lips go 6 mm to the front, the corners in.
  "lips_forward" =>
    for {i, f} <- face, w = near_lips.(f), w > 0, into: %{} do
      {i, Vec.scale({-0.25 * f.x, 0.006, 0.0}, w)}
    end,
  # The threat: the brows go up 4 mm.
  "brows_up" =>
    for {i, f} <- face, w = f.hw * smooth.(0.666, 0.672, f.z) * (1 - smooth.(0.684, 0.694, f.z)) * smooth.(0.04, 0.06, f.y), w > 0, into: %{} do
      {i, Vec.scale({0.0, 0.0, 0.004}, w)}
    end
}

# Inside the fold of the lips (a point that faces up or down, inside the
# corners of the mouth): the upper teeth (2 to 5 mm in from the front of
# the upper lip), and the mouth deeper (from 2.5 mm in under the line of
# the lips: the lower lip faces up, and shows when the mouth is shut).
marks = %{
  "teeth" =>
    for(
      {i, f} <- face,
      w = smooth.(0.0015, 0.0025, f.depth) * (1 - smooth.(0.004, 0.0055, f.depth)) * smooth.(-0.001, 0.0005, f.lip),
      w > 0,
      into: %{},
      do: {i, w}
    ),
  "mouth" =>
    for(
      {i, f} <- face,
      w = if(f.lip >= 0, do: smooth.(0.004, 0.0055, f.depth), else: smooth.(0.0015, 0.0025, f.depth)),
      w > 0,
      into: %{},
      do: {i, w}
    )
}

# With TAIL=no: the faces with a mean weight of the tail bones of the
# file of more than 0.5 go. Each new hole has a cap: a fan of faces to
# the mean of its points (with their mean weights). The points on no
# face go.
{all, tris, mats, weights, shapes, marks} =
  if no_tail? do
    tail =
      for %{"vertex_index" => i, "weights" => ws} <- file["deform_weights"], into: %{} do
        {i, ws |> Enum.filter(fn {b, _} -> String.starts_with?(b, "Tail") end) |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
      end

    edges = fn ts -> MapSet.new(for [a, b, c] <- ts, e <- [{a, b}, {b, c}, {c, a}], do: e) end
    open = fn ts -> ts |> edges.() |> then(fn es -> Enum.reject(es, fn {a, b} -> MapSet.member?(es, {b, a}) end) end) end

    {kept, kept_mats} =
      Enum.zip(tris, mats) |> Enum.reject(fn {t, _} -> Enum.sum(Enum.map(t, &Map.get(tail, &1, 0.0))) / 3 > 0.5 end) |> Enum.unzip()

    holes = MapSet.difference(MapSet.new(open.(kept)), MapSet.new(open.(tris)))
    next = Map.new(holes)

    loops =
      Enum.reduce(holes, {[], MapSet.new()}, fn {a, _}, {loops, seen} ->
        if MapSet.member?(seen, a) do
          {loops, seen}
        else
          loop = Stream.iterate(a, &next[&1]) |> Enum.reduce_while([], fn p, acc -> if p in acc, do: {:halt, acc}, else: {:cont, [p | acc]} end) |> Enum.reverse()
          {[loop | loops], MapSet.union(seen, MapSet.new(loop))}
        end
      end)
      |> elem(0)

    by_point = Enum.group_by(weights, fn {_, [i, _]} -> i end, fn {b, [_, w]} -> {b, w} end)
    pts = List.to_tuple(all)

    {all, caps, cap_weights} =
      Enum.reduce(loops, {all, [], []}, fn loop, {all, caps, ws} ->
        c = length(all)
        center = loop |> Enum.map(&elem(pts, &1)) |> Enum.reduce(&Vec.add/2) |> Vec.scale(1 / length(loop))
        mean = loop |> Enum.flat_map(&by_point[&1]) |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        mean = for {b, l} <- mean, do: {b, [c, Float.round(Enum.sum(l) / length(loop), 5)]}
        fan = for [a, b] <- Enum.chunk_every(loop ++ [hd(loop)], 2, 1, :discard), do: [b, a, c]
        {all ++ [center], caps ++ fan, ws ++ mean}
      end)

    tris = kept ++ caps
    used = tris |> List.flatten() |> Enum.uniq() |> Enum.sort()
    new = used |> Enum.with_index() |> Map.new()

    remap = fn m -> for {i, v} <- m, Map.has_key?(new, i), into: %{}, do: {new[i], v} end

    {Enum.map(used, &Enum.at(all, &1)), Enum.map(tris, fn t -> Enum.map(t, &new[&1]) end),
     kept_mats ++ List.duplicate(0, length(caps)),
     for({b, [i, w]} <- weights ++ cap_weights, Map.has_key?(new, i), do: {b, [new[i], w]}),
     Map.new(shapes, fn {n, m} -> {n, remap.(m)} end), Map.new(marks, fn {n, m} -> {n, remap.(m)} end)}
  else
    {all, tris, mats, weights, shapes, marks}
  end

data = %{
  "source" =>
    "BigMaQ (https://github.com/martinivis/BigMaQ, commit a92d2d0): the low-poly template mesh of a rhesus macaque, its 115 bones and its weights; the template mesh came from the Max Planck Institute for Intelligent Systems and M. J. Black. World turns it to the pose at rest of the body plan and adds the eyes.",
  "license" => "MIT (the license of the repository of BigMaQ): https://github.com/martinivis/BigMaQ/blob/main/LICENSE",
  "points" => Enum.map(all, round),
  "faces" => tris,
  "materials" => [
    %{"name" => "body", "color" => [170, 140, 110]},
    %{"name" => "eye", "color" => [20, 16, 14]},
    %{"name" => "iris", "color" => [155, 100, 40]}
  ],
  "face_materials" => mats,
  "bones" =>
    for b <- bones do
      %{"name" => b.name, "parent" => b.parent, "head" => round.(fit.(heads[b.name]))}
      |> then(&if(ends[b.name], do: Map.put(&1, "tail", round.(fit.(ends[b.name]))), else: &1))
    end,
  "weights" => weights |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Map.new(fn {b, l} -> {b, Enum.sort(l)} end),
  # The shapes of the face (the moves of the points, in the units of the
  # mesh) and the parts of the mouth (the weight of each point).
  "shapes" =>
    Map.new(shapes, fn {n, m} ->
      {n, for({i, d} <- Enum.sort(m), [x, y, z] = round.(d), [x, y, z] != [0.0, 0.0, 0.0], do: [i, x, y, z])}
    end),
  "marks" => Map.new(marks, fn {n, m} -> {n, for({i, w} <- Enum.sort(m), w >= 0.01, do: [i, Float.round(w, 3)])} end),
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
