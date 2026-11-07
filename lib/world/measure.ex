defmodule World.Measure do
  @moduledoc """
  The measures of a model as the standards define the numbers of a real
  blueprint (plan 0003, D2), so that a test can compare the model that
  the people of World build with the numbers that a maker or an engineer
  published (`World.References`).

  `of/2` places the parts of a model at a level once (`World.Build`):
  each part with its path (the names of its nodes) and its points in the
  axes of the model, and each joint with its role and its point. The
  measures read it:

  - the box (`box/2`) and its `length` (y), `width` (x) and `height`
    (z), with the nodes `without` it (the mirrors: the width of SAE J1100
    has no mirrors);
  - the axles (the joints of the role `wheel`), the `wheelbase` (SAE
    J1100: from the front axle to the rear axle) and the `track` of the
    front or the rear axle (from the center of one wheel to the other);
  - the `ground_clearance`: the lowest point between the axles, with no
    wheel, no tire and no knuckle (the nodes `without` it);
  - the `top` of a node (the seat height of a two-wheeler: the top of its
    seat at the place of the rider, `top/3` with a span of y);
  - a `port` of a node in the axes of the model (the geometry of a
    bicycle frame: its stack, its reach, its angles);
  - the curb `mass` (`World.Mass.of/2`);
  - the bill of quantities of a drawing (`takeoff/1`).
  """
  alias World.{Build, Frame, Mass, Vec}

  defstruct parts: [], joints: [], mass: 0.0

  @doc "The placed parts and joints of a model at a level."
  def of(item, level) do
    parts =
      for {path, frame, part, {shapes, _}} <- World.Detail.with(level, fn -> Build.elements(item, level) end),
          do: %{
            path: path,
            frame: frame,
            part: part,
            points: points(shapes, frame),
            faces: faces(shapes, frame)
          }

    scene = Build.scene(item, level: level)
    frames = frames(scene.nodes)

    joints =
      for {n, i} <- Enum.with_index(scene.nodes),
          role = n.extras["role"],
          do: %{name: n.name, role: role, at: Frame.point(frames[i], {0.0, 0.0, 0.0})}

    %__MODULE__{parts: parts, joints: joints, mass: Mass.of(item).mass}
  end

  defp points(shapes, frame), do: for(m <- shapes, p <- m.points, do: Frame.point(frame, p))

  # The faces of the meshes, each a list of its points in the axes of the model.
  defp faces(shapes, frame) do
    for m <- shapes, pts = List.to_tuple(m.points), f <- m.faces, do: for(i <- f, do: Frame.point(frame, elem(pts, i)))
  end

  defp frames(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {n, i}, acc ->
      Map.put(acc, i, if(n.parent, do: Frame.compose(acc[n.parent], n.frame), else: n.frame))
    end)
  end

  # The parts that are not in the nodes `without` (a path is a node, or
  # in a node: `name/...`).
  defp parts(m, without) do
    for p <- m.parts, not Enum.any?(without, &(p.path == &1 or String.starts_with?(p.path, &1 <> "/"))), do: p
  end

  @doc "The box of the points of the model, with the nodes `without` it: `{{x0, y0, z0}, {x1, y1, z1}}`."
  def box(m, without \\ []), do: Vec.bounds(for p <- parts(m, without), pt <- p.points, do: pt)

  @doc "The length (along y), the width (along x) or the height (along z) of the box (`box/2`)."
  def size(m, axis, without \\ []) do
    {{x0, y0, z0}, {x1, y1, z1}} = box(m, without)
    Map.fetch!(%{length: y1 - y0, width: x1 - x0, height: z1 - z0}, axis)
  end

  @doc "The points of the axles: the joints of the role `wheel`, from the front."
  def axles(m), do: m.joints |> Enum.filter(&(&1.role == "wheel")) |> Enum.map(& &1.at) |> Enum.sort_by(&(-elem(&1, 1)))

  @doc "The wheelbase (SAE J1100, L101): from the front axle to the rear axle, along y."
  def wheelbase(m) do
    ys = for {_, y, _} <- axles(m), do: y
    Enum.max(ys) - Enum.min(ys)
  end

  @doc "The track (SAE J1100, W101 and W102) of the `:front` or the `:rear` axle: from the center of one wheel to the other."
  def track(m, which) do
    ys = for {_, y, _} <- axles(m), do: y
    y = if which == :front, do: Enum.max(ys), else: Enum.min(ys)
    xs = for {x, ay, _} <- axles(m), abs(ay - y) < 0.01, do: x
    Enum.max(xs) - Enum.min(xs)
  end

  @doc """
  The ground clearance: the lowest point of the model between the axles,
  with the nodes `without` it (the wheels, the tires, the knuckles).
  """
  def ground_clearance(m, without) do
    ys = for {_, y, _} <- axles(m), do: y
    {lo, hi} = {Enum.min(ys), Enum.max(ys)}

    Enum.min(
      for p <- parts(m, without),
          face <- p.faces,
          clipped = clip(clip(face, lo, 1), hi, -1),
          {_, _, z} <- clipped,
          do: z
    )
  end

  # The part of a face on one side of the plane y = `at` (`side` 1: y >=
  # at; -1: y <= at), by the cut of each edge that crosses it.
  defp clip([], _at, _side), do: []

  defp clip(face, at, side) do
    inside? = fn {_, y, _} -> side * (y - at) >= 0 end

    face
    |> Enum.zip(tl(face) ++ [hd(face)])
    |> Enum.flat_map(fn {a, b} ->
      cut =
        if inside?.(a) != inside?.(b) do
          {_, ya, _} = a
          {_, yb, _} = b
          [Vec.lerp(a, b, (at - ya) / (yb - ya))]
        else
          []
        end

      if(inside?.(a), do: [a], else: []) ++ cut
    end)
  end

  @doc """
  The top of a node (the most z of its points): of all of it, or only of
  its points with y from `y0` to `y1` (the place of the rider on a seat).
  """
  def top(m, node, span \\ nil) do
    zs =
      for p <- parts(m, []),
          p.path == node or String.starts_with?(p.path, node <> "/"),
          {_, y, z} <- p.points,
          span == nil or (y >= elem(span, 0) and y <= elem(span, 1)),
          do: z

    Enum.max(zs)
  end

  @doc "A port of the root part of a node in the axes of the model: `{point, axis}`."
  def port(m, node, name) do
    p = Enum.find(m.parts, &(&1.path == node and Map.has_key?(&1.part.ports, name)))
    port = p.part.ports[name]
    {Frame.point(p.frame, port.at), Frame.dir(p.frame, port.axis)}
  end

  @doc "The curb mass of the model, in kg (`World.Mass.of/2`)."
  def mass(m), do: m.mass

  @doc """
  The bill of quantities of a drawing (a full drawing of a job): the sum
  of the takeoff of each of its tasks (`World.Drawing.materials/3`), a
  name of the stock to its count. A node that others take in `from` is
  made at far, for its data.
  """
  def takeoff(raw) do
    taken = MapSet.new(for n <- raw["nodes"], f <- Map.get(n, "from", []), do: f)

    {_, sum} =
      Enum.reduce(raw["nodes"], {%{}, %{}}, fn %{"name" => name}, {made, sum} ->
        inputs = World.Drawing.inputs(raw, name, made)
        sum = Map.merge(sum, World.Drawing.materials(raw, name, inputs), fn _, a, b -> a + b end)

        made =
          if MapSet.member?(taken, name),
            do: Map.put(made, name, World.Detail.with(:far, fn -> World.Drawing.make(raw, name, inputs) end)),
            else: made

        {made, sum}
      end)

    sum
  end
end
