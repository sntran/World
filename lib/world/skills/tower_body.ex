defmodule World.Skills.TowerBody do
  @moduledoc """
  The skill `tower_body` of a mason: the platform and the body of a tower
  (`World.Skills.Towers`): the round body with its ledge and its bands,
  the pilasters that flare at their foot, and the cornice under the
  gallery. At near with `hollow` the wall is a tube with the door through
  it. Its data: `meshes`.
  """
  @behaviour World.Skill
  alias World.{Frame, Mesh, Shape, Vec}
  alias World.Skills.Towers

  @names ~w(platform_width platform_height body top ledge bands pilasters pilaster_width across foot flare cornice gallery gallery_width door_width door_height door_angle hollow wall)

  @impl true
  def name, do: "tower_body"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: Towers.check(data, path, @names)

  # The lathes of 48 sides at near, 24 at mid and 8 at far, the rings and
  # the pilasters.
  @impl true
  def estimate(data, level) do
    sides = %{near: 48, mid: 24, far: 8}[level]
    rings = if level == :far, do: 0, else: 1 + length(Map.get(data, "bands", [4.1, 7.5]))
    pilasters = if level == :far, do: 0, else: Map.get(data, "pilasters", 4)
    sides * (6 + 8 * rings + 14) + 20 * pilasters
  end

  @impl true
  def make(data, _inputs, %{level: level}) do
    o = Towers.o(data, @names)
    {nil, %{"meshes" => platform(o) ++ body(o, level)}, %{}}
  end

  defp platform(%{platform: {d, h}}),
    do: [Shape.cylinder(d / 2, h, :tile_granite, sides: 48) |> Mesh.matter(:concrete)]

  defp body(o, level) do
    {_, z0} = o.platform
    {r0, r1} = {o.body / 2, o.top / 2}
    sides = %{near: 48, mid: 24, far: 8}[level]
    h = o.cornice - z0
    r = fn z -> r0 + (r1 - r0) * (z - z0) / h end

    wall =
      if o.hollow and level == :near do
        {dw, dh} = o.door
        ri = fn z -> r.(z) - o.wall end

        around =
          Shape.lathe(
            [{ri.(z0 + dh), z0 + dh}, {r.(z0 + dh), z0 + dh}, {r.(o.gallery), o.gallery}, {ri.(o.gallery), o.gallery}],
            :white,
            kind: :ring,
            sides: sides
          )

        [around, door_wall(o, r0, ri.(z0), z0, dw, dh, sides)]
      else
        [Shape.lathe([{0.0, z0}, {r0, z0}, {r.(o.gallery), o.gallery}, {0.0, o.gallery}], :white, sides: sides)]
      end

    rings =
      if level == :far,
        do: [],
        else: [{z0, z0 + o.ledge, 0.1}] ++ for(b <- o.bands, do: {z0 + b, z0 + b + 0.2, 0.12})

    rings =
      for {za, zb, out} <- rings do
        Shape.lathe([{r.(za) - 0.05, za}, {r.(za) + out, za}, {r.(zb) + out, zb}, {r.(zb) - 0.05, zb}], :white,
          kind: :ring,
          sides: sides
        )
      end

    (wall ++ rings ++ pilasters(o, r, level) ++ [cornice(o, sides)]) |> Enum.map(&Mesh.matter(&1, :concrete))
  end

  # The wall at the foot with the door through it: a ring of the plan
  # with a gap of the width of the door at its angle.
  defp door_wall(o, ro, ri, z0, dw, dh, sides) do
    gap = dw / ro
    a0 = o.door_angle * :math.pi() / 180 + gap / 2
    n = max(div(sides * 7, 8), 6)
    arc = for k <- 0..n, a = a0 + (2 * :math.pi() - gap) * k / n, do: a
    outer = for a <- arc, do: {ro * :math.cos(a), ro * :math.sin(a)}
    inner = for a <- Enum.reverse(arc), do: {ri * :math.cos(a), ri * :math.sin(a)}
    Shape.prism(outer ++ inner, dh, :white, frame: Frame.move({0.0, 0.0, z0}))
  end

  # The pilasters: each a prism in the plane of its radius, from inside
  # the body out to `across`, flared at its foot out to `foot`.
  defp pilasters(o, r, level) do
    {_, z0} = o.platform
    n = if level == :far, do: 0, else: o.pilasters

    for k <- 0..(n - 1)//1 do
      a = (45.0 + 360.0 * k / n) * :math.pi() / 180
      {c, s} = {:math.cos(a), :math.sin(a)}
      tangent = {-s, c, 0.0}
      rin = r.(z0) - 0.3
      {out, foot} = {o.across / 2, o.foot / 2}
      ztop = o.cornice

      loop = [{rin, z0}, {foot, z0}, {out, z0 + o.flare}, {out, ztop}, {rin, ztop}]
      # x out along the radius, y up, z back along the tangent (the
      # right hand): the prism goes from one side of the pilaster to the
      # other.
      frame = Frame.new(Vec.scale(tangent, o.pilaster_width / 2), Vec.scale(tangent, -1.0), {0.0, 0.0, 1.0})
      Shape.prism(loop, o.pilaster_width, :white, frame: frame)
    end
  end

  # The cornice: a cove from the pilasters out to the gallery, and the
  # floor of the gallery on it.
  defp cornice(o, sides) do
    {r0, rg, z1} = {o.across / 2 - 0.05, o.gallery_width / 2, o.gallery}
    zc = o.cornice
    steps = if sides > 8, do: 6, else: 2

    cove =
      for i <- 0..steps do
        t = i / steps * :math.pi() / 2
        {r0 + (rg - r0) * (1 - :math.cos(t)), zc + (z1 - 0.25 - zc) * :math.sin(t)}
      end

    Shape.lathe([{0.0, zc} | cove] ++ [{rg, z1}, {0.0, z1}], :white, sides: sides)
  end
end
