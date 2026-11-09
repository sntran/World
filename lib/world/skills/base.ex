defmodule World.Skills.Base do
  @moduledoc """
  The skill `base` of a mason: the base and the plinth of a statue. The
  base is a block with round corners (`corner`); at near and mid it has
  bands at its foot and its top and a frame round each panel, the panels
  in a recess of 0.15 m, with the figures in relief at near (`reliefs`:
  a `side`, a count of `figures` that stand in a row, and a `title`). The
  plinth is round with a curved top. The part `be` (nil with no base and
  no plinth) has the sources of the model.
  """
  @behaviour World.Skill
  alias World.{Detail, Frame, Mesh, Part, Shape, Vec}
  alias World.Skills.Statue

  @names ~w(material base_width base_depth base_height corner reliefs plinth_radius plinth_height plinth_top plinth_sides)

  @impl true
  def name, do: "base"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # The prisms of the block and the lathe of the plinth, and the figures
  # in relief at near.
  @impl true
  def estimate(_data, :far), do: 100
  def estimate(_data, :mid), do: 1_500
  def estimate(data, :near), do: 2_500 + 120 * Enum.sum(for r <- Map.get(data, "reliefs", []), do: r["figures"] || 3)

  @impl true
  def make(data, _inputs, %{sources: sources}) do
    o = Statue.o(data, @names)
    part = base_part(o, sources)
    {if(part.shapes != [], do: part), %{}, %{}}
  end

  # The outline of the base: a rectangle with round corners, in order
  # round it (counterclockwise from +z).
  defp outline(w, d, rc, inset) do
    n = %{near: 4, mid: 2, far: 1}[Detail.level()]
    {hw, hd, r} = {w / 2 - inset, d / 2 - inset, max(rc - inset, 0.01)}

    for {cx, cy, a0} <- [
          {hw - r, hd - r, 0.0},
          {-hw + r, hd - r, 90.0},
          {-hw + r, -hd + r, 180.0},
          {hw - r, -hd + r, 270.0}
        ],
        k <- 0..n do
      a = (a0 + 90.0 * k / n) * :math.pi() / 180
      {cx + r * :math.cos(a), cy + r * :math.sin(a)}
    end
  end

  defp base_part(o, sources) do
    level = Detail.level()
    {look, matter} = Statue.material(o.material)
    {w, d, h} = {o.base_width, o.base_depth, o.base_height}

    block =
      cond do
        h <= 0 ->
          []

        level == :far ->
          [Shape.prism(outline(w, d, o.corner, 0.0), h, look)]

        true ->
          [
            Shape.prism(outline(w, d, o.corner, 0.0), 0.6, look),
            Shape.prism(outline(w, d, o.corner, 0.15), h - 1.1, look, frame: Frame.move({0.0, 0.0, 0.6})),
            Shape.prism(outline(w, d, o.corner, 0.0), 0.5, look, frame: Frame.move({0.0, 0.0, h - 0.5}))
          ] ++ frames(o, look) ++ if(level == :near, do: reliefs(o, look), else: [])
      end

    plinth =
      if o.plinth_height > 0 do
        [plinth(o, h, look) |> Mesh.matter(matter)]
      else
        []
      end

    Part.new("be", :statue, Enum.map(block, &Mesh.matter(&1, matter)) ++ plinth, [Statue.port()], sources: sources)
  end

  # The plinth: round with a curved top, or with `plinth_top` (the radius
  # of its top, under the hem) a dome of `plinth_sides` facets, a face to
  # the front (the plinth on Núi Nhỏ: 8 facets, plan 0005).
  defp plinth(%{plinth_top: nil} = o, h, look) do
    {r, ph} = {o.plinth_radius, o.plinth_height}
    profile = [{0.0, 0.0}, {r, 0.0}, {r, 0.75 * ph}, {0.92 * r, 0.93 * ph}, {0.7 * r, ph}, {0.0, ph}]
    Shape.lathe(profile, look, sides: o.plinth_sides, frame: Frame.move({0.0, 0.0, h}))
  end

  defp plinth(o, h, look) do
    {r, t, ph} = {o.plinth_radius, o.plinth_top, o.plinth_height}
    # The profile of a dome from r at the foot to t at the top.
    curve = for f <- [0.0, 0.08, 0.33, 0.6, 0.84, 1.0], do: {t + (r - t) * :math.sqrt(1 - f * f), f * ph}
    profile = [{0.0, 0.0} | curve] ++ [{0.0, ph}]
    a = :math.pi() / o.plinth_sides

    Shape.lathe(profile, look,
      sides: o.plinth_sides,
      frame: Frame.new({0.0, 0.0, h}, {0.0, 0.0, 1.0}, {-:math.sin(a), :math.cos(a), 0.0})
    )
  end

  # The four sides of the base: their normal, their width, and where
  # their middle is.
  defp sides(o) do
    {hw, hd} = {o.base_width / 2, o.base_depth / 2}

    %{
      "front" => {{0.0, 1.0, 0.0}, o.base_width, {0.0, hd, 0.0}},
      "back" => {{0.0, -1.0, 0.0}, o.base_width, {0.0, -hd, 0.0}},
      "left" => {{-1.0, 0.0, 0.0}, o.base_depth, {-hw, 0.0, 0.0}},
      "right" => {{1.0, 0.0, 0.0}, o.base_depth, {hw, 0.0, 0.0}}
    }
  end

  # The frame of the panel of each side: a pilaster at each end of the
  # panel, in the recess of the middle of the base.
  defp frames(o, look) do
    for {_, {n, width, mid}} <- sides(o), sign <- [-1.0, 1.0] do
      along = Vec.cross({0.0, 0.0, 1.0}, n)
      half = width / 2 - o.corner
      c = Vec.add(mid, Vec.scale(along, sign * (half - 0.5)))
      box_on(c, n, along, {0.5, 0.15, o.base_height - 1.1}, 0.6, look)
    end
  end

  # A box of `{half along, depth in from the face, height}` on a face of
  # the base: its outer face on the face, from the height `z`.
  defp box_on(c, n, along, {ha, depth, h}, z, look) do
    p0 = Vec.add(Vec.add(c, Vec.scale(along, -ha)), Vec.scale(n, -depth))
    p1 = Vec.add(c, Vec.scale(along, ha))
    {{x0, y0, _}, {x1, y1, _}} = Vec.bounds([p0, p1])
    Shape.box({x0, y0, z}, {x1, y1, z + h}, look)
  end

  # The figures in relief of each panel: standing figures in a row, each
  # a body and a head that stand 0.12 m out of the recess.
  defp reliefs(o, look) do
    for %{"side" => side, "figures" => count} <- o.reliefs, {n, width, mid} = sides(o)[side], i <- 0..(count - 1) do
      along = Vec.cross({0.0, 0.0, 1.0}, n)
      panel = width - 2 * o.corner - 2.0
      x = -panel / 2 + panel * (i + 0.5) / count
      c = Vec.add(mid, Vec.add(Vec.scale(along, x), Vec.scale(n, -0.09)))
      ph = o.base_height - 1.1
      fw = min(0.3, panel / count * 0.35)
      body = {Vec.add(c, {0.0, 0.0, 0.7}), along, n, fw, 0.06, 3.0}
      shoulders = {Vec.add(c, {0.0, 0.0, 0.6 + 0.62 * ph}), along, n, fw * 1.1, 0.06, 3.0}
      neck = {Vec.add(c, {0.0, 0.0, 0.6 + 0.7 * ph}), along, n, fw * 0.45, 0.05, 2.0}
      head = {Vec.add(c, {0.0, 0.0, 0.6 + 0.85 * ph}), along, n, fw * 0.55, 0.05, 2.0}
      Shape.loft([body, shoulders, neck, head], look, sides: 12)
    end
  end
end
