defmodule World.Sewing.Cushion do
  @moduledoc """
  The cushions of the sewing shop (`World.Sewing`): a cover of a fabric,
  sewn from its pieces, over a fill, as a cushion maker makes them.

  - A box cushion (`box/2`): a top panel and a bottom panel of the
    outline of the seat, a boxing strip round its side (the thickness of
    the cushion), and a cord of piping in each of its two seams. The
    fill is a block of foam, or a fill of fiber that takes the shape of
    a bowl under it (`bowl`: the seat of an egg chair). The cover makes
    the edges round.
  - A pad (`pad/2`): a cushion with a knife edge that lies on a curved
    face (the back of a basket): two panels with one seam round the
    edge, the fill thick at the middle and thin at the seam, and tufts
    (a button through the cushion that pulls the panels in).
  - Ties (`ties`): a strip of the fabric sewn into a seam, round a bar of
    the frame (a slat, a rope).

  A cushion is a part (`World.Part`, the kind `:cushion`) with its cut
  list (`"pieces"`: each piece of the cover with its area, with a seam
  allowance of 1/2 in at each edge), its mass (the cover and the fill)
  and its sources. A person sinks into the fill (`squash/1`); `solid/2`
  gives the cushion as it is under a person (thinner by the squash), as
  an obstacle (`World.Contact`).
  """
  alias World.{Contact, Detail, Frame, Mesh, Part, Shape, Vec}

  # The fabric of the cover: the mass of an area.
  @fabric %{
    gsm: 271,
    source:
      "A cover of solution-dyed fabric for cushions, 8.00 oz per square yard (271 g/m2: the furniture grade of Sunbrella, Outdoor Fabrics)."
  }

  # The fills: the density, the share of the thickness that a person
  # squashes, and the source.
  @fills %{
    foam: %{
      density: 28.8,
      squash: 0.25,
      matter: :pu_foam,
      source: "A core of polyurethane foam for outdoor cushions, 1.8 lb/ft3 (28.8 kg/m3, Foam Order: outdoor foam)."
    },
    fiber: %{
      density: 25.0,
      squash: 0.35,
      matter: :pu_foam,
      source:
        "A fill of polyester fiber, 200 to 300 g for a cushion of 40 by 40 cm (Rijs Textiles: fiberfill): about 25 kg/m3 in its volume."
    }
  }

  # The seam allowance at each edge of a piece (1/2 in), and the radius
  # of the cord of piping.
  @allowance 0.0127
  @piping 0.003

  @doc "The share of the thickness of a cushion of the fill `fill` (`:foam`, `:fiber`) that a person squashes."
  def squash(fill), do: @fills[fill].squash

  @doc """
  A box cushion: `size` `{length, width}` (along x and y of the frame
  `at`, the bottom at its origin, z up), `thick`, the outline a
  superellipse of `power` (2 an oval; 10 by default, a rectangle with
  round corners). Options: `fill` (`:foam`, `:fiber`), `bowl` (a
  function of a height over the bottom to the most half length and half
  width there: the fill takes the shape of a bowl under it), `ties` (a
  list of `{point, axis, r}`: a tie from the seam near the point round a
  bar on the axis of radius `r`, in the axes of the model), `sources`.
  """
  def box(name, opts) do
    {mesh, loops} = box_mesh(opts, Keyword.fetch!(opts, :thick))
    {length, width} = Keyword.fetch!(opts, :size)
    thick = Keyword.fetch!(opts, :thick)
    [bottom, top] = loops
    # The two flat caps of the loft are the panels; the faces round its
    # side (with the round edges) are the boxing strip.
    [bottom_cap, top_cap | sides] = mesh.faces

    pieces = [
      piece("top", surface(mesh, [top_cap]), perimeter(top)),
      piece("bottom", surface(mesh, [bottom_cap]), perimeter(bottom)),
      piece("boxing", surface(mesh, sides), perimeter(top) + perimeter(bottom))
    ]

    piping =
      if Detail.level() == :far,
        do: [],
        else: for(loop <- loops, do: Shape.sweep(loop ++ [hd(loop)], @piping, :fabric, sides: 6))

    finish(name, mesh, piping, pieces, opts, "A box cushion of #{cm(length)} by #{cm(width)} by #{cm(thick)} cm")
  end

  @doc """
  A pad with a knife edge on a curved face: `face` gives the point of the
  face at `{u, v}` (each 0 to 1), `toward` a point on the side of the
  face where the pad is (the axis of a basket); the fill is `thick` at
  the middle and 1 cm at the seam. Options: `fill`, `tufts` (`{nu, nv}`:
  the buttons in rows), `ties`, `sources`.
  """
  def pad(name, opts) do
    {mesh, edge} = pad_mesh(opts, Keyword.fetch!(opts, :thick))
    panel = area_3d(Keyword.fetch!(opts, :face))
    perimeter = perimeter(edge)
    pieces = [piece("front", panel * 1.08, perimeter), piece("back", panel, perimeter)]

    piping =
      if Detail.level() == :far, do: [], else: [Shape.sweep(edge ++ [hd(edge)], @piping, :fabric, sides: 6)]

    buttons =
      for {p, n} <- tufts(opts, Keyword.fetch!(opts, :thick)),
          do: Shape.cylinder(0.012, 0.006, :fabric, sides: 8, frame: Frame.new(p, n, perp(n)))

    finish(
      name,
      mesh,
      piping ++ buttons,
      pieces,
      opts,
      "A pad of a knife edge, #{cm(Keyword.fetch!(opts, :thick))} cm thick at the middle"
    )
  end

  @doc """
  The cushion as it is under a person, as an obstacle (`World.Contact`):
  the same cushion (the options of `box/2` or `pad/2`, `kind` `:box` or
  `:pad`), thinner by the squash of its fill.
  """
  def solid(:box, opts), do: opts |> box_mesh(squashed(opts)) |> elem(0) |> Contact.solid()
  def solid(:pad, opts), do: opts |> pad_mesh(squashed(opts)) |> elem(0) |> Contact.solid()

  defp squashed(opts), do: Keyword.fetch!(opts, :thick) * (1 - squash(Keyword.get(opts, :fill, :foam)))

  # The part of a cushion: its meshes, its ties, its cut list and its mass.
  defp finish(name, mesh, extra, pieces, opts, what) do
    fill = @fills[Keyword.get(opts, :fill, :foam)]
    {tie_meshes, tie_pieces} = ties(Keyword.get(opts, :ties, []))
    pieces = pieces ++ tie_pieces
    cover = pieces |> Enum.map(& &1["area"]) |> Enum.sum()
    # Six times the volume (`World.Mesh.volume/2`).
    volume = Mesh.volume(mesh.points, mesh.faces) / 6
    mass = cover * @fabric.gsm / 1000 + volume * fill.density

    Part.new(
      name,
      :cushion,
      [Mesh.matter(mesh, fill.matter) | extra ++ tie_meshes],
      [Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      params: %{"mass" => Float.round(mass, 3), "pieces" => pieces, "squash" => fill.squash},
      sources:
        [
          "#{what}: its cover sewn from #{length(pieces)} pieces (World.Sewing.Cushion)."
          | Keyword.get(opts, :sources, [])
        ] ++ [@fabric.source, fill.source]
    )
  end

  # A piece of the cover: its area with the seam allowance round its edge.
  defp piece(name, area, edge), do: %{"name" => name, "area" => Float.round(area + edge * @allowance, 4)}

  # The mesh of a box cushion of `thick`: a loft of its outline, the
  # edges round by the cover (a radius of a fifth of the thickness, at
  # most 2 cm). The loops of the two seams.
  defp box_mesh(opts, thick) do
    {length, width} = Keyword.fetch!(opts, :size)
    p = Keyword.get(opts, :power, 10)
    at = Keyword.get(opts, :at, Frame.identity())
    bowl = Keyword.get(opts, :bowl, fn _ -> {length / 2, width / 2} end)
    r = min(thick / 5, 0.02)
    n = 8

    # The profile of the side: the bottom edge round, the side straight,
    # the top edge round.
    profile =
      for(k <- 0..n, a = :math.pi() / 2 * k / n, do: {r * (1 - :math.sin(a)), r * (1 - :math.cos(a))}) ++
        for k <- 0..n, a = :math.pi() / 2 * k / n, do: {r * (1 - :math.cos(a)), thick - r + r * :math.sin(a)}

    sections =
      for {inset, z} <- profile do
        {bx, by} = bowl.(z)
        {hx, hy} = {min(length / 2, bx) - inset, min(width / 2, by) - inset}

        {Frame.point(at, {0.0, 0.0, z}), Frame.dir(at, {1.0, 0.0, 0.0}), Frame.dir(at, {0.0, 1.0, 0.0}), max(hx, 0.005),
         max(hy, 0.005), p}
      end

    sides = 32
    mesh = Shape.loft(sections, :fabric, sides: sides)
    m = Detail.sides(sides)
    rings = Enum.chunk_every(mesh.points, m)
    {mesh, [Enum.at(rings, n), Enum.at(rings, n + 1)]}
  end

  # The mesh of a pad: rings across v, each the back of the pad (on the
  # face) and its front (out by the fill), closed at the two ends. The
  # loop of its seam.
  defp pad_mesh(opts, thick) do
    face = Keyword.fetch!(opts, :face)
    toward = Keyword.fetch!(opts, :toward)
    {nu, nv} = if Detail.level() == :far, do: {8, 10}, else: {20, 24}
    lift = fn u, v -> lift(opts, thick, u, v) end

    grid =
      for j <- 0..nv, v = j / nv do
        for i <- 0..nu, u = i / nu do
          p = face.({u, v})
          {p, Vec.add(p, Vec.scale(normal(face, toward, u, v), lift.(u, v)))}
        end
      end

    rings = for row <- grid, do: Enum.map(row, &elem(&1, 0)) ++ Enum.reverse(Enum.map(row, &elem(&1, 1)))

    edge =
      Enum.map(hd(grid), &elem(&1, 0)) ++
        Enum.map(Enum.map(grid, &List.last/1), &elem(&1, 0)) ++
        Enum.reverse(Enum.map(List.last(grid), &elem(&1, 0))) ++ Enum.reverse(Enum.map(grid, &elem(hd(&1), 0)))

    {Shape.rings(rings, :fabric), Enum.dedup(edge)}
  end

  # The fill at {u, v}: 1 cm at the seam, `thick` at the middle, less at
  # each tuft.
  defp lift(opts, thick, u, v) do
    base = 0.01 + (thick - 0.01) * :math.pow(max(:math.sin(:math.pi() * u) * :math.sin(:math.pi() * v), 0.0), 0.35)
    dips = for {tu, tv} <- tuft_places(opts), do: :math.exp(-((u - tu) ** 2 + (v - tv) ** 2) / 0.004)
    base * (1 - 0.3 * Enum.max([0.0 | dips]))
  end

  defp tuft_places(opts) do
    case Keyword.get(opts, :tufts) do
      nil -> []
      {nu, nv} -> for i <- 1..nu, j <- 1..nv, do: {i / (nu + 1), j / (nv + 1)}
    end
  end

  # The button of each tuft, on the front of the pad, and its normal.
  defp tufts(opts, thick) do
    face = Keyword.fetch!(opts, :face)
    toward = Keyword.fetch!(opts, :toward)

    for {u, v} <- tuft_places(opts) do
      n = normal(face, toward, u, v)
      {Vec.add(face.({u, v}), Vec.scale(n, lift(opts, thick, u, v))), n}
    end
  end

  # The normal of the face at {u, v}, to the side of `toward`.
  defp normal(face, toward, u, v) do
    d = 1.0e-3
    du = Vec.sub(face.({min(u + d, 1.0), v}), face.({max(u - d, 0.0), v}))
    dv = Vec.sub(face.({u, min(v + d, 1.0)}), face.({u, max(v - d, 0.0)}))
    n = Vec.norm(Vec.cross(du, dv))
    if Vec.dot(n, Vec.sub(toward, face.({u, v}))) < 0, do: Vec.scale(n, -1.0), else: n
  end

  defp perp(n), do: if(abs(elem(n, 2)) < 0.9, do: {0.0, 0.0, 1.0}, else: {1.0, 0.0, 0.0})

  # The ties: a strip from the seam to the bar, and a loop round the bar.
  defp ties(ties) do
    meshes =
      for {p, axis, r} <- ties do
        a = Vec.norm(axis)

        [
          Shape.sweep(
            for(
              k <- 0..12,
              do:
                Vec.add(
                  p,
                  Vec.scale(
                    Frame.dir(
                      Frame.new({0.0, 0.0, 0.0}, a, perp(a)),
                      {:math.cos(k * :math.pi() / 6), :math.sin(k * :math.pi() / 6), 0.0}
                    ),
                    r + 0.003
                  )
                )
            ),
            0.004,
            :fabric,
            sides: 4
          )
        ]
      end

    pieces =
      for {{_, _, r}, i} <- Enum.with_index(ties), do: piece("tie_#{i + 1}", 0.025 * (2 * :math.pi() * r + 0.3), 0.0)

    {List.flatten(meshes), pieces}
  end

  defp perimeter(loop),
    do: loop |> Enum.zip(tl(loop) ++ [hd(loop)]) |> Enum.map(fn {a, b} -> Vec.len(Vec.sub(b, a)) end) |> Enum.sum()

  # The area of the faces `faces` of a mesh.
  defp surface(%Mesh{points: points}, faces) do
    pt = List.to_tuple(points)

    for [a | rest] <- faces, [b, c] <- Enum.chunk_every(rest, 2, 1, :discard), reduce: 0.0 do
      acc -> acc + Vec.len(Vec.cross(Vec.sub(elem(pt, b), elem(pt, a)), Vec.sub(elem(pt, c), elem(pt, a)))) / 2
    end
  end

  # The area of a face over {u, v}.
  defp area_3d(face) do
    n = 16

    for i <- 0..(n - 1), j <- 0..(n - 1), reduce: 0.0 do
      acc ->
        {a, b, c} = {face.({i / n, j / n}), face.({(i + 1) / n, j / n}), face.({i / n, (j + 1) / n})}
        acc + Vec.len(Vec.cross(Vec.sub(b, a), Vec.sub(c, a)))
    end
  end

  defp cm(m), do: round(m * 100)
end
