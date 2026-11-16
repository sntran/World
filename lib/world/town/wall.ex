defmodule World.Town.Wall do
  @moduledoc """
  A wall of a building with its own axes
  (`docs/plans/0018-quang-trung-street.md`, section 11): a place on the
  wall is the way along it (`s`, m from its first corner) and the height
  (`z`). The functions give edits of a sculpture (`World.Skills.Sculpt`)
  at such a place: a box, a paint, a window. So the same words make a
  front on a wall of any direction.

  `n` is the direction out of the building, and `t` the direction along
  the wall.
  """

  defstruct [:a, :long, :t, :n]

  @doc """
  The wall from the corner `a` to the corner `b` (each `[x, y]`, m) of a
  plan with its corners counterclockwise (seen from above): the
  building is at the left of the way from `a` to `b`. So `s` goes from
  the left to the right for a person in front of the wall.
  """
  def new([ax, ay], [bx, by]) do
    {dx, dy} = {bx - ax, by - ay}
    long = :math.sqrt(dx * dx + dy * dy)
    {tx, ty} = {dx / long, dy / long}
    %__MODULE__{a: {ax * 1.0, ay * 1.0}, long: long, t: {tx, ty}, n: {ty, -tx}}
  end

  @doc "The wall moved out by `d` (a part of a front that stands out)."
  def out(%__MODULE__{a: {ax, ay}, n: {nx, ny}} = w, d), do: %{w | a: {ax + nx * d, ay + ny * d}}

  @doc "The point `[x, y, z]` of a place on the wall, `out` from it (less than 0: in the building)."
  def at(%__MODULE__{a: {ax, ay}, t: {tx, ty}, n: {nx, ny}}, s, z, out \\ 0.0),
    do: [r4(ax + tx * s + nx * out), r4(ay + ty * s + ny * out), r4(z)]

  @doc "The direction out of the wall, as the axis of an edit."
  def axis(%__MODULE__{n: {nx, ny}}), do: [Float.round(nx, 6) + 0.0, Float.round(ny, 6) + 0.0, 0]

  @doc """
  A box on the wall: `wide` along it and `high`, about the place, `deep`
  through it. The key `out` of `more` moves its middle out of the wall;
  each other key of `more` is a key of the edit.
  """
  def box(%__MODULE__{} = w, s, z, {wide, high, deep}, color, more \\ %{}) do
    {out, more} = Map.pop(more, "out", 0.0)

    edit(
      "box",
      [r4(wide / 2), r4(high / 2), r4(deep / 2)],
      at(w, s, z, out),
      color,
      Map.merge(%{"axis" => axis(w), "up" => [0, 0, 1]}, more)
    )
  end

  @doc "A paint on the wall, `wide` and `high` about the place (with `raise`, a relief)."
  def paint(%__MODULE__{} = w, s, z, {wide, high}, color, more \\ %{}),
    do: box(w, s, z, {wide, high, 0.5}, color, Map.merge(%{"mode" => "paint", "blend" => 0.01}, more))

  @doc """
  A window: glass in a hollow of 6 cm, a frame round it, and `bars`
  upright bars.
  """
  def window(%__MODULE__{} = w, s, z, {wide, high}, glass, frame, bars \\ 1) do
    [
      paint(w, s, z, {wide + 0.16, high + 0.16}, frame, %{"raise" => 0.015, "roughness" => 0.6}),
      paint(w, s, z, {wide, high}, glass, %{"raise" => -0.06, "roughness" => 0.1, "metal" => 0.2})
      | for i <- 1..bars//1 do
          paint(w, s - wide / 2 + wide * i / (bars + 1), z, {0.05, high}, frame, %{"blend" => 0.006, "roughness" => 0.6})
        end
    ]
  end

  @doc """
  An edit of a sculpture: a shape with its size, its place and its
  color, and the keys of `more`. A `raise` has a blend that is not
  smaller than it.
  """
  def edit(shape, size, at, color, more \\ %{}) do
    edit = Map.merge(%{"shape" => shape, "size" => size, "at" => at, "color" => color}, more)

    case edit do
      %{"raise" => h} -> Map.put(edit, "blend", max(Map.get(edit, "blend", 0), abs(h)))
      _ -> edit
    end
  end

  @doc "A tube through points (each `[x, y, z]`), with one radius for each point."
  def tube(points, radii, color, more \\ %{}) do
    Map.merge(
      %{"shape" => "tube", "size" => %{"points" => points, "radii" => Enum.map(radii, &r4/1)}, "color" => color},
      more
    )
  end

  @doc """
  An extrude of an outline (points `[a, b]`), `depth` deep, with its
  middle at `at`. Without an axis in `more`, the outline is a plan, and
  the depth is its height.
  """
  def outline(points, depth, at, color, more \\ %{}) do
    size = %{"outline" => Enum.map(points, fn [a, b] -> [r4(a), r4(b)] end), "depth" => r4(depth)}
    edit("extrude", size, Enum.map(at, &r4/1), color, more)
  end

  @doc "A number with four places after the point (a whole number stays; no zero with a minus sign)."
  def r4(v) when is_integer(v), do: v
  def r4(v), do: Float.round(v * 1.0, 4) + 0.0
end
