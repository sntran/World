defmodule World.Surface do
  @moduledoc """
  The surface data of a building, for the wall shader of an app (the
  request W23 of Vũng Tàu: the damp at the bottom of a wall and the
  streaks at its corners):

  - The UVs (`TEXCOORD_0`) are in meters, a box projection on the axis
    of the normal: a face that looks along x has `{y, z}`, a face that
    looks along y has `{x, z}`, and a face that looks up or down has
    `{x, y}`. A pattern of bricks or tiles has its real size.
  - The height above the ground and the horizontal distance to the
    nearest corner of the building, in meters, are in `TEXCOORD_1`, and
    scaled in `COLOR_0`: red is the height over 32 m, green is the
    distance over 4 m (each 1 at most), blue is 0 and alpha is 1. These
    are numbers for the shader, not colors.

  The corners are the vertical edges of the building in plan (`{x, y}`).
  A model with `"surface" => %{"corners" => [[x, y], ...]}` in its extras
  gets the data in its build (`World.Build.scene/2`). A wall needs a
  point at each corner, at 4 m from it and at its middle, so that the
  distance changes along it as it does on the real wall. A node with
  instances keeps no data: the same mesh is at many places.
  """
  alias World.{Frame, Scene, Vec}

  @height 32.0
  @reach 4.0

  @doc "The height (m) that is 1 in the red of `COLOR_0`."
  def height_scale, do: @height

  @doc "The distance to a corner (m) that is 1 in the green of `COLOR_0`."
  def reach_scale, do: @reach

  @doc """
  The data of each point of each primitive of the scene, from the place
  of the point at rest and its normal.
  """
  def apply(%Scene{} = scene, corners) do
    corners = Enum.map(corners, fn [x, y] -> {x / 1, y / 1} end)
    frames = Scene.world_frames(scene)

    nodes =
      for {n, i} <- Enum.with_index(scene.nodes) do
        if n.instances,
          do: n,
          else: %{n | primitives: Enum.map(n.primitives, &primitive(&1, frames[i], corners))}
      end

    %{scene | nodes: nodes}
  end

  defp primitive(%Scene.Primitive{} = p, f, corners) do
    {uvs, uvs2, data} =
      Enum.zip(p.positions, p.normals)
      |> Enum.map(fn {pt, n} -> point(Frame.point(f, pt), Frame.dir(f, n), corners) end)
      |> unzip3()

    %{p | uvs: uvs, uvs2: uvs2, data: data}
  end

  @doc """
  The data of one point `p` with the normal `n`, in the axes of the
  model: `{uv, uv2, data}`.

      iex> World.Surface.point({1.0, 2.0, 8.0}, {0.0, 1.0, 0.0}, [{0.0, 2.0}, {3.0, 2.0}])
      {{1.0, 8.0}, {8.0, 1.0}, {0.25, 0.25, 0.0, 1.0}}
  """
  def point({x, y, z} = p, n, corners) do
    uv = box(p, n)
    d = corners |> Enum.map(fn {cx, cy} -> Vec.len({x - cx, y - cy, 0.0}) end) |> Enum.min(fn -> 0.0 end)
    {uv, {z, d}, {min(max(z, 0.0) / @height, 1.0), min(d / @reach, 1.0), 0.0, 1.0}}
  end

  defp box({x, y, z}, {nx, ny, nz}) do
    {ax, ay, az} = {abs(nx), abs(ny), abs(nz)}

    cond do
      az >= ax and az >= ay -> {x, y}
      ax >= ay -> {y, z}
      true -> {x, z}
    end
  end

  defp unzip3(list),
    do: {Enum.map(list, &elem(&1, 0)), Enum.map(list, &elem(&1, 1)), Enum.map(list, &elem(&1, 2))}
end
