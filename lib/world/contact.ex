defmodule World.Contact do
  @moduledoc """
  The contact of a body with the things round it: a person leans as far
  as they want, and stops where the body touches a thing.

  - An obstacle is a closed mesh at its place (`solid/2`: its triangles
    and its box), or a function of a point that is true where the thing
    is (the wall of a basket with an opening in its front).
  - `blocked?/2`: a point is in an obstacle. A point is in a closed mesh
    when a ray from it goes through its faces an odd count of times
    (`inside?/2`).
  - `points/1`: the points of the skin of a figure in its pose, in the
    axes of the figure.
  - `reach/3`: the most of a move (0 to 1) before a point of the body is
    in an obstacle: in equal parts to the first touch, then by halves.
  - `lean/5`: a figure turns its joints to the values that it wants, and
    stops at the first touch.
  """
  alias World.{Figure, Frame, Mesh, Scene, Vec}

  @doc """
  A closed mesh at the frame `f` as an obstacle: `{:solid, {lo, hi},
  triangles}`.
  """
  def solid(%Mesh{} = mesh, f \\ Frame.identity()) do
    pts = mesh.points |> Enum.map(&Frame.point(f, &1)) |> List.to_tuple()

    tris =
      for [a | rest] <- mesh.faces,
          [b, c] <- Enum.chunk_every(rest, 2, 1, :discard),
          do: {elem(pts, a), elem(pts, b), elem(pts, c)}

    {:solid, Vec.bounds(Tuple.to_list(pts)), tris}
  end

  @doc """
  The point `p` is in an obstacle of the list: in the box and inside the
  triangles of a solid, or where a function is true.

      iex> box = World.Contact.solid(World.Shape.box({0, 0, 0}, {1, 1, 1}, :wood))
      iex> {World.Contact.blocked?({0.5, 0.5, 0.5}, [box]), World.Contact.blocked?({2.0, 0.5, 0.5}, [box])}
      {true, false}
  """
  def blocked?(p, obstacles), do: Enum.any?(obstacles, &in?(p, &1))

  defp in?(p, f) when is_function(f, 1), do: f.(p)

  defp in?({x, y, z} = p, {:solid, {{x0, y0, z0}, {x1, y1, z1}}, tris}),
    do: x >= x0 and x <= x1 and y >= y0 and y <= y1 and z >= z0 and z <= z1 and inside?(p, tris)

  # The ray is not along an axis, so it does not go along the edge of a
  # face of a box.
  @ray Vec.norm({0.5773, 0.5791, 0.5751})

  @doc "The point `p` is inside the closed triangles `tris` (`{a, b, c}`): a ray from it goes through them an odd count of times."
  def inside?(p, tris), do: tris |> Enum.count(&hit?(p, &1)) |> rem(2) == 1

  # Möller and Trumbore: the ray from `o` goes through the triangle.
  defp hit?(o, {a, b, c}) do
    {e1, e2} = {Vec.sub(b, a), Vec.sub(c, a)}
    h = Vec.cross(@ray, e2)
    det = Vec.dot(e1, h)
    s = Vec.sub(o, a)
    q = Vec.cross(s, e1)

    {u, v, t} =
      if det == 0, do: {-1.0, -1.0, -1.0}, else: {Vec.dot(s, h) / det, Vec.dot(@ray, q) / det, Vec.dot(e2, q) / det}

    u >= 0 and v >= 0 and u + v <= 1 and t > 1.0e-9
  end

  @doc """
  The points of the skin of a figure in its pose, in the axes of the
  figure: each point of each skinned mesh moved by its bones and their
  weights.
  """
  def points(%Figure{nodes: nodes, skins: skins}) do
    frames = Scene.world_frames(%Scene{nodes: nodes})

    for n <- nodes, n.skin != nil, skin = Enum.at(skins, n.skin), p <- n.primitives do
      bones =
        skin.joints
        |> Enum.zip(skin.inverse_bind)
        |> Enum.map(fn {j, ib} -> Frame.compose(frames[j], ib) end)
        |> List.to_tuple()

      for {pt, js, ws} <- Enum.zip([p.positions, p.joints, p.weights]) do
        Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
        |> Enum.map(fn {j, w} -> Vec.scale(Frame.point(elem(bones, j), pt), w) end)
        |> Enum.reduce(&Vec.add/2)
      end
    end
    |> List.flatten()
  end

  @doc """
  The most of a move before the body touches an obstacle: `at` gives the
  points of the body at a share `t` of the move (0 to 1); the result is
  the largest `t` before the first touch, to 1/(16 · 2^`steps`) (0 when the
  body touches at the start, 1 when it never touches). The move goes in
  16 equal parts to the first part with a touch, then by halves in that
  part: a thin obstacle (a slat) does not let the body through.

      iex> wall = fn {x, _, _} -> x > 1.0 end
      iex> t = World.Contact.reach(fn t -> [{2.0 * t, 0.0, 0.0}] end, [wall])
      iex> abs(t - 0.5) < 0.001
      true
  """
  def reach(at, obstacles, steps \\ 8) do
    free = fn t -> not Enum.any?(at.(t), &blocked?(&1, obstacles)) end

    case Enum.find(0..16, &(not free.(&1 / 16))) do
      nil ->
        1.0

      0 ->
        0.0

      k ->
        Enum.reduce(1..steps, {(k - 1) / 16, k / 16}, fn _, {lo, hi} ->
          mid = (lo + hi) / 2
          if free.(mid), do: {mid, hi}, else: {lo, mid}
        end)
        |> elem(0)
    end
  end

  @doc """
  A figure that leans as far as it wants: each joint value of `values`
  (`World.People.Joints`, such as `"spine.flex"`) goes from 0 to its
  value by the same share, and the figure stops at the largest share
  with no point of its skin in an obstacle. `place` puts the figure in
  the axes of the obstacles. The result is `{figure, share}`: the figure
  in its last free pose (`World.Figure.pose/3`), and the share (1 when
  it never touches).
  """
  def lean(f, values, obstacles, place \\ Frame.identity(), steps \\ 8)
  def lean(%Figure{} = f, values, _, _, _) when values == %{}, do: {f, 1.0}

  def lean(%Figure{} = f, values, obstacles, place, steps) do
    posed = fn t -> Figure.pose(f, Map.new(values, fn {k, v} -> {k, v * t} end), %{}) end
    at = fn t -> t |> posed.() |> points() |> Enum.map(&Frame.point(place, &1)) end
    t = reach(at, obstacles, steps)
    {posed.(t), t}
  end
end
