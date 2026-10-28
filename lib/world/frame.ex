defmodule World.Frame do
  @moduledoc """
  A rigid place in space: a turn (a matrix of 3 columns, the x, y and z
  directions of the frame) and a point (the origin of the frame). A frame
  takes a point from its own axes to the axes of its parent.
  """
  alias World.Vec

  defstruct x: {1.0, 0.0, 0.0}, y: {0.0, 1.0, 0.0}, z: {0.0, 0.0, 1.0}, at: {0.0, 0.0, 0.0}

  @type t :: %__MODULE__{x: Vec.t(), y: Vec.t(), z: Vec.t(), at: Vec.t()}

  @doc "The frame that changes nothing."
  def identity, do: %__MODULE__{}

  @doc "A frame that only moves."
  def move(at), do: %__MODULE__{at: Vec.float(at)}

  @doc """
  A frame from a point, its z direction (`axis`) and its y direction
  (`up`). `up` changes a little to be at a right angle to `axis`.
  """
  def new(at, axis, up) do
    z = Vec.norm(axis)
    x = Vec.norm(Vec.cross(up, z))
    %__MODULE__{x: x, y: Vec.cross(z, x), z: z, at: Vec.float(at)}
  end

  @doc "A turn of `deg` degrees around a unit axis, at a point."
  def turn(axis, deg, at \\ {0.0, 0.0, 0.0}) do
    {x, y, z} = Vec.norm(axis)
    a = deg * :math.pi() / 180
    {c, s} = {:math.cos(a), :math.sin(a)}
    t = 1 - c

    col = fn {px, py, pz} ->
      {(t * x * x + c) * px + (t * x * y - s * z) * py + (t * x * z + s * y) * pz,
       (t * x * y + s * z) * px + (t * y * y + c) * py + (t * y * z - s * x) * pz,
       (t * x * z - s * y) * px + (t * y * z + s * x) * py + (t * z * z + c) * pz}
    end

    f = %__MODULE__{x: col.({1.0, 0.0, 0.0}), y: col.({0.0, 1.0, 0.0}), z: col.({0.0, 0.0, 1.0})}
    at = Vec.float(at)
    %{f | at: Vec.sub(at, dir(f, at))}
  end

  @doc "A point from the axes of the frame to the axes of its parent."
  def point(%__MODULE__{at: at} = f, p), do: Vec.add(at, dir(f, p))

  @doc "A direction from the axes of the frame to the axes of its parent."
  def dir(%__MODULE__{x: x, y: y, z: z}, {a, b, c}),
    do: Vec.add(Vec.add(Vec.scale(x, a), Vec.scale(y, b)), Vec.scale(z, c))

  @doc "`compose(a, b)`: first `b`, then `a`."
  def compose(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{x: dir(a, b.x), y: dir(a, b.y), z: dir(a, b.z), at: point(a, b.at)}
  end

  @doc "The frame that undoes `f`."
  def invert(%__MODULE__{x: {a, b, c}, y: {d, e, g}, z: {h, i, j}, at: at}) do
    f = %__MODULE__{x: {a, d, h}, y: {b, e, i}, z: {c, g, j}}
    %{f | at: Vec.neg(dir(f, at))}
  end

  @doc "The turn of the frame as a unit quaternion `{x, y, z, w}`."
  def quaternion(%__MODULE__{x: {m00, m10, m20}, y: {m01, m11, m21}, z: {m02, m12, m22}}) do
    trace = m00 + m11 + m22

    q =
      cond do
        trace > 0 ->
          s = :math.sqrt(trace + 1.0) * 2
          {(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s}

        m00 > m11 and m00 > m22 ->
          s = :math.sqrt(1.0 + m00 - m11 - m22) * 2
          {0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s}

        m11 > m22 ->
          s = :math.sqrt(1.0 + m11 - m00 - m22) * 2
          {(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s}

        true ->
          s = :math.sqrt(1.0 + m22 - m00 - m11) * 2
          {(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s}
      end

    {qx, qy, qz, qw} = q
    l = :math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    {qx / l, qy / l, qz / l, qw / l}
  end

  @doc "The frame of a unit quaternion `{x, y, z, w}`, at a point."
  def from_quaternion({x, y, z, w}, at) do
    %__MODULE__{
      x: {1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w)},
      y: {2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w)},
      z: {2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)},
      at: Vec.float(at)
    }
  end

  @doc """
  The frame at `k` (0 to 1) of the way from `a` to `b`: the turn on the
  shortest arc (slerp), and the point on the line.
  """
  def blend(%__MODULE__{} = a, %__MODULE__{} = b, k) do
    {ax, ay, az, aw} = quaternion(a)
    {bx, by, bz, bw} = quaternion(b)
    d = ax * bx + ay * by + az * bz + aw * bw
    # The two signs of a quaternion are the same turn: take the near one.
    {d, {bx, by, bz, bw}} = if d < 0, do: {-d, {-bx, -by, -bz, -bw}}, else: {d, {bx, by, bz, bw}}

    {p, q} =
      if d > 0.9995 do
        {1 - k, k}
      else
        o = :math.acos(d)
        {:math.sin((1 - k) * o) / :math.sin(o), :math.sin(k * o) / :math.sin(o)}
      end

    {x, y, z, w} = {p * ax + q * bx, p * ay + q * by, p * az + q * bz, p * aw + q * bw}
    l = :math.sqrt(x * x + y * y + z * z + w * w)
    from_quaternion({x / l, y / l, z / l, w / l}, Vec.lerp(a.at, b.at, k))
  end

  @doc "The 16 numbers of the frame as a 4 x 4 matrix, column by column."
  def matrix(%__MODULE__{x: {a, b, c}, y: {d, e, f}, z: {g, h, i}, at: {x, y, z}}),
    do: [a, b, c, 0.0, d, e, f, 0.0, g, h, i, 0.0, x, y, z, 1.0]
end
