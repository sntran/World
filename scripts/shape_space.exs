# Make the shape space of a template of four legs (priv/animals/spaces/):
# the shape changes of other templates that the numbers of a shape do not
# give, as a mean and principal components (as SMAL for animals).
#
#     mix run scripts/shape_space.exs BASE OUT.json TEMPLATE ...
#
# BASE and each TEMPLATE are templates of priv/animals/templates/ on the
# rig of the Ultimate pack (the same bones of World).
#
# For each template:
#
# 1. Its size: the length of its back (the bones pelvis and spine_01) is
#    the length of the back of the base.
# 2. Its numbers (World.Animals.Shape): the lengths of the legs, the
#    neck, the tail and the ears from the lengths of its bones; the
#    girths and the size of the head from the root mean square of the
#    distance of the points of each bone to the axis of the bone; the
#    length of the muzzle from the point of the head farthest along its
#    bone; neck_up, head_down and tail_down from the angles of the neck,
#    of the line from the head to the tip of the nose, and of all the
#    tail. The base after these numbers is the fit.
# 3. The rest of its shape: for each point of the fit, a ray from the
#    nearest point of its bone (the bone that moves it most) to the
#    point, in the axes of that bone (for the head: y from the joint of
#    the neck to the tip of the nose), starts at the same place of the
#    same bone of the template (along the bone in the same part of its
#    length; along all the tail, for a tail of another number of bones;
#    the head for an ear of a template with no bones of the ears). The
#    move of the point is along the ray, to the face of the template that
#    the ray meets nearest to the length of the fit (faces of the same
#    bone or of a bone next to it, of the head and the ears only for the
#    head, 0.4 to 2.5 times the length of the
#    fit: a hit farther is another part of the body). A ray that meets no
#    face goes to the point of those faces nearest to its end, when that
#    point is nearer than the length of the fit. The move is in the axes
#    of the bone, over the scale of the bone. A point with no move takes
#    the mean of the moves of the points next to it.
#
# The shape space: the mean of the moves of all the templates (the base
# too, with no move), and the principal components of the moves around
# the mean, each with its standard deviation (sigma): the coefficient c
# of a component moves each point by c × sigma × the component. The
# numbers and the coefficients of each template are in the file too.
alias World.Animals
alias World.Animals.Shape
alias World.Vec

[base_name, output | names] = System.argv()

load = fn name ->
  %{bones: bones, points: points, weights: weights, template: t} = Animals.template(name)

  data =
    Path.join([:code.priv_dir(:world), "animals", "meshes", t["mesh"] <> ".json"]) |> File.read!() |> JSON.decode!()

  by_point = for {b, m} <- weights, {i, w} <- m, reduce: %{}, do: (acc -> Map.update(acc, i, [{b, w}], &[{b, w} | &1]))
  owner = fn i -> by_point |> Map.get(i, [{"pelvis", 1.0}]) |> Enum.max_by(fn {b, w} -> {w, b} end) |> elem(0) end
  %{name: name, bones: bones, points: points, weights: weights, template: t, faces: data["faces"], owner: owner}
end

len = fn b -> Vec.len(Vec.sub(b.tail, b.head)) end
by = fn m -> Map.new(m.bones, &{&1.name, &1}) end
tail_names = fn m -> m.bones |> Enum.map(& &1.name) |> Enum.filter(&String.starts_with?(&1, "tail_")) end

legs =
  ~w(front_upper_l front_lower_l front_foot_l hind_upper_l hind_lower_l hind_foot_l front_upper_r front_lower_r front_foot_r hind_upper_r hind_lower_r hind_foot_r)

# The root mean square of the distance to the axis of each bone, in x and
# in z of the bone, of the points that the bone moves most.
girths = fn m ->
  bb = by.(m)

  m.points
  |> Enum.with_index()
  |> Enum.group_by(fn {_, i} -> m.owner.(i) end, &elem(&1, 0))
  |> Map.new(fn {b, ps} ->
    {o, x, _, z} = Shape.frame(bb[b])
    n = length(ps)
    rx = :math.sqrt(Enum.sum(Enum.map(ps, &:math.pow(Vec.dot(Vec.sub(&1, o), x), 2))) / n)
    rz = :math.sqrt(Enum.sum(Enum.map(ps, &:math.pow(Vec.dot(Vec.sub(&1, o), z), 2))) / n)
    {b, {rx, rz}}
  end)
end

mean = fn list -> Enum.sum(list) / length(list) end

# The length of the head: the farthest point along the bone of the head
# from its head, of the points that it moves most.
reach = fn m ->
  {o, _, y, _} = Shape.frame(by.(m)["head"])

  m.points
  |> Enum.with_index()
  |> Enum.filter(fn {_, i} -> m.owner.(i) == "head" end)
  |> Enum.map(fn {p, _} -> Vec.dot(Vec.sub(p, o), y) end)
  |> Enum.max()
end

muzzle = fn base, m -> reach.(m) / reach.(base) end

# The angle of a bone over the level, to the front (degrees); of the tail
# (from the root to the end of the last bone), to the back.
angle = fn b ->
  {_, y, z} = Vec.sub(b.tail, b.head)
  :math.atan2(z, y) * 180 / :math.pi()
end

# The angle of the line from the joint of the neck and the head to the tip
# of the nose (the point of the head farthest to the front).
nose_angle = fn m ->
  o = by.(m)["head"].head

  nose =
    m.points
    |> Enum.with_index()
    |> Enum.filter(fn {_, i} -> m.owner.(i) == "head" end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.max_by(&elem(Vec.sub(&1, o), 1))

  {_, y, z} = Vec.sub(nose, o)
  :math.atan2(z, y) * 180 / :math.pi()
end

tail_angle = fn m ->
  names = tail_names.(m)
  {_, y, z} = Vec.sub(by.(m)[List.last(names)].tail, by.(m)[hd(names)].head)
  :math.atan2(z, -y) * 180 / :math.pi()
end

# The numbers of a template on the base (the template at the size of the
# base).
fit = fn base, m ->
  {bb, bm} = {by.(base), by.(m)}
  {gb, gm} = {girths.(base), girths.(m)}
  ratio = fn names -> mean.(for n <- names, bm[n] && bb[n], do: len.(bm[n]) / len.(bb[n])) end
  chain = fn mm -> mm |> tail_names.() |> Enum.map(&len.(by.(mm)[&1])) |> Enum.sum() end
  across = fn names, k -> mean.(for n <- names, gm[n] && gb[n], do: elem(gm[n], k) / elem(gb[n], k)) end

  tail_girth =
    mean.(for n <- tail_names.(m), gm[n], do: (elem(gm[n], 0) + elem(gm[n], 1)) / 2) /
      mean.(for n <- tail_names.(base), gb[n], do: (elem(gb[n], 0) + elem(gb[n], 1)) / 2)

  %{
    "body_length" => 1.0,
    "body_width" => across.(~w(pelvis spine_01), 0),
    "body_depth" => across.(~w(pelvis spine_01), 1),
    "leg_length" => ratio.(legs),
    "leg_girth" => (across.(legs, 0) + across.(legs, 1)) / 2,
    "neck_length" => ratio.(["neck_01"]),
    "neck_girth" => (across.(["neck_01"], 0) + across.(["neck_01"], 1)) / 2,
    "head_size" => (across.(["head"], 0) + across.(["head"], 1)) / 2,
    "muzzle_length" => muzzle.(base, m) / ((across.(["head"], 0) + across.(["head"], 1)) / 2),
    "tail_length" => chain.(m) / chain.(base),
    "tail_girth" => tail_girth
  }
  |> Map.merge(%{
    "neck_up" => angle.(bm["neck_01"]) - angle.(bb["neck_01"]),
    "head_down" => nose_angle.(base) + angle.(bm["neck_01"]) - angle.(bb["neck_01"]) - nose_angle.(m),
    "tail_down" => tail_angle.(base) - tail_angle.(m)
  })
  |> then(fn n -> if bm["ear_l"], do: Map.put(n, "ear_size", ratio.(~w(ear_l ear_r))), else: n end)
  # In the range of each number, so an order can give it.
  |> Map.new(fn {k, v} ->
    {lo, hi, _} = Shape.numbers()[k]
    {k, v |> max(lo) |> min(hi) |> Float.round(3)}
  end)
end

# A ray and a triangle (Möller and Trumbore): the length along the ray, or
# nil.
hit = fn from, dir, {a, b, c} ->
  e1 = Vec.sub(b, a)
  e2 = Vec.sub(c, a)
  p = Vec.cross(dir, e2)
  det = Vec.dot(e1, p)

  if abs(det) < 1.0e-12 do
    nil
  else
    s = Vec.sub(from, a)
    u = Vec.dot(s, p) / det
    q = Vec.cross(s, e1)
    v = Vec.dot(dir, q) / det
    t = Vec.dot(e2, q) / det
    if u >= 0 and v >= 0 and u + v <= 1 and t > 0, do: t
  end
end

# The point of a triangle nearest to a point (Ericson, Real-Time
# Collision Detection 5.1.5).
nearest = fn p, {a, b, c} ->
  {ab, ac, ap} = {Vec.sub(b, a), Vec.sub(c, a), Vec.sub(p, a)}
  {d1, d2} = {Vec.dot(ab, ap), Vec.dot(ac, ap)}
  bp = Vec.sub(p, b)
  {d3, d4} = {Vec.dot(ab, bp), Vec.dot(ac, bp)}
  cp = Vec.sub(p, c)
  {d5, d6} = {Vec.dot(ab, cp), Vec.dot(ac, cp)}
  {va, vb, vc} = {d3 * d6 - d5 * d4, d5 * d2 - d1 * d6, d1 * d4 - d3 * d2}

  cond do
    d1 <= 0 and d2 <= 0 ->
      a

    d3 >= 0 and d4 <= d3 ->
      b

    d6 >= 0 and d5 <= d6 ->
      c

    vc <= 0 and d1 >= 0 and d3 <= 0 ->
      Vec.add(a, Vec.scale(ab, d1 / (d1 - d3)))

    vb <= 0 and d2 >= 0 and d6 <= 0 ->
      Vec.add(a, Vec.scale(ac, d2 / (d2 - d6)))

    va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0 ->
      Vec.add(b, Vec.scale(Vec.sub(c, b), (d4 - d3) / (d4 - d3 + d5 - d6)))

    true ->
      k = 1 / (va + vb + vc)
      a |> Vec.add(Vec.scale(ab, vb * k)) |> Vec.add(Vec.scale(ac, vc * k))
  end
end

base = load.(base_name)
base_tail = tail_names.(base)

neighbors =
  for f <- base.faces, [a, b] <- Enum.chunk_every(f ++ [hd(f)], 2, 1, :discard), reduce: %{} do
    acc ->
      acc |> Map.update(a, MapSet.new([b]), &MapSet.put(&1, b)) |> Map.update(b, MapSet.new([a]), &MapSet.put(&1, a))
  end

moves = fn m ->
  # The template at the size of the base.
  k = (len.(by.(base)["pelvis"]) + len.(by.(base)["spine_01"])) / (len.(by.(m)["pelvis"]) + len.(by.(m)["spine_01"]))

  m = %{
    m
    | points: Enum.map(m.points, &Vec.scale(&1, k)),
      bones: Enum.map(m.bones, &%{&1 | head: Vec.scale(&1.head, k), tail: Vec.scale(&1.tail, k)})
  }

  numbers = fit.(base, m)
  {fit_bones, fit_points} = Shape.apply(base.bones, base.points, base.weights, numbers, base.template)
  fb = Map.new(fit_bones, &{&1.name, &1})
  mb = by.(m)
  n = Map.merge(Map.new(Shape.numbers(), fn {key, {_, _, d}} -> {key, d} end), numbers)
  scales = Shape.scales(base.bones, base.points, base.weights, n, base.template)

  # The faces of the template by their bone, as triangles.
  pts = List.to_tuple(m.points)

  tris =
    m.faces
    |> Enum.group_by(fn f ->
      f |> Enum.map(m.owner) |> Enum.frequencies() |> Enum.max_by(fn {b, c} -> {c, b} end) |> elem(0)
    end)
    |> Map.new(fn {b, fs} -> {b, for([a, bb, c] <- fs, do: {elem(pts, a), elem(pts, bb), elem(pts, c)})} end)

  m_tail = tail_names.(m)
  # The bones next to a bone of the template: its parent, its children.
  near = fn b ->
    bone = mb[b]
    kids = for x <- m.bones, x.parent == b, do: x.name
    # The head meets only the head and the ears (the neck under it is
    # another part of the body).
    if b == "head",
      do: ["head" | kids],
      else: [b | List.wrap(bone && bone.parent)] ++ kids ++ if(String.starts_with?(b, "tail_"), do: m_tail, else: [])
  end

  # The axes of a bone for the rays, with their length: the axes of the
  # bone; for the head, y from the joint of the neck to the tip of the
  # nose (the point of the head farthest to the front), as the bone of
  # the head does not lie the same way in each rig.
  axes = fn bones, points, owner, b ->
    if b == "head" do
      o = bones["head"].head

      nose =
        points
        |> Enum.with_index()
        |> Enum.filter(fn {_, i} -> owner.(i) == "head" end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.max_by(&elem(Vec.sub(&1, o), 1))

      y = Vec.norm(Vec.sub(nose, o))
      x = Vec.norm(Vec.sub({1.0, 0.0, 0.0}, Vec.scale(y, elem(y, 0))))
      {o, x, y, Vec.cross(x, y), Vec.len(Vec.sub(nose, o))}
    else
      {o, x, y, z} = Shape.frame(bones[b])
      {o, x, y, z, len.(bones[b])}
    end
  end

  fit_axes = Map.new(Map.keys(fb), &{&1, axes.(fb, fit_points, base.owner, &1)})
  m_axes = Map.new(Map.keys(mb), &{&1, axes.(mb, m.points, m.owner, &1)})
  length_of = fn table, b -> elem(table[b], 4) end

  # The place of a point of a bone of the base on the template: the bone
  # of the template and the length along it.
  place = fn b, along ->
    if String.starts_with?(b, "tail_") do
      fl = Enum.map(base_tail, &length_of.(fit_axes, &1))
      ml = Enum.map(m_tail, &length_of.(m_axes, &1))
      i = Enum.find_index(base_tail, &(&1 == b))
      s = (Enum.sum(Enum.take(fl, i)) + along) / Enum.sum(fl) * Enum.sum(ml)
      starts = Enum.scan([0.0 | Enum.drop(ml, -1)], &(&1 + &2))
      j = (Enum.count(starts, &(&1 <= s)) - 1) |> max(0)
      {Enum.at(m_tail, j), s - Enum.at(starts, j)}
    else
      {b, along / length_of.(fit_axes, b) * length_of.(m_axes, b)}
    end
  end

  result =
    for {p, i} <- Enum.with_index(fit_points) do
      own = base.owner.(i)
      # A bone of the base that the template does not have (an ear): the
      # head.
      b = if mb[own] || String.starts_with?(own, "tail_"), do: own, else: "head"
      {o, x, y, z, l} = fit_axes[b]
      d = Vec.sub(p, o)
      {lx, ly, lz} = {Vec.dot(d, x), Vec.dot(d, y), Vec.dot(d, z)}
      on = ly |> max(0.0) |> min(l)
      ray = {lx, ly - on, lz}
      e = Vec.len(ray)
      {mbone, along} = place.(b, on)
      {mo, mx, my, mz, ml} = m_axes[mbone]
      from = Vec.add(mo, Vec.scale(my, along |> max(0.0) |> min(ml)))
      {a, bb, c} = Vec.norm(ray)
      dir = mx |> Vec.scale(a) |> Vec.add(Vec.scale(my, bb)) |> Vec.add(Vec.scale(mz, c))
      # A hit far from the length of the fit is another part of the body
      # (the neck under the head): no hit.
      faces = Enum.flat_map(near.(mbone), &Map.get(tris, &1, []))
      ts = for t <- faces, h = hit.(from, dir, t), h != nil, h > 0.4 * e, h < 2.5 * e, do: h

      # The move in the template, in the axes of its bone: along the ray to
      # the face that it meets; with no face, to the point of the faces
      # nearest to the end of the ray, when it is nearer than the length
      # of the fit.
      along =
        cond do
          e <= 1.0e-9 or faces == [] ->
            nil

          ts != [] ->
            Vec.scale({a, bb, c}, Enum.min_by(ts, &abs(&1 - e)) - e)

          true ->
            q = Vec.add(from, Vec.scale(dir, e))
            d = faces |> Enum.map(&Vec.sub(nearest.(q, &1), q)) |> Enum.min_by(&Vec.len/1)
            if Vec.len(d) < e, do: {Vec.dot(d, mx), Vec.dot(d, my), Vec.dot(d, mz)}
        end

      if along do
        {ma, mm, mc} = along
        # The move in the fit, in the axes of the bone that moves the point
        # (as World.Animals.Shape keeps it), over the scale of the bone.
        move = x |> Vec.scale(ma) |> Vec.add(Vec.scale(y, mm)) |> Vec.add(Vec.scale(z, mc))
        {_, ox, oy, oz} = Shape.frame(fb[own])
        {sx, sy, sz} = scales[own]
        {Vec.dot(move, ox) / sx, Vec.dot(move, oy) / sy, Vec.dot(move, oz) / sz}
      end
    end

  # A point that meets no face: the mean of the points next to it.
  filled =
    Enum.reduce(1..20, List.to_tuple(result), fn _, acc ->
      Enum.reduce(0..(tuple_size(acc) - 1), acc, fn i, acc ->
        if elem(acc, i) do
          acc
        else
          known = for j <- Map.get(neighbors, i, []), v = elem(acc, j), do: v
          if known == [], do: acc, else: put_elem(acc, i, Vec.scale(Enum.reduce(known, &Vec.add/2), 1 / length(known)))
        end
      end)
    end)
    |> Tuple.to_list()
    |> Enum.map(&(&1 || {0.0, 0.0, 0.0}))

  missing = Enum.count(result, &is_nil/1)
  IO.puts("#{m.name}: #{inspect(numbers)}; #{missing} of #{length(result)} points have no move")
  {numbers, filled}
end

samples = [
  {base.name, {%{}, List.duplicate({0.0, 0.0, 0.0}, length(base.points))}}
  | for(
      name <- names,
      do:
        (
          m = load.(name)
          {name, moves.(m)}
        )
    )
]

# The principal components: the eigenvectors of the Gram matrix of the
# moves around the mean (Jacobi turns), small for a few samples.
rows = for {_, {_, ms}} <- samples, do: ms |> Enum.flat_map(&Tuple.to_list/1)
count = length(rows)
mu = rows |> Enum.zip_with(& &1) |> Enum.map(&(Enum.sum(&1) / count))
centered = for r <- rows, do: Enum.zip_with(r, mu, &(&1 - &2))
dot = fn a, b -> Enum.zip_with(a, b, &(&1 * &2)) |> Enum.sum() end
gram = for a <- centered, do: for(b <- centered, do: dot.(a, b))

jacobi = fn a ->
  n = length(a)
  a = a |> Enum.map(&List.to_tuple/1) |> List.to_tuple()

  v =
    for(i <- 0..(n - 1), do: List.to_tuple(for j <- 0..(n - 1), do: if(i == j, do: 1.0, else: 0.0))) |> List.to_tuple()

  get = fn m, i, j -> elem(elem(m, i), j) end
  set = fn m, i, j, x -> put_elem(m, i, put_elem(elem(m, i), j, x)) end

  {a, v} =
    Enum.reduce(1..100, {a, v}, fn _, {a, v} ->
      for p <- 0..(n - 2), q <- (p + 1)..(n - 1), reduce: {a, v} do
        {a, v} ->
          apq = get.(a, p, q)

          if abs(apq) < 1.0e-14 do
            {a, v}
          else
            theta = (get.(a, q, q) - get.(a, p, p)) / (2 * apq)
            t = if(theta >= 0, do: 1, else: -1) / (abs(theta) + :math.sqrt(theta * theta + 1))
            c = 1 / :math.sqrt(t * t + 1)
            s = t * c

            a =
              Enum.reduce(0..(n - 1), a, fn k, a ->
                {akp, akq} = {get.(a, k, p), get.(a, k, q)}
                a |> set.(k, p, c * akp - s * akq) |> set.(k, q, s * akp + c * akq)
              end)

            a =
              Enum.reduce(0..(n - 1), a, fn k, a ->
                {apk, aqk} = {get.(a, p, k), get.(a, q, k)}
                a |> set.(p, k, c * apk - s * aqk) |> set.(q, k, s * apk + c * aqk)
              end)

            v =
              Enum.reduce(0..(n - 1), v, fn k, v ->
                {vkp, vkq} = {get.(v, k, p), get.(v, k, q)}
                v |> set.(k, p, c * vkp - s * vkq) |> set.(k, q, s * vkp + c * vkq)
              end)

            {a, v}
          end
      end
    end)

  for i <- 0..(n - 1), do: {get.(a, i, i), for(k <- 0..(n - 1), do: get.(v, k, i))}
end

pairs =
  gram
  |> jacobi.()
  |> Enum.sort_by(&(-elem(&1, 0)))
  |> Enum.filter(fn {l, _} -> l > 1.0e-9 * max(1.0, Enum.sum(Enum.map(gram, &Enum.sum/1))) end)

components =
  for {l, w} <- pairs do
    u =
      Enum.zip_with(centered, w, fn r, k -> Enum.map(r, &(&1 * k)) end)
      |> Enum.zip_with(&Enum.sum/1)
      |> Enum.map(&(&1 / :math.sqrt(l)))

    {:math.sqrt(l / max(count - 1, 1)), u}
  end

coefficients = fn r ->
  for {sigma, u} <- components, do: Float.round(dot.(Enum.zip_with(r, mu, &(&1 - &2)), u) / sigma, 4)
end

vectors = fn flat -> flat |> Enum.chunk_every(3) |> Enum.map(fn v -> Enum.map(v, &Float.round(&1 / 1, 5)) end) end

data = %{
  "base" => base_name,
  "source" =>
    "The moves of the templates #{Enum.join([base_name | names], ", ")} on the base #{base_name} (scripts/shape_space.exs).",
  "mean" => vectors.(mu),
  "components" => for({sigma, u} <- components, do: %{"sigma" => Float.round(sigma, 6), "vectors" => vectors.(u)}),
  "animals" =>
    Map.new(Enum.zip(samples, rows), fn {{name, {numbers, _}}, r} ->
      {name, %{"shape" => numbers, "space" => coefficients.(r)}}
    end)
}

File.write!(output, JSON.encode!(data))
IO.puts("#{length(components)} components, sigmas #{inspect(Enum.map(components, &Float.round(elem(&1, 0), 4)))}")
