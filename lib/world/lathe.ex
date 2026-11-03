defmodule World.Lathe do
  @moduledoc """
  The lathe of the world (`docs/world.md`, step P2): a turner turns a
  part from a profile around an axis, as a potter turns a cup on a wheel
  or a turner turns a post of wood.

  A profile is the line of the outside of a part, from the axis at its
  foot (`{0, z}`) to its top: a list of points `{r, z}` in meters (`r`
  from the axis, `z` up). The lathe makes a smooth curve through the
  points (Catmull-Rom), with more steps near and fewer far away, and the
  sides of the turn come from the level of detail (`World.Detail.sides/1`:
  48 near, fewer at mid and far).

  A solid part (a post) has its top on the axis. A vessel (a cup, a
  bowl, a bottle, a pot) has a `wall`: the inside is the outside moved in
  by the wall, down to the `floor` (the thickness of its bottom). The
  section of the part is then the outside, the rim, and the inside down
  to the axis: a closed area that turns into a closed mesh.

  The volume of a part comes from its section by the theorem of Pappus:
  the area of the section times the length of the path of its centroid
  (`volume/1`). The capacity of a vessel is the volume of its inside, to
  the rim (`capacity/1`).
  """
  alias World.{Assembly, Detail, Part, Shape}

  @doc """
  The points of a smooth curve through the points of a profile
  (Catmull-Rom), with `steps` points for each span (the level of detail:
  fewer at mid and far), and the first and the last points as they are.

      iex> c = World.Lathe.curve([{0.0, 0.0}, {1.0, 1.0}, {2.0, 0.0}], 4)
      iex> {length(c), Enum.at(c, 4), List.last(c)}
      {9, {1.0, 1.0}, {2.0, 0.0}}
  """
  def curve([_, _ | _] = points, steps) do
    t = List.to_tuple(points)
    n = tuple_size(t)
    at = fn i -> elem(t, min(max(i, 0), n - 1)) end

    spans =
      for i <- 0..(n - 2), s <- 0..(steps - 1) do
        catmull(at.(i - 1), at.(i), at.(i + 1), at.(i + 2), s / steps)
      end

    spans ++ [at.(n - 1)]
  end

  defp catmull({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, u) do
    c = fn p0, p1, p2, p3 ->
      0.5 *
        (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)
    end

    {max(c.(x0, x1, x2, x3), 0.0), c.(y0, y1, y2, y3)}
  end

  @doc """
  The section of a part: the closed area to turn, from the curve of its
  outside. With no wall, the top closes on the axis. With a `wall`, the
  inside is the outside moved in by the wall (along the normal of the
  curve), down to `floor` over the foot.

      iex> World.Lathe.section([{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}])
      [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}]
  """
  def section(outside, opts \\ []) do
    {_, z0} = hd(outside)
    {_, top} = List.last(outside)

    case Keyword.get(opts, :wall) do
      nil ->
        outside ++ [{0.0, top}]

      wall ->
        floor = z0 + Keyword.get(opts, :floor, wall)

        inside =
          outside
          |> inward(wall)
          |> Enum.filter(fn {r, z} -> r > 1.0e-4 and z > floor end)

        outside ++ Enum.reverse(inside) ++ [{0.0, floor}]
    end
  end

  # Each point of a curve moved in by `d`: to the left of the way of the
  # curve (the way up the outside of a part: to the axis).
  defp inward(points, d) do
    t = List.to_tuple(points)
    n = tuple_size(t)

    for i <- 0..(n - 1) do
      {r0, z0} = elem(t, max(i - 1, 0))
      {r1, z1} = elem(t, min(i + 1, n - 1))
      {r, z} = elem(t, i)
      {dr, dz} = {r1 - r0, z1 - z0}
      l = :math.sqrt(dr * dr + dz * dz)
      {r - d * dz / l, z + d * dr / l}
    end
  end

  @doc """
  The volume of a section turned around the axis (m³), by the theorem of
  Pappus: the area of the section times the length of the path of its
  centroid (2π times its distance from the axis).

      iex> # A cylinder of radius 1 and height 1.
      iex> Float.round(World.Lathe.volume([{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}]), 6)
      3.141593
  """
  def volume(section) do
    pairs = Enum.zip(section, tl(section) ++ [hd(section)])
    cross = Enum.map(pairs, fn {{r0, z0}, {r1, z1}} -> {r0 * z1 - r1 * z0, r0 + r1} end)
    area = Enum.sum(Enum.map(cross, &elem(&1, 0))) / 2
    moment = Enum.sum(Enum.map(cross, fn {c, s} -> c * s end)) / 6
    if area == 0, do: 0.0, else: abs(2 * :math.pi() * moment)
  end

  @doc """
  The capacity of a vessel (m³): the volume of its inside, from the floor
  to the rim (the inside of its section turned around the axis).
  """
  def capacity(outside, opts) do
    floor = elem(hd(outside), 1) + Keyword.get(opts, :floor, opts[:wall])

    inside =
      outside |> inward(opts[:wall]) |> Enum.filter(fn {r, z} -> r > 1.0e-4 and z > floor end)

    {_, rim} = List.last(inside)
    volume([{0.0, floor}] ++ inside ++ [{0.0, rim}])
  end

  @doc """
  A turned part: an assembly of one part, the profile turned around the
  axis (z up), with its volume and, for a vessel, its capacity (liters)
  in its extras. The options: `wall` and `floor` (a vessel), `steps` (the
  points of each span of the curve near; 8 by default), `sides` (48 by
  default near), `sources`.
  """
  def turn(name, profile, material, opts \\ []) do
    steps = max(round(Keyword.get(opts, :steps, 8) * Detail.sides(48) / 48), 1)
    outside = curve(profile, steps)
    section = section(outside, opts)
    shape = Shape.lathe(section, material, sides: Keyword.get(opts, :sides, 48))
    {rs, zs} = Enum.unzip(profile)

    extras =
      %{
        "volume" => volume(section),
        "height" => Enum.max(zs) - Enum.min(zs),
        "diameter" => 2 * Enum.max(rs),
        "sources" => Keyword.get(opts, :sources, [])
      }
      |> Map.merge(if opts[:wall], do: %{"capacity" => 1000 * capacity(outside, opts)}, else: %{})

    # The port at the foot: the part stands on it.
    foot = Part.port("foot", {0.0, 0.0, elem(hd(profile), 1)}, {0.0, 0.0, -1.0}, {0.0, 1.0, 0.0})
    part = Part.new("body", :turned, shape, [foot], sources: extras["sources"])
    Assembly.new(name, part, kind: :turned, sources: extras["sources"], extras: Map.delete(extras, "sources"))
  end
end
