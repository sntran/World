defmodule World.Check do
  @moduledoc """
  The checks of a true model (`docs/world.md`, step P5): a model of the
  world must stand, its parts must not pass through each other, its
  joints must stay in their limits, and it must go out of the overhead
  door of the workshop that makes it.

  - `stands/1`: the center of mass (`World.Mass`; with no mass, the
    center of the points) is over the base: the points of the model on
    the ground (2 mm over its lowest point), with a margin of 1 mm.
  - `overlaps/1`: two parts that are in one place: the box of each, and
    the shared box is more than half of the smaller box, and a point in
    one is inside a closed mesh of the other. Two parts that a connection
    joins (a drum on its body, a tire on its rim, a grip and a mirror on
    one bar) and the fasteners (a bolt in the hole of a plate) are not
    checked, nor the skins and the open meshes: they have no inside.
  - `joints/2`: each value of a pose in the limits of its joint.
  - `fits/2`: the model goes through a door (a width and a height, in
    meters): its two smaller sizes, turned as the door needs. `model/2`
    does not check a house, a wall, a statue or a tower: they are built on their site. A
    vehicle goes through the drive-in door of its plant (`drive_in/0`); a
    thing put together on its site (`"site"` in its extras) goes through
    the door in its parts.

  `model/2` does not check that a door, a window, a material (a roof
  tile) or an enclosure stands: each is held in its wall, on its roof or
  on its wall. A boat floats,
  and it is built on a slipway: no check of its stand or of a door.

  `model/2` runs them all and gives `:ok` or `{:error, reasons}`.
  """
  alias World.{Assembly, Build, Frame, Joint, Mass, Part, Vec}

  # The overhead door of a factory of the world: 9 by 8 ft.
  @door {9 * 12 * 0.0254, 8 * 12 * 0.0254}

  # The kinds of the fasteners: a fastener goes through its parts.
  @fasteners [:bolt, :cap_screw, :wood_screw, :button_screw, :nut, :washer, :t_nut]

  # A vehicle leaves its plant on its wheels, by a drive-in door of 12 by
  # 14 ft (the door of a truck bay).
  @drive_in {12 * 12 * 0.0254, 14 * 12 * 0.0254}

  @doc "The overhead door of a factory: its width and its height (m)."
  def door, do: @door

  @doc "The drive-in door of the plant of a vehicle: its width and its height (m)."
  def drive_in, do: @drive_in

  @doc """
  All the checks of a model, in a pose (a map of a joint to its value):
  `:ok`, or `{:error, reasons}` (a list of `{check, details}`).
  """
  def model(item, pose \\ %{}) do
    reasons =
      [stand(item), overlaps(item), joints(item, pose), door(item)]
      |> Enum.flat_map(fn
        :ok -> []
        {:error, reason} -> [reason]
      end)

    if reasons == [], do: :ok, else: {:error, reasons}
  end

  # A door and a window stand in a wall, a material (a roof tile) on its
  # roof, an enclosure on its wall: they do not stand on their own. A boat
  # floats (its check is its stability: TODO.md). A helmet is worn, and
  # its strap hangs under its rim. A plant grows in the ground: its roots
  # hold it.
  defp stand(%{kind: kind}) when kind in [:door, :window, :material, :enclosure, :boat, :helmet, :plant], do: :ok
  # A thing on its site (a hammock between two trees, a swing on a
  # branch or under a ceiling: `"site"` in its extras) is held by its site.
  defp stand(%Assembly{extras: %{"site" => true}}), do: :ok
  defp stand(item), do: stands(item)

  # A house, a wall or a street is built on its site, a boat on the
  # slipway of its yard, a plant grows where it stands: they go through no
  # door. A
  # thing put together on its site (an overhead door: `"site"` in its
  # extras) goes through the door in its parts.
  defp door(%Assembly{kind: kind}) when kind in [:wall, :house, :boat, :street, :plant, :statue, :tower], do: :ok
  defp door(%Assembly{kind: :vehicle} = item), do: fits(item, @drive_in)

  defp door(%Assembly{extras: %{"site" => true}} = item),
    do: item |> Build.placed() |> Enum.map(fn {_, p} -> fits(p, @door) end) |> Enum.find(:ok, &(&1 != :ok))

  defp door(item), do: fits(item, @door)

  @doc """
  If the model stands on its base: `:ok`, or `{:error, {:tips, center,
  base}}` with the center of mass and the box of the base (x and y).

  A joint of the role `:stand` (the stand of a scooter, the side stand of
  a motorcycle) goes down to the angle where its stand first touches the
  ground, or to its upper limit. When the model is then on a line (two
  wheels) and its stand is to one side of the line, the model leans to
  that side until a point touches the ground: a motorcycle on its side
  stand.
  """
  def stands(item) do
    pose = stand_pose(item)
    placed = Build.placed(item, pose)
    points = for {f, p} <- placed, m <- p.shapes, pt <- m.points, do: Frame.point(f, pt)

    case points do
      [] ->
        :ok

      _ ->
        stand = for {f, %{kind: :stand} = p} <- placed, m <- p.shapes, pt <- m.points, do: Frame.point(f, pt)
        {points, {x, y, _}} = lean(points, stand, center(item, pose, placed, points))
        low = points |> Enum.map(&elem(&1, 2)) |> Enum.min()
        base = points |> Enum.filter(&(elem(&1, 2) < low + 0.002)) |> Enum.map(fn {x, y, _} -> {x, y} end) |> hull()

        if inside?(base, {x, y}, 0.001),
          do: :ok,
          else: {:error, {:tips, {x, y}, box(base)}}
    end
  end

  # The angle of each stand: the first angle where its lowest point is on
  # the ground of the other parts (by halves of the range), or its upper
  # limit when it does not get there.
  defp stand_pose(%Assembly{nodes: nodes} = item) do
    for {name, _, %{role: :stand, limits: [lo, hi]}} <- nodes, into: %{} do
      {name, if(gap(item, %{name => hi}) >= 0, do: hi, else: halve(item, name, lo, hi, 12))}
    end
  end

  defp stand_pose(_), do: %{}

  defp halve(_, _, _, hi, 0), do: hi

  defp halve(item, name, lo, hi, n) do
    mid = (lo + hi) / 2
    if gap(item, %{name => mid}) < 0, do: halve(item, name, lo, mid, n - 1), else: halve(item, name, mid, hi, n - 1)
  end

  # The height of the lowest point of the stands over the lowest point of
  # the other parts.
  defp gap(item, pose) do
    {stand, rest} = item |> Build.placed(pose) |> Enum.split_with(fn {_, p} -> p.kind == :stand end)

    low = fn placed ->
      for({f, p} <- placed, m <- p.shapes, pt <- m.points, do: elem(Frame.point(f, pt), 2)) |> Enum.min(fn -> 0.0 end)
    end

    low.(stand) - low.(rest)
  end

  # A model on a line of the ground, with its stand to one side of the
  # line: it turns about the line to that side until a point touches.
  defp lean(points, [], center), do: {points, center}

  defp lean(points, stand, center) do
    low = points |> Enum.map(&elem(&1, 2)) |> Enum.min()
    base = for {x, y, z} <- points, z < low + 0.002, do: {x, y}
    {a, b} = far_pair(base)
    {ux, uy} = norm2(sub2(b, a))
    n = {-uy, ux}
    d = fn {x, y, _} -> dot2(sub2({x, y}, a), n) end
    side = stand |> Enum.map(d) |> then(&(Enum.sum(&1) / length(&1)))

    if not line?(base, a, n) or abs(side) < 0.01 do
      {points, center}
    else
      s = if side > 0, do: 1, else: -1

      angles =
        for {_, _, z} = p <- points, e = s * d.(p), e > 0.002, do: :math.atan2(z - low, e)

      t = Enum.min(angles, fn -> 0.0 end)

      turn = fn {x, y, z} = p ->
        e = s * d.(p)
        h = z - low
        e2 = e * :math.cos(t) + h * :math.sin(t)
        h2 = h * :math.cos(t) - e * :math.sin(t)
        {nx, ny} = n
        {x + nx * s * (e2 - e), y + ny * s * (e2 - e), low + h2}
      end

      {Enum.map(points, turn), turn.(center)}
    end
  end

  # The base is a line: each point of it is within 2 mm of the line.
  defp line?(base, a, n), do: Enum.all?(base, &(abs(dot2(sub2(&1, a), n)) < 0.002))

  defp far_pair([p | _] = ps) do
    q = Enum.max_by(ps, &dist2(&1, p))
    {q, Enum.max_by(ps, &dist2(&1, q))}
  end

  defp sub2({x0, y0}, {x1, y1}), do: {x0 - x1, y0 - y1}
  defp dot2({x0, y0}, {x1, y1}), do: x0 * x1 + y0 * y1
  defp dist2(p, q), do: dot2(sub2(p, q), sub2(p, q))

  defp norm2(v) do
    l = :math.sqrt(dot2(v, v))
    if l < 1.0e-9, do: {1.0, 0.0}, else: {elem(v, 0) / l, elem(v, 1) / l}
  end

  # The center of mass. With a part of no mass, the center of the volume
  # of the closed meshes; with no closed mesh, the mean of the points.
  defp center(item, pose, placed, points) do
    case Mass.of(item, pose) do
      %{center: {_, _, _} = c, unknown: []} ->
        c

      _ ->
        solids = for {f, p} <- placed, m <- p.shapes, {v, c} <- [Mass.mesh(m)], do: {v, Frame.point(f, c)}
        total = solids |> Enum.map(&elem(&1, 0)) |> Enum.sum()

        if total > 0,
          do: solids |> Enum.map(fn {v, c} -> Vec.scale(c, v / total) end) |> Enum.reduce(&Vec.add/2),
          else: Vec.mean(points)
    end
  end

  # The convex hull of points in a plane (Andrew's monotone chain).
  defp hull(points) do
    ps = points |> Enum.uniq() |> Enum.sort()

    if length(ps) < 3 do
      ps
    else
      lower = half(ps)
      upper = half(Enum.reverse(ps))
      Enum.drop(lower, -1) ++ Enum.drop(upper, -1)
    end
  end

  defp half(ps) do
    ps
    |> Enum.reduce([], fn p, acc -> [p | drop(acc, p)] end)
    |> Enum.reverse()
  end

  defp drop([b, a | rest], p) do
    if cross(a, b, p) <= 0, do: drop([a | rest], p), else: [b, a | rest]
  end

  defp drop(acc, _p), do: acc

  defp cross({ax, ay}, {bx, by}, {cx, cy}), do: (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

  # A point in a convex polygon (counterclockwise), with a margin; a base
  # of one or two points (a line) is no base unless the point is on it.
  defp inside?([_, _, _ | _] = poly, p, margin) do
    Enum.zip(poly, tl(poly) ++ [hd(poly)])
    |> Enum.all?(fn {a, b} ->
      {ax, ay} = a
      {bx, by} = b
      l = :math.sqrt((bx - ax) ** 2 + (by - ay) ** 2)
      l == 0 or cross(a, b, p) / l >= -margin
    end)
  end

  defp inside?(poly, {px, py}, margin),
    do: Enum.any?(poly, fn {x, y} -> abs(x - px) <= margin and abs(y - py) <= margin end)

  defp box(points) do
    {xs, ys} = Enum.unzip(points)
    {{Enum.min(xs), Enum.min(ys)}, {Enum.max(xs), Enum.max(ys)}}
  end

  # The size of a cell of the grid of the overlap check (m), and the most
  # cells of a mesh in the grid.
  @cell 0.25
  @cells 4096

  @doc """
  The parts of a model that are in one place: `:ok`, or `{:error,
  {:overlap, [{name, name}]}}`. Two parts are in one place when their
  boxes share more than half of the smaller box, and the center of a mesh
  of one is inside a closed mesh of the other (a box test only would see
  the drum of a dryer in its body, or the spokes in a tire).
  """
  def overlaps(item) do
    joined = joined(item)

    # Each mesh with the name of its part and its box, in the cells of a
    # grid of 0.25 m that its box meets: a mesh meets only the meshes in
    # its cells (so a house of 7,000 bricks and their joints is fast).
    meshes =
      for {{f, p}, n} <- Enum.with_index(Build.placed(item)), p.kind not in @fasteners, m <- p.shapes, m.skin == nil do
        {{n, p.name}, bounds(Enum.map(m.points, &Frame.point(f, &1))), {m, f}}
      end
      |> Enum.with_index(fn m, i -> {i, m} end)
      |> Map.new()

    # A large mesh (the ground of a street, a building) meets too many
    # cells: it goes to each other mesh with no grid.
    {large, small} = Enum.split_with(meshes, fn {_, {_, box, _}} -> count(box) > @cells end)

    cells =
      Enum.reduce(small, %{}, fn {i, {_, box, _}}, acc ->
        Enum.reduce(cells(box), acc, &Map.update(&2, &1, [i], fn l -> [i | l] end))
      end)

    # The pairs of meshes of two parts that a connection does not join,
    # with boxes in one place; then a point inside one in the other.
    pairs = for {_, ids} <- cells, [i | rest] <- tails(Enum.sort(ids)), j <- rest, do: {i, j}
    wide = for {i, _} <- large, j <- Map.keys(meshes), j != i, do: {min(i, j), max(i, j)}

    near =
      Enum.uniq(pairs ++ wide)
      |> Enum.filter(fn {i, j} ->
        {{{n, a}, ba, _}, {{k, b}, bb, _}} = {meshes[i], meshes[j]}
        n != k and not MapSet.member?(joined, pair(a, b)) and same?(ba, bb)
      end)

    solids =
      near
      |> Enum.flat_map(&Tuple.to_list/1)
      |> Enum.uniq()
      |> Map.new(fn i ->
        {m, f} = elem(meshes[i], 2)
        {i, solid(m, f)}
      end)

    pairs =
      for {i, j} <- near,
          into?([solids[i]], [solids[j]]) or into?([solids[j]], [solids[i]]),
          do: pair(elem(elem(meshes[i], 0), 1), elem(elem(meshes[j], 0), 1))

    if pairs == [], do: :ok, else: {:error, {:overlap, pairs |> Enum.uniq() |> Enum.sort()}}
  end

  # The cells of the grid that a box meets.
  defp count({{x0, y0, z0}, {x1, y1, z1}}) do
    c = fn v -> floor(v / @cell) end
    (c.(x1) - c.(x0) + 1) * (c.(y1) - c.(y0) + 1) * (c.(z1) - c.(z0) + 1)
  end

  defp cells({{x0, y0, z0}, {x1, y1, z1}}) do
    c = fn v -> floor(v / @cell) end
    for i <- c.(x0)..c.(x1), j <- c.(y0)..c.(y1), k <- c.(z0)..c.(z1), do: {i, j, k}
  end

  # The tails of a list: [1, 2, 3] gives [[1, 2, 3], [2, 3], [3]].
  defp tails([]), do: []
  defp tails([_ | rest] = l), do: [l | tails(rest)]

  # A mesh at its place: a point inside it, and its triangles. For a
  # closed mesh the point is the center of its volume, or (a ring, where
  # the center is in the hole) a point 1 mm inside its first face. An open
  # mesh has no inside: no point, and no triangles. (A skin,
  # `World.Mesh.skin/3`, is not checked.)
  defp solid(mesh, f) do
    case Mass.mesh(mesh) do
      {_, center} ->
        pts = mesh.points |> Enum.map(&Frame.point(f, &1)) |> List.to_tuple()

        tris =
          for [a | rest] <- mesh.faces,
              [b, c] <- Enum.chunk_every(rest, 2, 1, :discard),
              do: {elem(pts, a), elem(pts, b), elem(pts, c)}

        {a, b, c} = hd(tris)
        mid = Vec.scale(Vec.add(Vec.add(a, b), c), 1 / 3)
        n = Vec.scale(Vec.norm(Vec.cross(Vec.sub(b, a), Vec.sub(c, a))), 0.001)

        probes =
          [Frame.point(f, center), Vec.add(mid, n), Vec.sub(mid, n)]
          |> Enum.filter(&World.Contact.inside?(&1, tris))
          |> Enum.take(1)

        {probes, tris}

      nil ->
        {[], []}
    end
  end

  # A point inside a mesh of `a` is inside a closed mesh of `b`.
  defp into?(a, b),
    do:
      Enum.any?(a, fn {ps, _} ->
        Enum.any?(ps, fn p -> Enum.any?(b, fn {_, tris} -> tris != [] and World.Contact.inside?(p, tris) end) end)
      end)

  # The pairs of the names of the parts that a connection joins: each
  # part of a node with each part of the node that it connects to, and
  # the parts of the nodes on one port of a node.
  defp joined(%Assembly{nodes: nodes}) do
    items = Map.new(nodes, fn {name, item, _} -> {name, item} end)

    own =
      for {_, item, %Assembly.Connection{to: to}} <- nodes,
          a <- names(item),
          b <- names(items[to]),
          into: MapSet.new(),
          do: pair(a, b)

    # The nodes on one port of a node clamp on one thing (a grip, a lever
    # and a mirror on a bar): they touch.
    ports = for {_, item, %Assembly.Connection{to: to, at: at}} <- nodes, is_binary(at), do: {{to, at}, item}

    same =
      for {_, group} <- Enum.group_by(ports, &elem(&1, 0), &elem(&1, 1)),
          {x, i} <- Enum.with_index(group),
          y <- Enum.drop(group, i + 1),
          a <- names(x),
          b <- names(y),
          into: own,
          do: pair(a, b)

    Enum.reduce(nodes, same, fn {_, item, _}, acc -> MapSet.union(acc, joined(item)) end)
  end

  defp joined(_item), do: MapSet.new()

  defp names(%Part{name: name}), do: [name]
  defp names(%Assembly{nodes: nodes}), do: Enum.flat_map(nodes, fn {_, item, _} -> names(item) end)
  defp names(_item), do: []

  defp pair(a, b), do: {min(a, b), max(a, b)}

  defp bounds(points) do
    {xs, ys, zs} = {Enum.map(points, &elem(&1, 0)), Enum.map(points, &elem(&1, 1)), Enum.map(points, &elem(&1, 2))}
    {{Enum.min(xs), Enum.min(ys), Enum.min(zs)}, {Enum.max(xs), Enum.max(ys), Enum.max(zs)}}
  end

  # Two boxes in one place: their shared box is more than half of the
  # smaller box.
  defp same?({lo1, hi1}, {lo2, hi2}) do
    shared = volume(each(lo1, lo2, &max/2), each(hi1, hi2, &min/2))
    small = min(volume(lo1, hi1), volume(lo2, hi2))
    small > 0 and shared > small / 2
  end

  defp each({a1, a2, a3}, {b1, b2, b3}, f), do: {f.(a1, b1), f.(a2, b2), f.(a3, b3)}

  defp volume({x0, y0, z0}, {x1, y1, z1}), do: max(x1 - x0, 0.0) * max(y1 - y0, 0.0) * max(z1 - z0, 0.0)

  @doc """
  Each value of a pose in the limits of its joint: `:ok`, or `{:error,
  {:joints, [name]}}`. Only the joints of the assemblies are checked (the
  joints of a person stay in their limits: `World.Joint`); an order
  checks that each name is a joint (`World.Orders`).
  """
  def joints(item, pose) do
    known = joints_of(item)

    out =
      for {name, value} <- pose,
          j = known[name],
          j != nil and Joint.clamp(j, nil, value / 1) != value / 1,
          do: name

    if out == [], do: :ok, else: {:error, {:joints, Enum.sort(out)}}
  end

  defp joints_of(%Assembly{nodes: nodes}) do
    Enum.reduce(nodes, %{}, fn
      {name, item, %Assembly.Connection{kind: kind, limits: limits, role: role}}, acc when kind != :fixed ->
        acc |> Map.put(name, Joint.new(name, kind, role: role, limits: limits)) |> Map.merge(joints_of(item))

      {_, item, _}, acc ->
        Map.merge(acc, joints_of(item))
    end)
  end

  defp joints_of(_item), do: %{}

  @doc """
  If a model goes through a door of a width and a height (m): `:ok`, or
  `{:error, {:door, size, door}}`.
  """
  def fits(item, {w, h} = door) do
    points = for {f, p} <- Build.placed(item), m <- p.shapes, pt <- m.points, do: Frame.point(f, pt)

    case points do
      [] ->
        :ok

      _ ->
        {lo, hi} = bounds(points)
        [a, b, _] = Vec.sub(hi, lo) |> Tuple.to_list() |> Enum.sort()
        {small, big} = {min(w, h), max(w, h)}
        if a <= small and b <= big, do: :ok, else: {:error, {:door, Vec.sub(hi, lo), door}}
    end
  end

  @doc """
  The text of a reason of `model/2`, for a person who reads the answer to
  an order.

      iex> World.Check.message({:joints, ["door"]})
      "a joint is out of its limits: door"
  """
  def message({:tips, {x, y}, _base}),
    do: "it does not stand: its center of mass (#{mm(x)}, #{mm(y)} mm) is not over its base"

  def message({:overlap, pairs}),
    do: "parts are in one place: " <> Enum.map_join(pairs, ", ", fn {a, b} -> "#{a} and #{b}" end)

  def message({:joints, names}), do: "a joint is out of its limits: " <> Enum.join(names, ", ")

  def message({:door, {x, y, z}, {w, h}}),
    do:
      "it does not go through the door of its workshop (#{mm(w)} by #{mm(h)} mm): it is #{mm(x)} by #{mm(y)} by #{mm(z)} mm"

  defp mm(v), do: round(v * 1000)
end
