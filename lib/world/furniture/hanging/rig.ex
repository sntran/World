defmodule World.Furniture.Hanging.Rig do
  @moduledoc """
  The suspension and the anchors of the hammock shop
  (`World.Furniture.Hanging`). Each piece is a part of its own, so that it
  goes on the node of the part that it is fixed to (`docs/format.md`, "A
  joint as in real life"): a hook on its beam, a strap on its tree, the
  rope and the chain on the node that swings, the two halves of a swivel
  on the two nodes of the swivel.

  Meshes for the parts of other models:

  - `rope/3`: a rope between two points;
  - `chain/3`: a chain of links between two points (at mid and far, a
    rod);
  - `ring/4`: a ring of round wire (an O-ring, the link of a chain);
  - `fan/3`: the cords from a ring to points (the cords of the end of a
    hammock, to the holes of its spreader bar or to the end of its net).

  Parts:

  - `hook/2`: an eye hook in a beam, or the hook at the top of a stand;
  - `carabiner/2`: a carabiner of aluminum;
  - `swivel/2`: a swivel in its two halves, `{top, bottom}`;
  - `tree_strap/4`: a strap of webbing round a trunk, to its loop;
  - `trunk/3`, `post/3`, `beam/3`: the anchors of a site (a tree, a pole
    of a café, the joist of a porch ceiling): the site is not a part of
    the thing that hangs, but it holds it.
  """
  alias World.{Detail, Mesh, Part, Shape, Vec}
  alias World.Materials.Webbing

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc "A rope of the diameter `d` from `a` to `b` (option `material`, `:rope`; nylon)."
  def rope(a, b, d, opts \\ []) do
    Shape.sweep([a, b], d / 2, Keyword.get(opts, :material, :rope), sides: 8)
    |> Mesh.matter(Keyword.get(opts, :matter, :nylon))
  end

  @doc """
  A ring of round wire: its center `at`, its axis `axis`, the radius `r`
  of its middle line and the radius `wire` of the wire. Options
  `material` (`:steel`), `stretch` (the length of a link along `along`,
  over its width: 1, a round ring).
  """
  def ring(at, axis, r, wire, opts \\ []) do
    n = Keyword.get(opts, :profile, 8)
    profile = for k <- 0..(n - 1), a = 2 * :math.pi() * k / n, do: {r + wire * :math.cos(a), wire * :math.sin(a)}
    up = Keyword.get(opts, :along, Vec.perpendicular(Vec.norm(axis)))

    profile
    |> Shape.lathe(Keyword.get(opts, :material, :steel), kind: :ring, sides: Keyword.get(opts, :sides, 12))
    |> stretch(Keyword.get(opts, :stretch, 1.0))
    |> Mesh.transform(World.Frame.new(at, axis, up))
    |> Mesh.matter(:steel)
  end

  # A link is a ring longer along y than along x.
  defp stretch(mesh, 1.0), do: mesh
  defp stretch(mesh, k), do: %{mesh | points: for({x, y, z} <- mesh.points, do: {x, y * k, z})}

  @doc """
  A chain from `a` to `b`: links of the wire `wire` (option, 4 mm), each
  a quarter turn from the one before, along the line. At mid and far, a
  rod of steel.
  """
  def chain(a, b, opts \\ []) do
    wire = Keyword.get(opts, :wire, 0.004)
    dir = Vec.sub(b, a)
    len = Vec.len(dir)
    u = Vec.norm(dir)

    case Detail.level() do
      :near ->
        # A link: 4 wires long and 3 wide (its pitch is 2 wires less than
        # its length): a common chain of welded links (by eye).
        pitch = 2.6 * wire
        n = max(round(len / pitch), 1)
        side = Vec.perpendicular(u)
        other = Vec.cross(u, side)

        for i <- 0..(n - 1) do
          c = Vec.add(a, Vec.scale(u, pitch * (i + 0.5) * len / (pitch * n)))
          axis = if rem(i, 2) == 0, do: side, else: other
          ring(c, axis, 1.0 * wire, wire / 2, stretch: 1.6, along: u, sides: 6, profile: 5)
        end

      _ ->
        [Shape.sweep([a, b], wire, :steel, sides: 6) |> Mesh.matter(:steel)]
    end
  end

  @doc """
  The cords from the point `from` to each of the points `to`: the cords of
  the end of a hammock (option `d`, 3 mm; `material`, `:rope`).
  """
  def fan(from, to, opts \\ []) do
    d = Keyword.get(opts, :d, 0.003)
    for p <- to, do: rope(from, p, d, Keyword.take(opts, [:material, :matter]))
  end

  @doc """
  An eye hook at `at`: its shank up into the beam or the stand, and its
  eye under it, of steel (by eye: an eye of 25 mm, a wire of 8 mm). The
  port `hook` at the bottom of the eye, where a ring or a chain hangs.
  """
  def hook(name, at) do
    {x, y, z} = at
    eye = ring({x, y, z + 0.0125}, {1, 0, 0}, 0.0125, 0.004)
    shank = Shape.sweep([{x, y, z + 0.025}, {x, y, z + 0.09}], 0.004, :steel, sides: 8) |> Mesh.matter(:steel)

    Part.new(name, :hook, [eye, shank], [@o, Part.port("hook", at, {0, 0, 1}, {0, 1, 0})],
      sources: ["An eye hook of steel: by eye."],
      detail: :near
    )
  end

  @doc """
  A carabiner of aluminum at `at` (its axis along `axis`): an oval of 75
  by 45 mm of a rod of 9 mm (the carabiners of 7075 aluminum of a camping
  hammock, ENO: by eye).
  """
  def carabiner(name, at, axis \\ {0, 0, 1}) do
    mesh = ring(at, {1, 0, 0}, 0.018, 0.0045, stretch: 1.6, along: axis, material: :aluminum) |> Mesh.matter(:aluminum)

    Part.new(name, :hardware, [mesh], [@o],
      sources: ["A carabiner of 7075 aluminum (ENO): its size by eye."],
      detail: :near
    )
  end

  @doc """
  A swivel at `at`, in its two halves, `{top, bottom}`: the top half (its
  eye and the upper barrel) on the rope or the chain over it, the bottom
  half (the lower barrel and its eye) on the node that spins (by eye: a
  barrel of 20 by 40 mm).
  """
  def swivel(name, at) do
    {x, y, z} = at

    top = [
      ring({x, y, z + 0.035}, {1, 0, 0}, 0.009, 0.003),
      Shape.cylinder(0.01, 0.02, :steel, frame: World.Frame.move({x, y, z})) |> Mesh.matter(:steel)
    ]

    bottom = [
      ring({x, y, z - 0.035}, {1, 0, 0}, 0.009, 0.003),
      Shape.cylinder(0.01, 0.02, :steel, frame: World.Frame.move({x, y, z - 0.02})) |> Mesh.matter(:steel)
    ]

    source = ["A swivel of steel: by eye."]

    {Part.new(name <> "_top", :hardware, top, [@o], sources: source),
     Part.new(name <> "_bottom", :hardware, bottom, [@o], sources: source)}
  end

  @doc """
  A strap of webbing round a trunk at the height `z` (the trunk of the
  center `{cx, cy}` and the radius `r`), from its loop round the trunk to
  the point `to` (its end loop, where a carabiner hangs). Of polyester, 25
  mm wide (the straps of a camping hammock: by eye).
  """
  def tree_strap(name, {cx, cy}, r, z, to) do
    {tx, ty, tz} = to
    a = :math.atan2(ty - cy, tx - cx)

    round =
      for k <- 0..16,
          t = a + 2 * :math.pi() * k / 16,
          do: {cx + (r + 0.002) * :math.cos(t), cy + (r + 0.002) * :math.sin(t), z}

    Webbing.strap(name, round ++ [{tx, ty, tz}], 0.025, thickness: 0.0015, material: :black)
  end

  @doc """
  A trunk of a tree at `{x, y}`: the diameter `d` and the height `h`, of
  bark: an anchor of a site, not a part of the hammock.
  """
  def trunk(name, {x, y}, d, h \\ 3.0) do
    mesh = Shape.cylinder(d / 2, h, :bark, sides: 16, frame: World.Frame.move({x, y, 0.0})) |> Mesh.matter(:wood)

    Part.new(name, :site, [mesh], [@o],
      sources: ["A trunk of a tree of #{round(d * 100)} cm: the site of the hammock."]
    )
  end

  @doc """
  A round pole of wood at `{x, y}`, `d` across and `h` high, with its
  bark: an anchor of a site (the poles of a café of võng, by eye from the
  photos).
  """
  def post(name, {x, y}, d, h \\ 2.6) do
    mesh = Shape.cylinder(d / 2, h, :bark, sides: 12, frame: World.Frame.move({x, y, 0.0})) |> Mesh.matter(:wood)

    Part.new(name, :site, [mesh], [@o],
      sources: ["A round pole of wood of #{round(d * 100)} cm: the site of the hammock."]
    )
  end

  @doc """
  The beam of a porch ceiling from `a` to `b` (a joist of 2 by 6 in) on
  two posts of 4 by 4 in to the floor: an anchor of a site.
  """
  def beam(name, a, b) do
    {{ax, ay, az}, {bx, by, _}} = {a, b}
    {w, h, p} = {0.038, 0.14, 0.089}

    meshes = [
      Shape.box({ax - p, ay - w / 2, az}, {bx + p, by + w / 2, az + h}, :wood),
      Shape.box({ax - p, ay - p / 2, 0.0}, {ax, ay + p / 2, az}, :wood),
      Shape.box({bx, by - p / 2, 0.0}, {bx + p, by + p / 2, az}, :wood)
    ]

    Part.new(name, :site, Enum.map(meshes, &Mesh.matter(&1, :wood)), [@o],
      sources: [
        "A joist of 2 by 6 in on two posts of 4 by 4 in (the lumber of World.Materials.Stock): the site of the porch swing."
      ]
    )
  end
end
