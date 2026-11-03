defmodule World.Molds do
  @moduledoc """
  The things of the mold shop (`docs/world.md`, step P6; the family
  `:molds`): shells from molds, each made with `World.Loft`.

  - `half_helmet/1`: the half helmet of Việt Nam (mũ bảo hiểm che nửa
    đầu): a shell of ABS over a liner of EPS, with a peak and a strap.
  """
  alias World.{Assembly, Loft, Part, Shape, Vec}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # QCVN 2:2021/BKHCN (Bảng 1): the mass of a half helmet or a helmet of
  # three quarters is 1 kg or less for the head sizes 4 to 9, and 0.8 kg or
  # less for the sizes 1 to 3.
  @mass_limit 1.0

  # Trzaskalska and Chwastek, "Analysis of the protective helmets",
  # Archives of Metallurgy and Materials 66 (2021): a liner of EPS of 30
  # to 40 mm, a shell of a thermoplastic of 4 to 5 mm. The model takes the
  # least of each.
  @liner 0.030
  @shell 0.004
  # The gap between the head and the liner (the comfort pad): by eye.
  @gap 0.003

  @doc "The models of the mold shop, as `{name, fun}`."
  def models, do: [{"helmet_half_vn", fn -> half_helmet() end}]

  @doc "The mass limit of a half helmet of the large head sizes (kg, QCVN 2:2021/BKHCN)."
  def mass_limit, do: @mass_limit

  @doc """
  The half helmet of Việt Nam, for a head of the circumference `c` (m,
  0.57 by default). The options: `color` (`[r, g, b]` of the shell).

  The head over the rim is half of an ellipsoid: its length along y, its
  breadth across x (0.82 of the length, by eye), its height over the rim
  0.10 m (by eye). The circumference of the ellipse of the rim is `c`
  (Ramanujan). Out from the head: the gap, the liner of EPS, and the
  shell of ABS. The peak at the front, the strap and its buckle: by eye.

  The axes: x across, y to the front, z up from the rim.
  """
  def half_helmet(c \\ 0.57, opts \\ []) do
    # The half axes of the head at the rim: a along y, b across x.
    r = 0.82
    a = c / (:math.pi() * (3 * (1 + r) - :math.sqrt((3 + r) * (1 + 3 * r))))
    {b, h} = {r * a, 0.10}

    liner_out = @gap + @liner
    shell_out = liner_out + @shell

    liner = dome(b + liner_out, a + liner_out, h + liner_out)
    shell = dome(b + shell_out, a + shell_out, h + shell_out)
    {sx, sy} = {b + shell_out, a + shell_out}

    color = Keyword.get(opts, :color, [236, 232, 222])

    shell_part =
      Part.new(
        "shell_helmet_half",
        :shell,
        [Loft.shell(shell, @shell, :paint) |> World.Mesh.matter(:plastic) | peak(sx, sy)],
        [@o, Part.port("liner", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}), Part.port("strap", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
        params: %{"area" => Float.round(Loft.area(shell), 4), "thickness" => @shell},
        sources: [
          "The shell: ABS of #{mm(@shell)} mm, the least of a thermoplastic shell (Trzaskalska and Chwastek, Archives of Metallurgy and Materials 66, 2021); a peak of 40 mm at the front, by eye."
        ]
      )

    liner_part =
      Loft.part(liner, "liner_helmet_half", :liner, [@o], @liner, :eps,
        matter: :eps_helmet,
        sources: [
          "The liner: EPS of #{mm(@liner)} mm and 45 kg/m3, the least thickness and the middle density of a liner (Trzaskalska and Chwastek, 2021)."
        ]
      )

    Assembly.new("helmet_half_vn", shell_part,
      root: "shell_helmet_half",
      kind: :helmet,
      materials: %{paint: %{"color" => color, "roughness" => 0.35, "metalness" => 0.0}},
      sources: [
        "A half helmet of Việt Nam (QCVN 2:2021/BKHCN, mũ che nửa đầu): a mass of 1 kg or less for the head sizes 4 to 9; for a head of #{round(c * 100)} cm."
      ],
      extras: %{"head" => c, "mass_limit" => @mass_limit}
    )
    |> Assembly.add("liner_helmet_half", liner_part, at: "liner", port: "o")
    |> Assembly.add("strap_helmet_half", strap(sx), at: "strap", port: "o")
  end

  # A half ellipsoid over the rim (z = 0), as sections along z to the
  # crown: x across (hx), y along (hy), the height hz.
  defp dome(hx, hy, hz) do
    k = 12
    angles = for i <- 0..k, do: :math.pi() / 2 * i / k
    spine = for t <- angles, do: {0.0, 0.0, hz * :math.sin(t)}

    sections =
      for {t, i} <- Enum.with_index(angles),
          do: if(i == k, do: {0, 0, 2}, else: {hx * :math.cos(t), hy * :math.cos(t), 2})

    Loft.new(spine, sections, sides: 32, up: {1, 0, 0})
  end

  # The peak: a plate of 3 mm and 40 mm out from the rim at the front,
  # from -50 to 50 degrees around the front, down by 15 degrees.
  defp peak(sx, sy) do
    {out, t, down} = {0.04, 0.003, 15 * :math.pi() / 180}

    sections =
      for i <- 0..10 do
        phi = (-50 + 100 * i / 10) * :math.pi() / 180
        p = {sx * :math.sin(phi), sy * :math.cos(phi), 0.004}
        # The normal of the ellipse of the rim, out.
        n = Vec.norm({:math.sin(phi) / sx, :math.cos(phi) / sy, 0.0})
        u = Vec.norm(Vec.add(n, {0.0, 0.0, -:math.tan(down)}))
        v = Vec.norm(Vec.cross(Vec.cross(u, {0.0, 0.0, 1.0}), u))
        # Less out at the ends of the peak.
        w = out * (0.35 + 0.65 * :math.cos(phi * 1.6))
        {Vec.add(p, Vec.scale(u, w / 2 - 0.002)), u, v, w / 2, t / 2, 8}
      end

    [Shape.loft(sections, :paint, sides: 12) |> World.Mesh.matter(:plastic)]
  end

  # The strap: a webbing of 20 mm from a rivet on each side of the rim to
  # the buckle under the chin, 0.13 m under the rim (by eye).
  defp strap(sx) do
    buckle = {0.0, 0.07, -0.13}

    straps =
      for sign <- [1, -1] do
        rivet = {sign * (sx + 0.001), -0.005, 0.012}
        d = Vec.norm(Vec.sub(buckle, rivet))
        w = Vec.norm(Vec.sub({0.0, 1.0, 0.0}, Vec.scale(d, Vec.dot({0.0, 1.0, 0.0}, d))))
        th = Vec.cross(d, w)
        end_ = Vec.add(buckle, {sign * 0.012, 0.0, 0.0})
        Shape.loft([{rivet, w, th, 0.01, 0.0006, 8}, {end_, w, th, 0.01, 0.0006, 8}], :black, sides: 12)
      end

    {bx, by, bz} = buckle

    clip =
      Shape.box({bx - 0.012, by - 0.004, bz - 0.012}, {bx + 0.012, by + 0.006, bz + 0.012}, :black)
      |> World.Mesh.matter(:plastic)

    Part.new("strap_helmet_half", :strap, straps ++ [clip], [@o],
      sources: ["The strap: a webbing of 20 mm with a buckle under the chin, by eye."]
    )
  end

  defp mm(m), do: round(m * 1000)
end
