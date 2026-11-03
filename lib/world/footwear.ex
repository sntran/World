defmodule World.Footwear do
  @moduledoc """
  The shoe shop of the world (the family `:footwear`): footwear on the
  foot of a person (`World.People.Human.footprint/2`).

  - `sandal/1`: a sandal with straps (xăng-đan quai hậu of Việt Nam): a
    midsole of EVA on an outsole of rubber, each a molded part on the
    footprint of the foot, and three straps: over the toes, over the
    instep, and round the heel. The straps are webbing
    (`World.Materials.Webbing`): the instep strap goes through a D-ring
    and closes on itself with hook and loop, and a tri-glide sets the
    heel strap. With `leather: true`, the straps are leather, and the
    instep strap closes with a pin buckle.

  The size: one Paris point is 2/3 cm; the EU size is 3/2 of the length
  of the last in cm, and the last is about 2 Paris points longer than
  the foot (Wikipedia, Shoe size, the European system). The sole has the
  length of the last.

  The axes: x across (to the outside of a right foot), y from the heel to
  the toes, z up from the ground.
  """
  alias World.{Assembly, Frame, Part, Shape}
  alias World.Materials.Webbing
  alias World.People.Human

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # A Paris point (m).
  @paris 2 / 300
  # The sole out from the foot: 4 mm at the heel and 6 mm at each side
  # (the rest of 2 Paris points is at the toes); by eye.
  @heel 0.004
  @side 0.006
  # The outsole of rubber, and the midsole of EVA at the heel and at the
  # ball of the foot (by eye).
  @outsole 0.004
  @mid {0.020, 0.012}
  # The webbing, and the places of the toe strap and the instep strap: a
  # part of the length of the foot from the heel (by eye; the top of the
  # foot under the instep strap is under its ankle).
  @strap 0.025
  @toe 0.75
  @instep 0.55

  @doc "The models of the shoe shop, as `{name, fun}`."
  def models,
    do: [{"sandal_vn", fn -> sandal() end}, {"sandal_leather_vn", fn -> sandal(leather: true) end}]

  @doc """
  The EU size of a shoe for a foot of a length (m).

      iex> World.Footwear.eu_size(0.24)
      38
      iex> World.Footwear.eu_size(0.26)
      41
  """
  def eu_size(foot), do: round(1.5 * (foot + 2 * @paris) * 100)

  @doc """
  A sandal for the right foot of a person. The options: `person` (the
  options of `World.People.Human.person/2`: the shape of the foot) and
  `leather` (straps of leather and a pin buckle, `false` by default).
  """
  def sandal(opts \\ []) do
    fp = Human.footprint(Keyword.get(opts, :person, []), "r")
    leather = Keyword.get(opts, :leather, false)
    last = fp.length + 2 * @paris
    rows = rows(fp)

    zt = fn y -> @outsole + thickness(y, last) end

    sole = sole(rows, last)
    {xa, xb, top} = at(rows, @instep * fp.length + @heel)
    instep_y = @instep * fp.length + @heel
    {ta, tb, ttop} = at(rows, @toe * fp.length + @heel)
    toe_y = @toe * fp.length + @heel

    toe = arch(toe_y, ta - 0.003, tb + 0.003, ttop, zt.(toe_y))
    # The instep strap: over the foot, then straight down the outside to
    # its ring.
    z0 = zt.(instep_y)
    xo = xb + 0.003
    over = arch(instep_y, xa - 0.003, xo, top, z0) |> Enum.drop(-3)
    instep = over ++ [{xo, instep_y, z0 + 0.035}, {xo, instep_y, z0 + 0.012}]
    heel = heel_path(rows, fp.length, zt)

    {matter, t, color} =
      if leather, do: {:leather, 0.003, :paint}, else: {:nylon, 0.0015, :black}

    strap = fn name, path, across, ports ->
      Webbing.strap(name, path, @strap, thickness: t, across: across, matter: matter, material: color, ports: ports)
    end

    back = Enum.min_by(heel, &elem(&1, 1))
    down = Frame.new({xo + 0.003, instep_y, z0 + 0.035}, {1, 0, 0}, {0, 1, 0})

    closure =
      if leather do
        [{"buckle_sandal", Webbing.pin_buckle("buckle_sandal", @strap, frame: down), "closure"}]
      else
        ring = Frame.new({xo - 0.003, instep_y, z0 + 0.01}, {0, 0, 1}, {0, 1, 0})
        patch = Frame.new({xo + 0.001, instep_y, z0 + 0.035}, {1, 0, 0}, {0, 1, 0})
        fold = [{xo + 0.0035 + t / 2, instep_y, z0 + 0.012}, {xo + 0.0035 + t / 2, instep_y, z0 + 0.036}]

        [
          {"ring_sandal", Webbing.d_ring("ring_sandal", @strap, frame: ring), "ring"},
          {"patch_sandal", Webbing.hook_loop("patch_sandal", @strap, 0.02, frame: patch), "patch"},
          {"fold_sandal", strap.("fold_sandal", fold, {0, 1, 0}, []), "fold"}
        ]
      end

    closure_ports =
      for {_, p, port} <- closure,
          do: {port, if(p.kind == :strap, do: Part.port!(p, "a").at, else: Part.port!(p, "o").at)}

    parts = [
      {"strap_toe_sandal", strap.("strap_toe_sandal", toe, {0, 1, 0}, [])},
      {"strap_instep_sandal", strap.("strap_instep_sandal", instep, {0, 1, 0}, closure_ports)},
      {"strap_heel_sandal", strap.("strap_heel_sandal", heel, {0, 0, 1}, [{"glide", back}])}
    ]

    {outsole, midsole} = sole

    midsole = %{
      midsole
      | ports:
          Map.merge(
            midsole.ports,
            Map.new(parts, fn {n, p} -> {n, Part.port(n, Part.port!(p, "a").at, {0, 0, 1}, {0, 1, 0})} end)
          )
    }

    glide = Webbing.tri_glide("glide_sandal", @strap, frame: Frame.new(back, {0, -1, 0}, {0, 0, 1}))

    a =
      Assembly.new(if(leather, do: "sandal_leather_vn", else: "sandal_vn"), outsole,
        root: "outsole_sandal",
        kind: :sandal,
        materials: %{paint: %{"color" => [120, 72, 40], "roughness" => 0.7, "metalness" => 0.0}},
        sources: [
          "A sandal with straps (xăng-đan quai hậu) for the right foot of a person of MakeHuman (#{round(fp.length * 1000)} mm long, EU size #{eu_size(fp.length)}): the sole has the length of the last (the foot and 2 Paris points, Wikipedia, Shoe size)."
        ],
        extras: %{"foot" => Float.round(fp.length, 4), "eu_size" => eu_size(fp.length), "last" => Float.round(last, 4)}
      )
      |> Assembly.add("midsole_sandal", midsole, at: "o", port: "o")

    a = Enum.reduce(parts, a, fn {n, p}, acc -> Assembly.add(acc, n, p, at: n, port: "a", to: "midsole_sandal") end)

    a =
      Enum.reduce(closure, a, fn {n, p, port}, acc ->
        Assembly.add(acc, n, p, at: port, port: if(p.kind == :strap, do: "a", else: "o"), to: "strap_instep_sandal")
      end)

    if leather, do: a, else: Assembly.add(a, "glide_sandal", glide, at: "glide", port: "o", to: "strap_heel_sandal")
  end

  # The rows of the footprint in the axes of the sandal: the heel of the
  # foot at y = @heel, the middle of the foot at x = 0. The base mesh is
  # sparse: each side is the widest of the row and the rows next to it,
  # then the mean of 5 rows.
  defp rows(%{rows: rows}) do
    [{y0, _, _, _} | _] = rows
    cx = rows |> Enum.map(fn {_, a, b, _} -> (a + b) / 2 end) |> then(&(Enum.sum(&1) / length(&1)))
    wide = near(rows, 1, fn group, {y, _, _, top} -> {y, min_of(group, 1), max_of(group, 2), top} end)

    near(wide, 2, fn group, {y, _, _, top} ->
      {y - y0 + @heel, mean_of(group, 1) - cx, mean_of(group, 2) - cx, top}
    end)
  end

  # Each row with the rows within k of it.
  defp near(rows, k, fun) do
    t = List.to_tuple(rows)
    n = tuple_size(t)
    for i <- 0..(n - 1), do: fun.(for(j <- max(i - k, 0)..min(i + k, n - 1), do: elem(t, j)), elem(t, i))
  end

  defp min_of(group, i), do: group |> Enum.map(&elem(&1, i)) |> Enum.min()
  defp max_of(group, i), do: group |> Enum.map(&elem(&1, i)) |> Enum.max()
  defp mean_of(group, i), do: (group |> Enum.map(&elem(&1, i)) |> Enum.sum()) / length(group)

  # The row nearest to y: `{x0, x1, top}`.
  defp at(rows, y) do
    {_, x0, x1, top} = Enum.min_by(rows, fn {ry, _, _, _} -> abs(ry - y) end)
    {x0, x1, top}
  end

  # The thickness of the midsole: from the heel to the ball, then the same
  # to the toes.
  defp thickness(y, last) do
    {heel, ball} = @mid
    s = min(y / (0.65 * last), 1.0)
    heel + (ball - heel) * s
  end

  # The outsole and the midsole: sections along y, each the width of the
  # foot and @side at each side, the length of the last.
  defp sole(rows, last) do
    ys = Enum.take_every(rows, 2)
    {_, a0, b0, _} = hd(ys)
    {_, a1, b1, _} = List.last(ys)

    stations =
      [{0.0, (a0 + b0) / 2, (b0 - a0) * 0.6}] ++
        for({y, a, b, _} <- ys, do: {y, (a + b) / 2, b - a + 2 * @side}) ++
        [{last, (a1 + b1) / 2, (b1 - a1) * 0.6}]

    loft = fn z_of, h_of, role, matter ->
      stations
      |> Enum.map(fn {y, cx, w} -> {{cx, y, z_of.(y)}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, w / 2, h_of.(y) / 2, 6} end)
      |> Shape.loft(role, sides: 24)
      |> World.Mesh.matter(matter)
    end

    out = loft.(fn _ -> @outsole / 2 end, fn _ -> @outsole end, :rubber, :rubber_sole)
    mid = loft.(fn y -> @outsole + thickness(y, last) / 2 end, &thickness(&1, last), :eps, :eva)
    {heel, ball} = @mid

    {Part.new("outsole_sandal", :sole, [out], [@o],
       params: %{"thickness" => @outsole, "length" => Float.round(last, 4)},
       sources: [
         "The outsole: rubber of #{mm(@outsole)} mm (soft commercial rubber, 1.1 g/cm3, The Engineering ToolBox), by eye."
       ]
     ),
     Part.new("midsole_sandal", :sole, [mid], [@o],
       params: %{"heel" => heel, "ball" => ball},
       sources: [
         "The midsole: EVA of #{mm(heel)} mm at the heel and #{mm(ball)} mm at the ball (by eye), 240 kg/m3 (Footwear Science)."
       ]
     )}
  end

  # A strap over the foot at y, from the side x0 to the side x1, its top
  # 4 mm over the top of the foot, its ends on the sole (z0).
  defp arch(y, x0, x1, top, z0) do
    for i <- 0..10, s = i / 10, do: {x0 + (x1 - x0) * s, y, z0 + (top + 0.004 - z0) * :math.sin(:math.pi() * s) ** 0.5}
  end

  # The heel strap: from the sole on the outside, up and round the back of
  # the heel 40 mm over the sole, to the sole on the inside; 4 mm out from
  # the foot.
  defp heel_path(rows, length, zt) do
    back = Enum.filter(rows, fn {y, _, _, _} -> y <= 0.12 * length + @heel end)
    zh = zt.(0.0) + 0.04
    {_, ea, eb, _} = Enum.min_by(rows, fn {y, _, _, _} -> abs(y - 0.25 * length) end)
    ye = 0.25 * length + @heel
    {_, ba, bb, _} = hd(back)

    outside = for {y, _, b, _} <- Enum.reverse(back), do: {b + 0.004, y, zh}
    inside = for {y, a, _, _} <- back, do: {a - 0.004, y, zh}

    [{eb + 0.003, ye, zt.(ye)}] ++ outside ++ [{(ba + bb) / 2, 0.0, zh}] ++ inside ++ [{ea - 0.003, ye, zt.(ye)}]
  end

  defp mm(m), do: round(m * 1000)
end
