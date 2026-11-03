defmodule World.Footwear do
  @moduledoc """
  The shoe shop of the world (the family `:footwear`): footwear on the
  last of the right foot of a person (`World.Footwear.Last`), each a
  stack of soles (`World.Footwear.Sole`) and the straps of its upper
  (`World.Footwear.Upper`, of the straps and the hardware of
  `World.Materials.Webbing`).

  - `sandal/1`: a sport sandal with straps (xăng-đan quai hậu): an
    outsole of rubber, a midsole of EVA with a rim, a forefoot strap and
    an ankle strap that close on the outside with a D-ring and hook and
    loop, and a heel strap from the ankle strap with a tri-glide; with
    `leather: true`, straps of leather and pin buckles.
  - `thong/1`: a thong (dép tông, dép xỏ ngón): a sole of EVA and a Y of
    rubber with a post between the first two toes, plugged into the sole.
  - `tire_sandal/1`: a sandal of tire rubber (dép lốp): a sole cut from a
    tire, two straps of inner tube that cross over the front of the foot
    and a heel strap, each end through a slit in the sole.
  - `clog/1`: a wooden clog (guốc mộc): a sole of vông wood on a grip pad
    of rubber, and one wide strap nailed to its sides; with `heel:
    :high`, a wedge heel of 70 mm.

  The places of the straps and the sizes that are not from a standard
  are by eye from photos: the sport sandals of Wikimedia Commons, the
  tire sandals and the thongs of Wikimedia Commons (Hanoi - Ho Chi Minh
  sandals for sale, Flip-flops, Flipflop in hong kong), and the clogs of
  the shop of Trần Thị Hoàng Yến in Vĩnh Long (Tuổi Trẻ News, 2023).

  The axes: x across (to the outside of a right foot), y from the heel to
  the toes, z up from the ground.
  """
  alias World.{Assembly, Frame, Part}
  alias World.Footwear.{Last, Sole, Upper}
  alias World.Materials.Webbing

  @brown %{"color" => [120, 72, 40], "roughness" => 0.7, "metalness" => 0.0}

  @doc "The models of the shoe shop, as `{name, fun}`."
  def models,
    do: [
      {"sandal_vn", fn -> sandal() end},
      {"sandal_leather_vn", fn -> sandal(leather: true) end},
      {"dep_tong_vn", fn -> thong() end},
      {"dep_lop_vn", fn -> tire_sandal() end},
      {"guoc_moc_vn", fn -> clog() end},
      {"guoc_cao_vn", fn -> clog(heel: :high) end}
    ]

  @doc """
  The EU size of a shoe for a foot of a length (m)
  (`World.Footwear.Last.eu_size/1`).
  """
  defdelegate eu_size(foot), to: Last

  @doc """
  A sport sandal for the right foot of a person. The options: `person`
  (the options of `World.People.Human.person/2`) and `leather`.
  """
  def sandal(opts \\ []) do
    last = Last.new(Keyword.get(opts, :person, []))
    leather = Keyword.get(opts, :leather, false)
    {w, t} = {0.025, 0.003}

    sole =
      Sole.stack(last, [
        [
          name: "outsole_sandal",
          heel: 0.004,
          role: :gray,
          matter: :rubber_sole,
          source: "The outsole: rubber of 4 mm (soft commercial rubber, 1.1 g/cm3, The Engineering ToolBox), by eye."
        ],
        [
          name: "midsole_sandal",
          heel: 0.024,
          ball: 0.014,
          role: :dark,
          matter: :eva,
          rim: 0.005,
          source:
            "The midsole: EVA of 24 mm at the heel and 14 mm at the ball, with a rim of 10 mm round the footbed (by eye from the photos), 240 kg/m3 (Footwear Science)."
        ]
      ])

    {matter, color} = if leather, do: {:leather, :paint}, else: {:nylon, :black}

    strap = fn name, path, across, ports ->
      Webbing.strap(name, path, w, thickness: t, across: across, matter: matter, material: color, ports: ports)
    end

    plain = fn name, path -> strap.(name, path, {0, 1, 0}, []) end

    # The forefoot strap and the ankle strap, closed on the outside; the
    # top of the ankle strap at the front of the ankle, 85 mm over the
    # ground at most (by eye from the photos).
    toe = Upper.over(last, 0.72, sole.top, closure: true)
    ankle = Upper.over(last, 0.38, sole.top, closure: true, high: 0.085)
    toe_closure = Upper.closure("toe_sandal", toe, {w, t}, leather, plain)
    ankle_closure = Upper.closure("ankle_sandal", ankle, {w, t}, leather, plain)

    # The heel strap: from the ankle strap on the outside, round the heel
    # 45 mm over the sole, to the ankle strap on the inside.
    {xo, y, _} = List.last(ankle)
    {xi, _, _} = hd(ankle)
    {behind, z} = {y - w / 2 - t, sole.top.(y) + 0.03}
    heel = Upper.heel(last, sole.top, {{xo, behind, z}, {xi, behind, z}}, 0.045)
    back = Enum.min_by(heel, &elem(&1, 1))

    nodes =
      [
        {"strap_toe_sandal", strap.("strap_toe_sandal", toe, {0, 1, 0}, []), "midsole_sandal"},
        {"strap_ankle_sandal", strap.("strap_ankle_sandal", ankle, {0, 1, 0}, []), "midsole_sandal"},
        {"strap_heel_sandal", strap.("strap_heel_sandal", heel, {0, 0, 1}, []), "strap_ankle_sandal"}
      ] ++
        for({n, p} <- toe_closure, do: {n, p, "strap_toe_sandal"}) ++
        for({n, p} <- ankle_closure, do: {n, p, "strap_ankle_sandal"}) ++
        if(leather,
          do: [],
          else: [
            {"glide_sandal", Webbing.tri_glide("glide_sandal", w, frame: Frame.new(back, {0, -1, 0}, {0, 0, 1})),
             "strap_heel_sandal"}
          ]
        )

    assemble(if(leather, do: "sandal_leather_vn", else: "sandal_vn"), :sandal, last, sole, nodes,
      materials: %{paint: @brown},
      source:
        "A sport sandal with straps (xăng-đan quai hậu); the places of the straps, the rim, the closures and the padded straps by eye from photos of sport sandals on Wikimedia Commons (Man in sport sandals front view, Man in sandals side view, Man in sandals top view, Hiking sandals of Hysocc)."
    )
  end

  @doc """
  A thong (dép tông) for the right foot of a person. The option
  `person`.
  """
  def thong(opts \\ []) do
    last = Last.new(Keyword.get(opts, :person, []))

    sole =
      Sole.stack(last, [
        [
          name: "sole_dep_tong",
          heel: 0.015,
          ball: 0.012,
          role: :blue,
          matter: :eva,
          source:
            "The sole: EVA of 15 mm at the heel and 12 mm at the ball (by eye from the photos), 240 kg/m3 (Footwear Science)."
        ]
      ])

    %{post: post, straps: [inside, outside]} = Upper.thong(last, sole.top)
    # Each strap lies flat on the foot: its width across its own path.
    rubber = fn name, path, {w, t} ->
      across = World.Vec.cross({0.0, 0.0, 1.0}, World.Vec.sub(List.last(path), hd(path)))
      across = if World.Vec.len(across) < 1.0e-9, do: {0, 1, 0}, else: across
      Webbing.strap(name, path, w, thickness: t, across: across, matter: :rubber, material: :black)
    end

    plugs = Upper.plugs([hd(post), List.last(inside), List.last(outside)], 0.01, {:black, :rubber})

    parts = [
      rubber.("post", post, {0.006, 0.006}),
      rubber.("inside", inside, {0.015, 0.004}),
      rubber.("outside", outside, {0.015, 0.004})
    ]

    y_strap =
      Part.new(
        "thong_dep_tong",
        :strap,
        Enum.flat_map(parts, & &1.shapes) ++ plugs,
        [Part.port("a", hd(post), {0, 0, 1}, {0, 1, 0})],
        params: %{"width" => 0.015, "thickness" => 0.004},
        sources: [
          "The Y of a thong: one molded piece of rubber, straps of 15 by 4 mm, a post of 6 mm, three plugs of 8 mm into the sole (by eye from the photos)."
        ]
      )

    assemble("dep_tong_vn", :sandal, last, sole, [{"thong_dep_tong", y_strap, "sole_dep_tong"}],
      source:
        "A thong (dép tông, dép xỏ ngón); its sizes by eye from photos of thongs on Wikimedia Commons (Flip-flops, Flipflop in hong kong)."
    )
  end

  @doc """
  A sandal of tire rubber (dép lốp) for the right foot of a person. The
  option `person`.
  """
  def tire_sandal(opts \\ []) do
    last = Last.new(Keyword.get(opts, :person, []))
    depth = 0.012

    sole =
      Sole.stack(last, [
        [
          name: "sole_dep_lop",
          heel: depth,
          role: :tire,
          matter: :rubber_sole,
          side: 0.008,
          source:
            "The sole: a piece of a tire, 12 mm (by eye from the photos), of soft commercial rubber (1.1 g/cm3, The Engineering ToolBox)."
        ]
      ])

    tube = fn name, path, across ->
      Webbing.strap(name, path, 0.018, thickness: 0.003, across: across, matter: :rubber, material: :black)
    end

    # Each end goes 3/4 of the way down through its slit.
    [a, b] = Upper.cross(last, sole.top, 0.75 * depth)

    # The heel strap has its width up: its ends 2 mm into the sole, the
    # strap through its slits.
    {y, xa, xb, _} = Last.at(last, 0.3)
    z = sole.top.(y) - 0.002
    heel = Upper.heel(last, sole.top, {{xb + 0.002, y, z}, {xa - 0.002, y, z}}, 0.035)

    assemble(
      "dep_lop_vn",
      :sandal,
      last,
      sole,
      [
        {"strap_a_dep_lop", tube.("strap_a_dep_lop", a, {0, 1, 0}), "sole_dep_lop"},
        {"strap_b_dep_lop", tube.("strap_b_dep_lop", b, {0, 1, 0}), "strap_a_dep_lop"},
        {"strap_heel_dep_lop", tube.("strap_heel_dep_lop", heel, {0, 0, 1}), "sole_dep_lop"}
      ],
      source:
        "A sandal of tire rubber (dép lốp, dép Bác Hồ): a sole cut from a tire and straps cut from an inner tube (pure gum rubber, 0.92 g/cm3, The Engineering ToolBox), each end through a slit in the sole; by eye from the photos of Wikimedia Commons (Hanoi - Ho Chi Minh sandals for sale, Category: Tire sandals)."
    )
  end

  @doc """
  A wooden clog (guốc mộc) for the right foot of a person. The options:
  `person`, and `heel` (`:flat`, or `:high`: a wedge heel of 70 mm).
  """
  def clog(opts \\ []) do
    high = Keyword.get(opts, :heel, :flat) == :high
    last = Last.new(Keyword.get(opts, :person, if(high, do: [gender: 0.0], else: [])))
    {heel, ball, rise} = if high, do: {0.07, 0.014, 0.0}, else: {0.016, 0.016, 0.008}
    name = if high, do: "guoc_cao_vn", else: "guoc_moc_vn"

    sole =
      Sole.stack(
        last,
        [
          [
            name: "pad_#{name}",
            heel: 0.003,
            role: :black,
            matter: :rubber_sole,
            side: 0.007,
            source:
              "The grip pad: rubber of 3 mm under the sole (Tuổi Trẻ News, 2023: a grip pad makes the clog non-slip); its thickness by eye."
          ],
          [
            name: "sole_#{name}",
            heel: heel,
            ball: ball,
            role: :wood,
            matter: :vong,
            side: 0.008,
            source:
              "The sole: vông wood (Erythrina, a light wood of clogs, Vietnam Discovery), #{round(heel * 1000)} mm at the heel and #{round(ball * 1000)} mm at the ball, by eye from the photos."
          ]
        ],
        rise: rise
      )

    {w, t, side} = {0.055, 0.002, 0.008}
    band = Upper.band(last, 0.68, sole.top, {side, 0.006})

    strap =
      Webbing.strap("band_#{name}", band, w, thickness: t, across: {0, 1, 0}, matter: :plastic, material: :plastic)

    strap = %{
      strap
      | shapes: strap.shapes ++ Upper.nails(band, {w, t}, 3),
        sources:
          strap.sources ++ ["Three nails of steel at each end, 2 mm across and 12 mm long (by eye from the photos)."]
    }

    assemble(name, :clog, last, sole, [{"band_#{name}", strap, "sole_#{name}"}],
      source:
        "A wooden clog (guốc mộc): a sole of wood and one wide strap of clear plastic nailed to its sides, on a grip pad; by eye from the photos of the shop of Trần Thị Hoàng Yến in Vĩnh Long (Tuổi Trẻ News, Woman spends 3 decades making traditional clogs by hand, 2023)."
    )
  end

  # The assembly of a shoe: the layers of its sole, each on the one under
  # it, then each node `{name, part, parent}` on a port of its parent at
  # the port of the part (`World.Footwear.Upper.port_of/1`).
  defp assemble(name, kind, %Last{} = last, %{parts: sole}, nodes, opts) do
    at = Enum.group_by(nodes, &elem(&1, 2), fn {n, p, _} -> {n, Part.port!(p, Upper.port_of(p)).at} end)

    with_ports = fn %Part{} = p ->
      more = Map.new(Map.get(at, p.name, []), fn {n, point} -> {n, Part.port(n, point, {0, 0, 1}, {0, 1, 0})} end)
      %{p | ports: Map.merge(p.ports, more)}
    end

    [root | rest] = Enum.map(sole, with_ports)

    a =
      Assembly.new(name, root,
        root: root.name,
        kind: kind,
        materials: Keyword.get(opts, :materials, %{}),
        sources: [
          Keyword.fetch!(opts, :source) <>
            " For the right foot of a person of MakeHuman (#{round(last.foot * 1000)} mm long, EU size #{Last.eu_size(last.foot)}); the sole has the length of the last (the foot and 2 Paris points, Wikipedia, Shoe size)."
        ],
        extras: %{
          "foot" => Float.round(last.foot, 4),
          "eu_size" => Last.eu_size(last.foot),
          "last" => Float.round(last.length, 4)
        }
      )

    {a, _} =
      Enum.reduce(rest, {a, root.name}, fn p, {acc, below} ->
        {Assembly.add(acc, p.name, p, at: "o", port: "o", to: below), p.name}
      end)

    Enum.reduce(nodes, a, fn {n, p, parent}, acc ->
      Assembly.add(acc, n, with_ports.(p), at: n, port: Upper.port_of(p), to: parent)
    end)
  end
end
