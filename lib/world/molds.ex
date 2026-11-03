defmodule World.Molds do
  @moduledoc """
  The things of the mold shop (`docs/world.md`, step P6; the family
  `:molds`): shells from molds, each made with `World.Loft`.

  - `headform/1`: a headform (dạng đầu) of QCVN 2:2021/BKHCN, from the
    polar coordinates of its sections (`priv/standards/helmet.json`).
  - `half_helmet/2`: the half helmet of Việt Nam (mũ bảo hiểm che nửa
    đầu) on a headform: the parts of Hình 2 of QCVN 2:2021, each a part
    of its own: the shell, the liner, the comfort pad, the edge trim, the
    rivets, the straps of webbing and the buckle
    (`World.Materials.Webbing`), and the peak (an optional part, 3.2.2).
  - `shell_chair/1`: a chair with a seat shell of glass fiber, laid up by
    hand in a mold (`World.Materials.Laminate`): the pan and the back of
    one open shell along a bent spine, on four legs of steel tube.
  """
  alias World.{Assembly, Frame, Loft, Part, Shape, Standards, Vec}
  alias World.Materials.{Laminate, Webbing}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @sizes ~w(1 2 3 4 5 6 7 8 9)

  # Trzaskalska and Chwastek, "Analysis of the protective helmets",
  # Archives of Metallurgy and Materials 66 (2021): a liner of EPS of 30
  # to 40 mm, a shell of a thermoplastic of 4 to 5 mm. The model takes the
  # least of each.
  @liner 0.030
  @shell 0.004
  # The comfort pad between the head and the liner: by eye.
  @gap 0.003
  # The webbing of the strap, and the head of a rivet: by eye.
  @webbing 0.02
  @rivet {0.005, 0.0015}

  @doc "The models of the mold shop, as `{name, fun}`."
  def models, do: [{"helmet_half_vn", fn -> half_helmet() end}, {"chair_shell_frp", fn -> shell_chair() end}]

  @doc "The sizes of a headform: \"1\" to \"9\"."
  def sizes, do: @sizes

  @doc """
  The mass limit of a helmet of a kind (`"half"`, `"three_quarter"`,
  `"open_face"`, `"full_face"`) for a size of headform (kg, QCVN
  2:2021/BKHCN, 5.2).

      iex> World.Molds.mass_limit("half", "6")
      1.0
      iex> World.Molds.mass_limit("full_face", "2")
      1.2
  """
  def mass_limit(kind, size) when size in @sizes do
    [small, large] = Standards.size({"helmet", "mass"}, kind)
    if size in ~w(1 2 3), do: small, else: large
  end

  @doc """
  A headform of a size: `%{circumference, x, y, loft}`, in m. The loft is
  the upper part of the headform, over its reference plane (z = 0): a
  section at each height of the table, a ring of 24 points from the front
  (+y) around the right side (+x) to the back and around the left side,
  and the top at the height Y.
  """
  def headform(size) when size in @sizes do
    [c, x, y] = Standards.size({"helmet", "headform"}, size)
    rows = Standards.size({"helmet", "sections"}, size)

    spine = for([h | _] <- rows, do: {0.0, 0.0, h / 1000}) ++ [{0.0, 0.0, y / 1000}]
    sections = for([_ | radii] <- rows, do: ring(radii)) ++ [{0, 0, 2}]

    %{circumference: c / 1000, x: x / 1000, y: y / 1000, loft: Loft.new(spine, sections, up: {1, 0, 0})}
  end

  # A ring of a section: the radii at 0, 15, ... 180 degrees from the
  # front, on the right side, then the left side back to the front.
  defp ring(radii) do
    right =
      for {r, i} <- Enum.with_index(radii),
          a = i * 15 * :math.pi() / 180,
          do: {r / 1000 * :math.sin(a), r / 1000 * :math.cos(a)}

    left = for {px, py} <- right |> Enum.slice(1..11) |> Enum.reverse(), do: {-px, py}
    right ++ left
  end

  @doc """
  The half helmet of Việt Nam on the headform of a size (\"6\", a head of
  56 cm, by default). The options: `color` (`[r, g, b]` of the shell).

  Out from the headform: the comfort pad, the liner of EPS and the shell
  of ABS, each the thickness out from the one under it. The rim is on the
  reference plane of the headform, under the line AA' (12.7 mm over it):
  the helmet covers the headform over AA', as 6.4.1 b) asks. The rivets
  of the straps are on the sides, at 105 degrees from the front; the
  buckle is under the chin, and the peak at the front (by eye).

  The axes: x across, y to the front, z up from the reference plane.
  """
  def half_helmet(size \\ "6", opts \\ []) when size in @sizes do
    head = headform(size)
    pad = Loft.grow(head.loft, @gap)
    liner = Loft.grow(head.loft, @gap + @liner)
    shell = Loft.grow(head.loft, @gap + @liner + @shell)
    {shell_rows, _} = Loft.rows(shell)
    {liner_rows, _} = Loft.rows(liner)
    rim = hd(shell_rows)

    color = Keyword.get(opts, :color, [236, 232, 222])

    # A rivet on each side, on the outside of the shell, 6 mm over the
    # rim, at 105 degrees from the front (the index 7 of the ring), and its
    # normal out.
    rivet = fn sign ->
      p = Enum.at(rim, if(sign > 0, do: 7, else: 17))
      {px, py, pz} = p
      {Vec.add(p, {0.0, 0.0, 0.006}), Vec.norm({px, py, 0.0}), pz}
    end

    bl = Webbing.buckle("buckle_helmet_half", @webbing)
    buckle_len = elem(Part.port!(bl, "male").at, 0)
    chin = {-buckle_len / 2, 0.07, -0.13}

    shell_part =
      Loft.part(shell, "shell_helmet_half", :shell, [@o | ports(rivet)], @shell, :paint,
        matter: :plastic,
        sources: [
          "The shell: ABS of #{mm(@shell)} mm, the least of a thermoplastic shell (Trzaskalska and Chwastek, Archives of Metallurgy and Materials 66, 2021), over the headform of the size #{size} of QCVN 2:2021/BKHCN."
        ]
      )

    liner_part =
      Loft.part(
        liner,
        "liner_helmet_half",
        :liner,
        [@o, Part.port("pad", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
        @liner,
        :eps,
        matter: :eps_helmet,
        sources: [
          "The liner (đệm hấp thụ xung động): EPS of #{mm(@liner)} mm and 45 kg/m3, the least thickness and the middle density of a liner (Trzaskalska and Chwastek, 2021)."
        ]
      )

    pad_part =
      Loft.part(pad, "pad_helmet_half", :pad, [@o], @gap, :fabric,
        matter: :pu_foam,
        sources: [
          "The comfort pad (lớp vải lót, đệm lót trong): PU foam of #{mm(@gap)} mm (30 kg/m3, The Engineering ToolBox), on the headform; it gives the fit, not the protection (GRSP, Helmet standards guide, 2025)."
        ]
      )

    # A strap from each rivet down the shell to under the rim, then to its
    # end of the buckle, in the axes of the rivet.
    strap = fn name, sign, to ->
      {at, _, _} = rivet.(sign)
      Webbing.strap(name, [{0.0, 0.0, 0.0}, {0.0, 0.0, -0.012}, Vec.sub(to, at)], @webbing, across: {0, 1, 0})
    end

    {cx, cy, cz} = chin

    Assembly.new("helmet_half_vn", shell_part,
      root: "shell_helmet_half",
      kind: :helmet,
      materials: %{paint: %{"color" => color, "roughness" => 0.35, "metalness" => 0.0}},
      sources: [
        "A half helmet of Việt Nam (QCVN 2:2021/BKHCN, mũ che nửa đầu) on the headform of the size #{size} (a head of #{round(head.circumference * 100)} cm): its parts from 3.2 and Hình 2, its mass under the limit of 5.2."
      ],
      extras: %{"size" => size, "head" => head.circumference, "mass_limit" => mass_limit("half", size)}
    )
    |> Assembly.add("liner_helmet_half", liner_part, at: "liner", port: "o")
    |> Assembly.add("pad_helmet_half", pad_part, at: "pad", port: "o", to: "liner_helmet_half")
    |> Assembly.add("trim_helmet_half", trim(rim, hd(liner_rows)), at: "trim", port: "o")
    |> Assembly.add("peak_helmet_half", peak(rim), at: "peak", port: "o")
    |> Assembly.add("rivet_left_helmet_half", rivet_part("rivet_left_helmet_half", rivet.(-1)),
      at: "rivet_left",
      port: "o"
    )
    |> Assembly.add("rivet_right_helmet_half", rivet_part("rivet_right_helmet_half", rivet.(1)),
      at: "rivet_right",
      port: "o"
    )
    |> Assembly.add("strap_left_helmet_half", strap.("strap_left_helmet_half", -1, chin), at: "rivet_left", port: "a")
    |> Assembly.add("strap_right_helmet_half", strap.("strap_right_helmet_half", 1, {cx + buckle_len, cy, cz}),
      at: "rivet_right",
      port: "a"
    )
    |> Assembly.add("buckle_helmet_half", bl, at: "b", port: "female", to: "strap_left_helmet_half")
  end

  # The ports of the shell: its liner, its trim, its peak, and a rivet on
  # each side.
  defp ports(rivet) do
    [
      Part.port("liner", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
      Part.port("trim", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
      Part.port("peak", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
      Part.port("rivet_left", elem(rivet.(-1), 0), {0, 0, 1}, {0, 1, 0}),
      Part.port("rivet_right", elem(rivet.(1), 0), {0, 0, 1}, {0, 1, 0})
    ]
  end

  # A rivet: a round head of 10 mm and 1.5 mm out from the shell (5.4: at
  # most 2 mm), in the axes of its port.
  defp rivet_part(name, {_at, normal, _}) do
    {r, h} = @rivet
    head = Shape.cylinder(r, h, :steel, sides: 12, frame: Frame.new({0.0, 0.0, 0.0}, normal, {0, 0, 1}))

    Part.new(name, :rivet, [head], [@o],
      params: %{"head" => h, "diameter" => 2 * r},
      sources: [
        "A rivet of steel with a round head of #{mm(2 * r)} mm, #{h * 1000} mm out from the shell (QCVN 2:2021/BKHCN, 5.4: at most 2 mm); by eye."
      ]
    )
  end

  # The edge trim (bọc mép): a band of rubber round the rim of the shell
  # and the liner.
  defp trim(rim, liner_rim) do
    line = Enum.zip_with(rim, liner_rim, fn a, b -> Vec.scale(Vec.add(a, b), 0.5) end)

    band =
      (line ++ [hd(line)])
      |> Shape.sweep(@shell / 2 + 0.0015, :black, sides: 8)
      |> World.Mesh.matter(:rubber)

    Part.new("trim_helmet_half", :trim, [band], [@o],
      sources: [
        "The edge trim (bọc mép, QCVN 2:2021/BKHCN, Hình 2): rubber round the rim of the shell; its size by eye."
      ]
    )
  end

  # The peak (lưỡi trai, an optional part, 3.2.2): a plate of 3 mm and up
  # to 40 mm out from the rim at the front, from -45 to 45 degrees, down by
  # 15 degrees.
  defp peak(rim) do
    {out, t, down} = {0.04, 0.003, 15 * :math.pi() / 180}

    sections =
      for {k, i} <- Enum.with_index([21, 22, 23, 0, 1, 2, 3]) do
        {px, py, pz} = Enum.at(rim, k)
        n = Vec.norm({px, py, 0.0})
        u = Vec.norm(Vec.add(n, {0.0, 0.0, -:math.tan(down)}))
        v = Vec.norm(Vec.cross(Vec.cross(u, {0.0, 0.0, 1.0}), u))
        # Less out at the ends of the peak.
        w = out * (0.4 + 0.6 * :math.cos((i - 3) * 15 * :math.pi() / 180 * 1.6))
        {Vec.add({px, py, pz + 0.004}, Vec.scale(u, w / 2 - 0.002)), u, v, w / 2, t / 2, 8}
      end

    Part.new("peak_helmet_half", :peak, [Shape.loft(sections, :paint, sides: 12) |> World.Mesh.matter(:plastic)], [@o],
      sources: [
        "The peak (lưỡi trai, QCVN 2:2021/BKHCN, 3.2.2): ABS of 3 mm, 40 mm out from the rim at the front, by eye."
      ]
    )
  end

  @doc """
  The angle of the view up from the point K of the headform (degrees):
  the least angle over the horizontal from K to a point of the helmet in
  front of K, in the plane of symmetry (6.9; 5.10 b asks 7 degrees at the
  least). K is the front of the headform on its basic plane, X under the
  reference plane; the model takes the front of the headform there as the
  front at the reference plane.
  """
  def vision_up(%Assembly{} = g, size) when size in @sizes do
    head = headform(size)
    {[[front | _] | _], _} = Loft.rows(head.loft)
    {_, ky, _} = front
    kz = -head.x

    for {_, p} <- World.Build.placed(g), m <- p.shapes, {x, y, z} <- m.points, abs(x) < 0.01, y > ky do
      :math.atan2(z - kz, y - ky) * 180 / :math.pi()
    end
    |> Enum.min()
  end

  defp mm(m), do: round(m * 1000)

  # --- The shell chair ----------------------------------------------------------------------

  # The spine of the shell, from the front of the pan to the top of the
  # back ({y, z}, m), and the section at each point: {the depth of the
  # dish, its half width, its power}. The sizes are those of a molded
  # shell chair on four legs: 0.81 m high, 0.48 m wide, 0.55 m deep, the
  # seat at 0.445 m (Herman Miller, the data sheet of a molded fiberglass
  # side chair); the shape of the pan and of the back is by eye.
  @spine [{0.26, 0.44}, {0.05, 0.425}, {-0.15, 0.43}, {-0.2, 0.46}, {-0.23, 0.53}, {-0.26, 0.65}, {-0.29, 0.8}]
  @dish [
    {0.02, 0.22, 2.5},
    {0.05, 0.235, 2.5},
    {0.06, 0.225, 2.5},
    {0.06, 0.21, 2.5},
    {0.06, 0.205, 2.5},
    {0.05, 0.22, 2.5},
    {0.03, 0.235, 2.5}
  ]

  # The legs: steel tube of 19 mm with a wall of 1.9 mm (14 gauge; MooreCo,
  # the data sheet of the Seed chair on four legs), from the pan to the
  # floor, a little out at the floor.
  @leg {0.0095, 0.0019}

  @doc """
  A chair with a seat shell of glass fiber (the kind `:chair`, the mold
  shop): the pan and the back of one open shell (`World.Loft`) along a
  bent spine, of a laminate laid up by hand (the gel coat and 3 plies of
  chopped strand mat of 450 g/m2 by default: the option `plies`), on four
  legs of steel tube. The option `color`: the color of the gel coat.
  """
  def shell_chair(opts \\ []) do
    laminate = Laminate.new(Keyword.get(opts, :plies, ~w(csm_450 csm_450 csm_450)))
    t = Laminate.thickness(laminate)
    spine = for {y, z} <- @spine, do: {0.0, y, z}
    loft = Loft.new(spine, @dish, arc: {90, 270}, up: {0, 0, 1}, sides: 24)

    shell =
      Loft.part(loft, "shell_chair_frp", :shell, [@o], t, :paint,
        matter: Laminate.density(laminate),
        sources: [
          "The shell: #{Enum.join(laminate.plies, ", ")} with a gel coat, #{Float.round(t * 1000, 2)} mm and #{round(Laminate.density(laminate))} kg/m3 (World.Materials.Laminate, priv/standards/laminate.json)."
        ]
      )

    legs =
      for sx <- [1, -1], sy <- [1, -1] do
        top = {sx * 0.17, sy * 0.15 - 0.02, 0.37}
        foot = {sx * 0.22, sy * 0.24 - 0.02, 0.0}
        Shape.sweep([foot, top], elem(@leg, 0), :steel, sides: 10) |> World.Mesh.skin(elem(@leg, 1), :steel)
      end

    base =
      Part.new("legs_chair_frp", :legs, legs, [@o],
        sources: ["Four legs of steel tube, 19 mm with a wall of 1.9 mm (MooreCo, Seed chair, the data sheet)."]
      )

    color = Keyword.get(opts, :color, [212, 208, 196])

    Assembly.new("chair_shell_frp", base,
      root: "legs_chair_frp",
      kind: :chair,
      materials: %{paint: %{"color" => color, "roughness" => 0.4, "metalness" => 0.0}},
      sources: [
        "A chair with a seat shell of glass fiber and polyester resin, laid up by hand in a mold, on four legs of steel tube: the sizes of a molded shell chair (Herman Miller, the data sheet of a molded fiberglass side chair: 806 by 476 by 552 mm, the seat at 445 mm)."
      ],
      extras: %{"laminate" => laminate.plies, "thickness" => Float.round(t, 5)}
    )
    |> Assembly.add("shell_chair_frp", shell, at: "o", port: "o")
  end
end
