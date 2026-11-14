defmodule World.Sculpt.Texture do
  @moduledoc """
  The surfaces of the edits of a sculpture
  (`docs/plans/0012-a-world-of-sites.md`, D3): the grain of wood, the
  ridges of bark, the strips of a weave. A flat color with one roughness
  looks like plastic; a real thing has a small relief, and its color and
  its roughness change from place to place.

  A surface is a function of a place: `at/3` gives the relief, the
  change of the color and the change of the finish there. The place is
  in the axes of the edit, in units of the scale of the surface (the
  size of one mark: a ring of the wood, a strip of the weave). So the
  grain of a leg of a chair goes along the leg, and turns with it. Only
  the maps have a surface (`World.Sculpt.Bake`): the mesh does not
  change.

  The kinds:

  | Kind | What it is | One mark (the scale by default) |
  |---|---|---|
  | `wood` | Rings round an axis next to the z of the edit, and streaks along it. | A ring: 6 mm. |
  | `bark` | Ridges along the z of the edit, with dark cracks. | A ridge: 30 mm. |
  | `brushed` | Fine lines along the z of the edit: a metal from a mill. | A line: 2 mm. |
  | `cast` | Small bumps: a cast metal, a forged head. | A bump: 3 mm. |
  | `plaster` | Soft bumps and patches: a wall with plaster. | A bump: 10 mm. |
  | `concrete` | Patches, fine grains and some pits. | A patch: 20 mm. |
  | `fabric` | The threads of a cloth, over and under, on the side that the surface faces. | A thread: 2 mm. |
  | `weave` | Strips over and under, flat across the z of the edit and pressed to its shape: a basket. | A strip: 20 mm. |
  | `leather` | A net of fine creases. | A cell: 4 mm. |
  | `rubber` | A fine grain with no shine. | A grain: 3 mm. |
  | `leaves` | Clumps, light at their tops and dark between them. | A clump: 120 mm. |
  | `stone` | Bumps of three sizes and spots. | A bump: 50 mm. |
  | `rust` | Patches of rust on a metal: brown, rough, no metal there. | A patch: 30 mm. |
  | `hair` | Strands that go out and down from the z of the edit (the top of a head), in locks: each strand has its height and its tone, and some are light. | A strand: 1.5 mm, at 9 cm from the z. |

  | `palm` | Leaves of palm that go out and down from the z of the edit (a nón lá): 40 blades, each with its tone and its fibers, and a dark line between two blades. | A fiber: 1 mm, at 6 cm from the z. |

  The height of a strand of `hair` (`strand/1`) is also how far it
  stands out of a mass of hair: the alpha of the image of a sculpture
  with strands is from it (`World.Sculpt.Bake`).
  """

  @kinds %{
    "wood" => {:wood, 0.006},
    "bark" => {:bark, 0.03},
    "brushed" => {:brushed, 0.002},
    "cast" => {:cast, 0.003},
    "plaster" => {:plaster, 0.01},
    "concrete" => {:concrete, 0.02},
    "fabric" => {:fabric, 0.002},
    "weave" => {:weave, 0.02},
    "leather" => {:leather, 0.004},
    "rubber" => {:rubber, 0.003},
    "leaves" => {:leaves, 0.12},
    "stone" => {:stone, 0.05},
    "rust" => {:rust, 0.03},
    "hair" => {:hair, 0.0015},
    "palm" => {:palm, 0.003}
  }

  # The color of rust (linear light is not needed: a mix of two colors of the image).
  @rust {120, 62, 30}

  @doc "The names of the kinds."
  def kinds, do: @kinds |> Map.keys() |> Enum.sort()

  @doc "The kind of a name (an atom) and its scale by default (m), or nil."
  def kind(name), do: @kinds[name]

  @doc """
  The surface of a kind at the place `q` (in the axes of the edit, in
  units of the scale), where the surface faces `n` (in the axes of the
  edit): `{height, tone, rough, metal, to}`.

  - `height`: the relief, in units of the scale (more is out).
  - `tone`: the color times this (1 for no change).
  - `rough`: this more roughness (0 for no change).
  - `metal`: the metal times this (1 for no change).
  - `to`: `{color, part}`, the part of a color of the kind that the
    surface has there (rust), or nil.
  """
  def at(:wood, {x, y, z}, _n) do
    # The middle of the tree is not in the part: the rings are arcs.
    {x, y} = {x + 7.3, y + 2.1}
    wobble = noise(x * 0.35, y * 0.35, z * 0.025)
    ring = frac(:math.sqrt(x * x + y * y) + 2.5 * wobble)
    # The late wood of a ring: a dark thin line.
    late = step(0.72, 0.9, ring) * (1.0 - step(0.93, 1.0, ring))
    streak = noise(x * 5.0, y * 5.0, z * 0.06) - 0.5
    {-0.05 * late + 0.03 * streak, 1.0 - 0.22 * late + 0.12 * streak, 0.06 * late, 1.0, nil}
  end

  def at(:bark, {x, y, z}, _n) do
    v = noise(x, y, z * 0.22) * 2.0 - 1.0
    # A crack is where the noise goes through its middle.
    crack = 1.0 - step(0.0, 0.3, abs(v))
    fine = noise(x * 3.1, y * 3.1, z * 1.3) - 0.5
    {-0.25 * crack + 0.06 * fine, 1.0 - 0.32 * crack + 0.16 * fine, 0.1 * crack, 1.0, nil}
  end

  def at(:brushed, {x, y, z}, _n) do
    v = noise(x, y, z * 0.03) - 0.5
    {0.04 * v, 1.0 + 0.08 * v, 0.12 * v, 1.0, nil}
  end

  def at(:cast, {x, y, z}, _n) do
    v = noise(x, y, z) - 0.5
    fine = noise(x * 2.7, y * 2.7, z * 2.7) - 0.5
    {0.07 * v + 0.035 * fine, 1.0 + 0.12 * v, 0.1 * (fine + 0.5), 1.0, nil}
  end

  def at(:plaster, {x, y, z}, _n) do
    v = noise(x * 0.5, y * 0.5, z * 0.5) - 0.5
    fine = noise(x * 2.0, y * 2.0, z * 2.0) - 0.5
    patch = noise(x * 0.08, y * 0.08, z * 0.08) - 0.5
    {0.1 * v + 0.04 * fine, 1.0 + 0.05 * v + 0.1 * patch, 0.05 * fine, 1.0, nil}
  end

  def at(:concrete, {x, y, z}, _n) do
    patch = noise(x * 0.3, y * 0.3, z * 0.3) - 0.5
    fine = noise(x * 3.0, y * 3.0, z * 3.0) - 0.5
    pit = step(0.8, 0.9, noise(x * 1.7, y * 1.7, z * 1.7))
    {0.03 * fine - 0.12 * pit, 1.0 + 0.16 * patch + 0.06 * fine - 0.25 * pit, 0.1 * pit, 1.0, nil}
  end

  def at(:fabric, {x, y, z}, {nx, ny, nz}) do
    # The two axes of the cloth: across the side that the surface faces most.
    {a, b} =
      cond do
        abs(nz) >= abs(nx) and abs(nz) >= abs(ny) -> {x, y}
        abs(nx) >= abs(ny) -> {y, z}
        true -> {x, z}
      end

    {h, over, thread} = plain(a, b)
    {0.25 * h, 0.9 + 0.12 * h + if(over, do: 0.03, else: -0.03) + 0.05 * thread, 0.05 * (1.0 - h), 1.0, nil}
  end

  def at(:weave, {x, y, _z}, _n) do
    {h, _over, strip} = plain(x, y)
    # (Each strip has its own tone, and the gaps between the strips are dark.)
    {0.18 * h, 0.72 + 0.3 * h + 0.14 * strip, 0.08 * (1.0 - h), 1.0, nil}
  end

  def at(:leather, {x, y, z}, _n) do
    a = 1.0 - step(0.0, 0.1, abs(noise(x, y, z) - 0.5))
    b = 1.0 - step(0.0, 0.08, abs(noise(x * 2.3 + 11.0, y * 2.3, z * 2.3) - 0.5))
    crease = max(a, 0.7 * b)
    {-0.1 * crease, 1.0 - 0.18 * crease, 0.06 * crease, 1.0, nil}
  end

  def at(:rubber, {x, y, z}, _n) do
    v = noise(x, y, z) - 0.5
    {0.06 * v, 1.0 + 0.06 * v, 0.08, 1.0, nil}
  end

  def at(:leaves, {x, y, z}, _n) do
    v = noise(x, y, z)
    fine = noise(x * 2.3, y * 2.3, z * 2.3)
    lump = 0.65 * v + 0.35 * fine
    {0.18 * (lump - 0.5), 0.8 + 0.4 * lump, 0.1 * (0.5 - lump), 1.0, nil}
  end

  def at(:stone, {x, y, z}, _n) do
    v = noise(x, y, z) - 0.5
    mid = noise(x * 2.2, y * 2.2, z * 2.2) - 0.5
    fine = noise(x * 5.0, y * 5.0, z * 5.0) - 0.5
    {0.2 * v + 0.1 * mid + 0.04 * fine, 1.0 + 0.2 * mid + 0.12 * fine, 0.1 * fine, 1.0, nil}
  end

  def at(:rust, {x, y, z}, _n) do
    v = 0.7 * noise(x, y, z) + 0.3 * noise(x * 2.9, y * 2.9, z * 2.9)
    patch = step(0.48, 0.62, v)
    pit = noise(x * 6.0, y * 6.0, z * 6.0) - 0.5
    {0.1 * patch * pit, 1.0 + 0.3 * patch * pit, 0.35 * patch, 1.0 - patch, {@rust, patch}}
  end

  def at(:hair, q, _n) do
    h = strand(q)
    {cx, cy, along} = flow(q)
    # Some strands catch the light.
    light = step(0.8, 0.95, noise(cx * 1.3 + 5.2, cy * 1.3, along * 0.015))
    {0.5 * (h - 0.5), 0.62 + 0.62 * h + 0.35 * light, 0.12 * (0.5 - h), 1.0, nil}
  end

  def at(:palm, {x, y, _z} = q, _n) do
    {cx, cy, along} = flow(q)
    fiber = noise(cx, cy, along * 0.01) - 0.5
    # The blade of a place: 40 round the z, each with its own tone; a dark line at its two edges.
    turn = (:math.atan2(y, x) / (2 * :math.pi()) + 0.5) * 40
    blade = floor(turn)
    edge = abs(turn - blade - 0.5) * 2
    seam = step(0.86, 0.98, edge)
    tone = 0.93 + 0.12 * (:erlang.phash2(blade, 256) / 255) + 0.1 * fiber - 0.22 * seam
    {0.25 * fiber - 0.35 * seam, tone, 0.06 * seam - 0.05 * fiber, 1.0, nil}
  end

  @doc """
  The height of the strand of hair at a place (in the axes of the edit,
  in units of the scale): 0 to 1. The strands go out from the z of the
  edit and down, as hair from the top of a head: a strand is a
  direction round the z, one unit wide at 60 units from it. Three
  strands or so make a lock.
  """
  def strand(q) do
    {cx, cy, along} = flow(q)
    one = noise(cx, cy, along * 0.02)
    lock = noise(cx * 0.3 + 7.1, cy * 0.3, along * 0.008)
    fine = noise(cx * 2.7, cy * 2.7 + 3.3, along * 0.05)
    # (The mean of the three is near the middle: the heights go over all of 0 to 1.)
    min(max((0.5 * one + 0.32 * lock + 0.18 * fine - 0.5) * 2.6 + 0.5, 0.0), 1.0)
  end

  # The place of a strand: its direction round the z (two numbers, with
  # no seam) and how far it is along the strand (out and down).
  defp flow({x, y, z}) do
    r = :math.sqrt(x * x + y * y)
    out = max(r, 1.0e-9)
    {60.0 * x / out, 60.0 * y / out, r - z}
  end

  # A plain weave of two sets of strips, one mark wide: the height of the
  # strip on top (0 at its edges, 1 on its middle line, and lower where
  # it goes under the next strip), if the strip along the first axis is
  # on top, and a number of the strip (0 to 1).
  defp plain(a, b) do
    {i, j} = {floor(a), floor(b)}
    {u, v} = {a - i - 0.5, b - j - 0.5}
    over = rem(i + j, 2) == 0
    # (The strip on top goes along the first axis in one square, along the second in the next.)
    {across, along, id} = if over, do: {v, u, j}, else: {u, v, i}
    h = (1.0 - 4.0 * across * across) * (1.0 - 1.2 * along * along)
    {h, over, :erlang.phash2({id, over}, 256) / 255}
  end

  defp frac(v), do: v - floor(v)

  # 0 below `a`, 1 above `b`, smooth between.
  defp step(a, _b, v) when v <= a, do: 0.0
  defp step(_a, b, v) when v >= b, do: 1.0

  defp step(a, b, v) do
    t = (v - a) / (b - a)
    t * t * (3.0 - 2.0 * t)
  end

  @doc """
  A smooth noise of a place: 0 to 1, the same for the same place, with
  one change for each unit of length (the values at the points of a
  grid, with a smooth mix between them).
  """
  def noise(x, y, z) do
    {i, j, k} = {floor(x), floor(y), floor(z)}
    {u, v, w} = {ease(x - i), ease(y - j), ease(z - k)}

    a = mix(mix(grid(i, j, k), grid(i + 1, j, k), u), mix(grid(i, j + 1, k), grid(i + 1, j + 1, k), u), v)

    b =
      mix(
        mix(grid(i, j, k + 1), grid(i + 1, j, k + 1), u),
        mix(grid(i, j + 1, k + 1), grid(i + 1, j + 1, k + 1), u),
        v
      )

    mix(a, b, w)
  end

  defp ease(t), do: t * t * (3.0 - 2.0 * t)
  defp mix(a, b, t), do: a + (b - a) * t
  defp grid(i, j, k), do: :erlang.phash2({i, j, k}, 1024) / 1023
end
