defmodule World.Vec do
  @moduledoc """
  Vectors of three floats: `{x, y, z}`. The axes of World: x to the right
  side of a model, y to its front, z up, in meters.
  """

  @type t :: {float, float, float}

  def add({a, b, c}, {x, y, z}), do: {a + x, b + y, c + z}
  def sub({a, b, c}, {x, y, z}), do: {a - x, b - y, c - z}
  def scale({x, y, z}, k), do: {x * k, y * k, z * k}
  def dot({a, b, c}, {x, y, z}), do: a * x + b * y + c * z
  def cross({a, b, c}, {x, y, z}), do: {b * z - c * y, c * x - a * z, a * y - b * x}
  def len(v), do: :math.sqrt(dot(v, v))
  def lerp(a, b, t), do: add(a, scale(sub(b, a), t))
  def neg({x, y, z}), do: {-x, -y, -z}

  @doc "The vector with a length of 1. A vector of length 0 gives +z."
  def norm(v) do
    l = len(v)
    if l < 1.0e-12, do: {0.0, 0.0, 1.0}, else: scale(v, 1 / l)
  end

  @doc "The same vector with floats (the core of Wings needs floats)."
  def float({x, y, z}), do: {x / 1, y / 1, z / 1}

  @doc "The mean of a list of points."
  def mean([_ | _] = ps), do: scale(Enum.reduce(ps, &add/2), 1 / length(ps))

  @doc "A unit vector at a right angle to `v`."
  def perpendicular(v) do
    {x, y, z} = norm(v)
    other = if abs(z) < 0.9, do: {0.0, 0.0, 1.0}, else: {1.0, 0.0, 0.0}
    norm(cross({x, y, z}, other))
  end

  @doc "The box of a list of points: `{min, max}`."
  def bounds([{x, y, z} | rest]) do
    Enum.reduce(rest, {{x, y, z}, {x, y, z}}, fn {a, b, c}, {{x0, y0, z0}, {x1, y1, z1}} ->
      {{min(a, x0), min(b, y0), min(c, z0)}, {max(a, x1), max(b, y1), max(c, z1)}}
    end)
  end
end
