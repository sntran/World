defmodule World.Materials.Webbing do
  @moduledoc """
  Webbing and its hardware, as standard parts for any thing with a strap
  (a helmet, a bag, a harness, a tie-down).

  - `strap/4`: a flat strap of webbing along a path of points, with a
    port at each end.
  - `buckle/2`: a side-release buckle for a width of webbing, with a
    port for the strap at each end.
  - `d_ring/2`, `tri_glide/2`, `pin_buckle/2` and `hook_loop/3`: the
    hardware of a strap: a ring of steel wire that the strap goes
    through, a slide of three bars that sets the length of a strap, a
    buckle with a pin for a strap with holes, and a patch of hook and
    loop that closes a strap on itself.

  The webbing is nylon (Nylon 6,6, 1.13 to 1.15 g/cm3: The Engineering
  ToolBox, Densities of solids), as a solid band of its thickness; a
  woven band has less mass (`TODO.md`). A strap can be of another
  material (`matter: :leather`, dry leather 0.86 g/cm3, the same table).
  The buckles and the slide are acetal (POM, 1.4 g/cm3, the same table).

  The hardware is in its own axes: the strap goes along x, its width is
  along y. The option `frame` puts it in the axes of the thing, and its
  port `o` goes with it.
  """
  alias World.{Frame, Loft, Mesh, Part, Shape, Vec}

  @doc """
  A strap of webbing of the width `w` along a path (two or more points,
  m). The options: `thickness` (1 mm), `across` (the direction of the
  width at the first point; perpendicular to the path by default),
  `material` (the role of its color, `:black`), `matter` (the material
  of its mass, `:nylon`) and `ports` (more ports on the strap: `{name,
  point}`, for its hardware). Its ports: `a` at the first point and `b`
  at the last, in the axes of the part. Its params: the width, the
  thickness and the length.
  """
  def strap(name, [_, _ | _] = path, w, opts \\ []) do
    t = Keyword.get(opts, :thickness, 0.001)
    material = Keyword.get(opts, :material, :black)
    path = Enum.map(path, &Vec.float/1)
    sections = List.duplicate({w / 2, t / 2, 8}, length(path))
    {_, frames} = Loft.rows(Loft.new(path, sections, up: opts[:across]))
    band = Shape.loft(for({c, _, u, v} <- frames, do: {c, u, v, w / 2, t / 2, 8}), material, sides: 12)

    length = path |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [p, q] -> Vec.len(Vec.sub(q, p)) end) |> Enum.sum()

    matter = Keyword.get(opts, :matter, :nylon)
    more = for {n, at} <- Keyword.get(opts, :ports, []), do: port(n, at)

    Part.new(name, :strap, [Mesh.matter(band, matter)], [port("a", hd(path)), port("b", List.last(path)) | more],
      params: %{"width" => w / 1, "thickness" => t / 1, "length" => Float.round(length, 4)},
      sources: ["A strap of #{matter}, #{mm(w)} mm wide and #{mm(t)} mm thick."]
    )
  end

  @doc """
  A side-release buckle for webbing of the width `w`: the female body
  and the male tongue, locked. Its length along x (from the port
  `female` at x = 0 to the port `male`), its sizes from the width (by
  eye). The option `material` (`:black`).
  """
  def buckle(name, w, opts \\ []) do
    material = Keyword.get(opts, :material, :black)
    {bw, t} = {w * 1.3, w * 0.4}
    {lf, lm} = {w * 1.5, w * 1.1}

    female = Shape.box({0.0, -bw / 2, -t / 2}, {lf, bw / 2, t / 2}, material)
    male = Shape.box({lf, -bw / 2 * 0.9, -t / 2 * 0.8}, {lf + lm, bw / 2 * 0.9, t / 2 * 0.8}, material)

    Part.new(
      name,
      :buckle,
      Enum.map([female, male], &Mesh.matter(&1, :pom)),
      [port("female", {0.0, 0.0, 0.0}), port("male", {lf + lm, 0.0, 0.0})],
      params: %{"width" => w / 1},
      sources: ["A side-release buckle of acetal for webbing of #{mm(w)} mm; its sizes by eye."]
    )
  end

  @doc """
  A D-ring for webbing of the width `w`: a straight bar across the strap
  (along y, at x = 0) and a round back to the side of +x, of steel wire
  of 3 mm (by eye). The options `frame` and `material` (`:chrome`).
  """
  def d_ring(name, w, opts \\ []) do
    {r, half, deep} = {0.0015, w / 2 + 0.002, w * 0.6}
    arc = for i <- 0..12, a = :math.pi() * i / 12, do: {deep * :math.sin(a), half * :math.cos(a), 0.0}
    loop = [{0.0, -half, 0.0}, {0.0, half, 0.0} | arc] ++ [{0.0, -half, 0.0}]
    wire = loop |> Shape.sweep(r, Keyword.get(opts, :material, :chrome), sides: 8) |> Mesh.matter(:steel)

    hardware(
      name,
      :d_ring,
      [wire],
      opts,
      %{"width" => w / 1},
      "A D-ring of steel wire of 3 mm for webbing of #{mm(w)} mm; its sizes by eye."
    )
  end

  @doc """
  A tri-glide for webbing of the width `w`: a frame of three bars across
  the strap (along y), 2.5 mm thick, that sets the length of a strap.
  Of acetal (by eye). The options `frame` and `material` (`:black`).
  """
  def tri_glide(name, w, opts \\ []) do
    {half, l, bar, t} = {w / 2 + 0.003, w * 0.9, 0.003, 0.0025}
    m = Keyword.get(opts, :material, :black)
    bars = for x <- [-l / 2, 0.0, l / 2 - bar], do: Shape.box({x, -half, -t / 2}, {x + bar, half, t / 2}, m)
    sides = for y <- [-half, half - bar], do: Shape.box({-l / 2, y, -t / 2}, {l / 2, y + bar, t / 2}, m)

    hardware(
      name,
      :tri_glide,
      Enum.map(bars ++ sides, &Mesh.matter(&1, :pom)),
      opts,
      %{"width" => w / 1},
      "A tri-glide of acetal for webbing of #{mm(w)} mm; its sizes by eye."
    )
  end

  @doc """
  A pin buckle for a strap of the width `w` (a strap of leather with
  holes): a frame of steel wire of 3 mm and a pin across it, along x
  from the bar at x = 0. The options `frame` and `material` (`:chrome`).
  """
  def pin_buckle(name, w, opts \\ []) do
    {r, half, l} = {0.0015, w / 2 + 0.002, w * 0.8}
    m = Keyword.get(opts, :material, :chrome)

    frame =
      [{0.0, -half, 0.0}, {0.0, half, 0.0}, {l, half, 0.0}, {l, -half, 0.0}, {0.0, -half, 0.0}]
      |> Shape.sweep(r, m, sides: 8)

    pin = Shape.sweep([{0.0, 0.0, 0.0}, {l + 0.002, 0.0, 0.003}], 0.001, m, sides: 6)

    hardware(
      name,
      :pin_buckle,
      Enum.map([frame, pin], &Mesh.matter(&1, :steel)),
      opts,
      %{"width" => w / 1},
      "A pin buckle of steel wire of 3 mm for a strap of #{mm(w)} mm; its sizes by eye."
    )
  end

  @doc """
  A patch of hook and loop on webbing of the width `w`, of the length
  `l` along x: the hook layer and the loop layer, 0.75 mm each, on the
  side of +z. Of nylon. The options `frame` and `material` (`:black`).
  """
  def hook_loop(name, w, l, opts \\ []) do
    {half, t} = {w / 2 - 0.001, 0.00075}
    m = Keyword.get(opts, :material, :black)
    layers = for k <- [0, 1], do: Shape.box({0.0, -half, k * t}, {l, half, (k + 1) * t}, m) |> Mesh.matter(:nylon)

    hardware(
      name,
      :hook_loop,
      layers,
      opts,
      %{"width" => w / 1, "length" => l / 1},
      "A patch of hook and loop of nylon, #{mm(w)} by #{mm(l)} mm; its thickness by eye."
    )
  end

  # A part of hardware, in the axes of its frame, with its port `o` at the
  # origin of the frame.
  defp hardware(name, kind, meshes, opts, params, source) do
    f = Keyword.get(opts, :frame, Frame.identity())

    Part.new(name, kind, Enum.map(meshes, &Mesh.transform(&1, f)), [port("o", Frame.point(f, {0.0, 0.0, 0.0}))],
      params: params,
      sources: [source]
    )
  end

  defp port(name, at), do: Part.port(name, at, {0, 0, 1}, {0, 1, 0})

  defp mm(m), do: round(m * 1000)
end
