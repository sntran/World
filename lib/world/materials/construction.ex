defmodule World.Materials.Construction do
  @moduledoc """
  The materials of a house, at the sizes of their standards: bricks and
  concrete blocks (the units of masonry), a concrete lintel, clay roof
  tiles, metal roof panels, and the hardware of a door. Lumber and sheets
  are in `World.Materials.Stock`.

  A unit of masonry lies from x = 0 to its length, y = 0 to its width
  (the thickness of a wall of one unit), z = 0 to its height. Its port
  `o` is at the origin, with the axis +z and `up` +y.
  """
  alias World.{Frame, Part, Shape}
  # The units of masonry (`priv/standards/masonry.json`): the length, the
  # width and the height in mm, the material, the source.
  @units (for {name, u} <- World.Standards.table("masonry", "units")["sizes"], into: %{} do
            [l, w, h] = u["size"]
            {name, {l, w, h, String.to_atom(u["material"]), u["source"]}}
          end)

  @doc "The names of the units of masonry."
  def units, do: @units |> Map.keys() |> Enum.sort()

  @doc """
  A unit of masonry by its name: `%{name, l, w, h, joint, material,
  source}` in meters. The joint of mortar is 10 mm.
  """
  def unit(name) do
    {l, w, h, material, source} = Map.fetch!(@units, name)
    %{name: name, l: l / 1000, w: w / 1000, h: h / 1000, joint: 0.01, material: material, source: source}
  end

  @doc """
  A part of a unit of masonry. With a length less than the unit, it is a
  cut unit: it has the name of the whole unit, so the list of the parts
  counts the units to buy.
  """
  def masonry(name, length \\ nil) do
    u = unit(name)
    l = length || u.l
    shapes = if name == "cmu_8", do: block_shapes(l, u), else: [Shape.box({0, 0, 0}, {l, u.w, u.h}, u.material)]

    Part.new(
      name,
      if(name == "cmu_8", do: :block, else: :brick),
      shapes,
      [Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      params: %{"length" => u.l, "width" => u.w, "height" => u.h},
      sources: [u.source]
    )
  end

  # A hollow block: two face shells and three webs (two at a cut block).
  defp block_shapes(l, u) do
    {shell, web} = {0.032, 0.026}
    webs = if l < u.l * 0.75, do: [0.0, l - web], else: [0.0, l / 2 - web / 2, l - web]

    [Shape.box({0, 0, 0}, {l, shell, u.h}, u.material), Shape.box({0, u.w - shell, 0}, {l, u.w, u.h}, u.material)] ++
      for x <- webs, do: Shape.box({x, shell, 0}, {x + web, u.w - shell, u.h}, u.material)
  end

  @doc """
  A precast concrete lintel over an opening: from x = 0 to `length`,
  `width` thick, `height` high.
  """
  def lintel(length, width, height) do
    Part.new(
      "lintel_#{mm(length)}x#{mm(width)}x#{mm(height)}",
      :lintel,
      [Shape.box({0, 0, 0}, {length, width, height}, :concrete)],
      [Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      params: %{"length" => Float.round(length, 3)},
      sources: ["A precast lintel of reinforced concrete, 150 mm longer than the opening at each end."]
    )
  end

  @doc """
  A clay roof tile of 10 tiles to the square meter: 424 by 335 mm, with a
  roll along one side. It lies along y (down the slope from y = 0), on
  z = 0. Each tile covers 360 by 280 mm of the roof.
  """
  def roof_tile do
    {l, w, t} = {0.424, 0.335, 0.014}

    roll =
      Shape.lathe([{0.0, 0.0}, {0.03, 0.0}, {0.03, l}, {0.0, l}], :tile,
        sides: 8,
        frame: Frame.new({w - 0.03, 0.0, t}, {0, 1, 0}, {0, 0, 1})
      )

    Part.new(
      "roof_tile_clay_424x335",
      :tile,
      [Shape.box({0, 0, 0}, {w, l, t}, :tile), roll],
      [Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      params: %{"cover" => [0.28, 0.36]},
      sources: [
        "A clay tile of 10 tiles to the square meter (424 by 335 mm), a common size in Việt Nam. No source of a maker."
      ]
    )
  end

  @doc """
  A metal roof panel with ribs (a PBR panel of 26 gauge): it covers 36 in
  of width, with a rib of 1 1/4 in every 12 in. It lies along y (down the
  slope) from 0 to `length`, on z = 0, from x = 0. With `width`, the
  panel is cut to that width (the last panel of a roof).
  """
  def metal_panel(length, width \\ 0.9144) do
    cover = min(width, 0.9144)
    rib = 0.0318
    t = 0.0015

    # The profile across the panel (x, z): flat, then a rib every 12 in.
    top =
      Enum.flat_map(0..3, fn k ->
        x = k * 0.3048
        [{x - 0.03, 0.0}, {x - 0.013, rib}, {x + 0.013, rib}, {x + 0.03, 0.0}]
      end)
      |> Enum.filter(fn {x, _} -> x >= 0.0 and x <= cover end)
      |> then(&([{0.0, rib}] ++ &1 ++ [{cover, rib}]))
      |> Enum.uniq_by(&elem(&1, 0))

    # The sheet lies on z = 0: its flats from 0 to t.
    loop = for({x, z} <- top, do: {x, z + t}) ++ Enum.reverse(top)

    Part.new(
      "metal_panel_pbr_#{mm(length)}",
      :roof_panel,
      [Shape.prism(loop, length, :roof_metal, frame: Frame.new({0, length, 0}, {0, -1, 0}, {0, 0, 1}))],
      [Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      params: %{"length" => length, "cover" => 0.9144},
      sources: ["A PBR panel of 26 gauge: 36 in of cover, a rib of 1 1/4 in every 12 in (a common profile)."]
    )
  end

  @doc """
  A butt hinge of 3 1/2 by 3 1/2 in for a door (`butt_hinge/5`): `{fixed,
  moving}`, the half for the jamb and the half for the door.
  """
  def hinge,
    do:
      butt_hinge("hinge_3_5in", 0.0889, 0.032, 0.0045,
        sources: ["A butt hinge of 3 1/2 by 3 1/2 in; its knuckles and its pin by eye."]
      )

  @doc """
  A butt hinge as it is in real life: two halves on one pin, along z from
  the port `pin` on the axis of the pin. It gives `{fixed, moving}`:

  - the fixed half: the leaf to the side -x, screwed to the frame (a jamb,
    the body of a box), with the knuckles 1, 3, 5 and the pin;
  - the moving half: the leaf to the side +x, screwed to the part that
    turns (a door, a cover), with the knuckles 2 and 4, that turn on the
    pin.

  Each half goes on the part that it is screwed to: the fixed half on the
  frame, the moving half on the node of the part that turns, both on the
  axis of the joint. Then the leaf of the door turns with the door, and the
  pin stays on the axis in each pose. `height`, `leaf` (the width of a
  leaf), `r` (the radius of a knuckle); options `knuckles` (5, an odd
  number), `t` (the thickness of a leaf, 2.4 mm), `sources`. Only at the
  near level.
  """
  def butt_hinge(name, height, leaf, r, opts \\ []) do
    n = Keyword.get(opts, :knuckles, 5)
    t = Keyword.get(opts, :t, 0.0024)
    pin_r = 0.45 * r
    step = height / n

    knuckle = fn k ->
      Shape.lathe([{pin_r, k * step}, {r, k * step}, {r, (k + 1) * step}, {pin_r, (k + 1) * step}], :chrome,
        kind: :ring,
        sides: 12
      )
    end

    port = [Part.port("pin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]
    sources = Keyword.get(opts, :sources, [])

    fixed =
      [Shape.box({-leaf, -t / 2, 0.0}, {-r, t / 2, height}, :chrome), Shape.cylinder(pin_r, height, :chrome, sides: 8)] ++
        for k <- 0..(n - 1)//2, do: knuckle.(k)

    moving = [Shape.box({r, -t / 2, 0.0}, {leaf, t / 2, height}, :chrome) | for(k <- 1..(n - 2)//2, do: knuckle.(k))]

    {Part.new(name <> "_fixed_leaf", :hinge, fixed, port, detail: :near, sources: sources),
     Part.new(name <> "_moving_leaf", :hinge, moving, port, detail: :near, sources: sources)}
  end

  defp mm(x), do: x |> Kernel.*(1000) |> round()
end
