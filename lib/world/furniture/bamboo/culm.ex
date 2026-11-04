defmodule World.Furniture.Bamboo.Culm do
  @moduledoc """
  The pieces of bamboo of the bamboo shop (`World.Furniture.Bamboo`):

  - `piece/3`: a piece of a culm between two points: a hollow tube with
    the rings of its nodes, each end open (the hole shows) or closed (the
    piece is cut at a node);
  - `slat/5`: a slat split from a culm: a strip with a round outside and
    a flat inside;
  - `cord/2`: a cord of a lashing along a line of points.

  The culms are of tầm vông (Thyrsostachys siamensis): culms of 2 to 7.5
  cm with internodes of 15 to 30 cm and a very thick wall, solid at the
  base (PROSEA, Plant Resources of South-East Asia 7, Bamboos). The
  bamboo shops of the South sell furniture of it (Tre Tầm Vông Đàm
  Phương, Báo Thế giới và Việt Nam). The wall of a piece is a third of its
  radius by default: PROSEA gives no number.
  """
  alias World.{Detail, Frame, Mesh, Shape, Vec}

  # The ring of a node: 1.5 mm out of the culm, 12 mm long (by eye from
  # the photos of the shops).
  @ring 0.0015
  @ring_length 0.012

  @doc """
  A piece of a culm from `a` to `b` (m), as one closed mesh: its volume is
  the volume of its wall.

  Options: `d` (the outside diameter, 0.04), `wall` (a third of the
  radius), `node` (the length of an internode, 0.22), `phase` (the place
  of the first node from `a`, a part of an internode: 0.5), `ends` (`{a,
  b}`, each `:open` or `:node`: `{:open, :open}`), `material` (`:bamboo`).
  At far, the piece has no rings.

      iex> m = World.Furniture.Bamboo.Culm.piece({0, 0, 0}, {0, 0, 1}, d: 0.04, wall: 0.01)
      iex> v = World.Mesh.volume(m.points, m.faces) / 6
      iex> abs(v - :math.pi() * (0.02 ** 2 - 0.01 ** 2)) < 0.00015
      true
  """
  def piece(a, b, opts \\ []) do
    r = Keyword.get(opts, :d, 0.04) / 2
    wall = min(Keyword.get(opts, :wall, r / 3), 0.9 * r)
    ri = r - wall
    len = Vec.len(Vec.sub(b, a))
    {e0, e1} = Keyword.get(opts, :ends, {:open, :open})

    rings = if Detail.level() == :far, do: [], else: rings(len, opts)

    outer =
      [{r, 0.0}] ++
        Enum.flat_map(rings, fn z ->
          h = @ring_length / 2
          [{r, z - h}, {r + @ring, z - h / 3}, {r + @ring, z + h / 3}, {r, z + h}]
        end) ++ [{r, len}]

    top = if e1 == :node, do: [{1.0e-4, len}, {1.0e-4, len - wall}, {ri, len - wall}], else: [{ri, len}]
    bottom = if e0 == :node, do: [{ri, wall}, {1.0e-4, wall}, {1.0e-4, 0.0}], else: [{ri, 0.0}]

    Shape.lathe(outer ++ top ++ bottom, Keyword.get(opts, :material, :bamboo),
      kind: :ring,
      sides: Keyword.get(opts, :sides, 16),
      frame: frame(a, b)
    )
  end

  # The places of the rings along a piece: one in each internode length,
  # not at its ends.
  defp rings(len, opts) do
    node = Keyword.get(opts, :node, 0.22)
    first = Keyword.get(opts, :phase, 0.5) * node

    Stream.iterate(first, &(&1 + node))
    |> Enum.take_while(&(&1 < len - @ring_length))
    |> Enum.filter(&(&1 > @ring_length))
  end

  @doc """
  A slat split from a culm, from `a` to `b`: `width` across, `t` thick,
  its round outside to the side `up`. The outside is an arc of a culm of
  `d` (option, 0.06).
  """
  def slat(a, b, up, width, t, opts \\ []) do
    big = Keyword.get(opts, :d, 0.06) / 2
    hw = width / 2
    # The arc of the outside over the flat inside, as a loop in the axes
    # of the slat: x across, y up.
    sag = big - :math.sqrt(max(big * big - hw * hw, 0.0))

    arc =
      for k <- 0..4 do
        x = hw - 2 * hw * k / 4
        {x, t - sag + (:math.sqrt(max(big * big - x * x, 0.0)) - (big - sag))}
      end

    loop = [{-hw, 0.0}, {hw, 0.0} | arc]

    Shape.prism(loop, Vec.len(Vec.sub(b, a)), Keyword.get(opts, :material, :bamboo),
      frame: Frame.new(a, Vec.sub(b, a), up)
    )
  end

  @doc """
  A cord along a line of points: 2.4 mm across, of nylon (the white cord
  of the lashing in the photos). Option `material` (`:white`).
  """
  def cord(points, opts \\ []) do
    points
    |> Shape.sweep(0.0012, Keyword.get(opts, :material, :white), sides: 4)
    |> Mesh.matter(:nylon)
  end

  @doc "The frame of a piece from `a` to `b`: its z along the piece."
  def frame(a, b) do
    dir = Vec.sub(b, a)
    up = if abs(Vec.dot(Vec.norm(dir), {0.0, 0.0, 1.0})) > 0.9, do: {0.0, 1.0, 0.0}, else: {0.0, 0.0, 1.0}
    Frame.new(a, dir, up)
  end
end
