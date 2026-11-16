defmodule World.LoftTest do
  use ExUnit.Case, async: true

  alias World.{Loft, Mesh, Molds}

  doctest Molds

  # A half sphere of the radius r over z = 0, with its apex at the top.
  defp dome(r, k \\ 16) do
    spine = for i <- 0..k, do: {0.0, 0.0, r * :math.sin(:math.pi() / 2 * i / k)}

    sections =
      for i <- 0..k, c = :math.cos(:math.pi() / 2 * i / k), do: if(i == k, do: {0, 0, 2}, else: {r * c, r * c, 2})

    Loft.new(spine, sections, sides: 48, up: {1, 0, 0})
  end

  test "a shell of a half sphere: its area and its volume, as the half sphere" do
    {r, t} = {0.1, 0.004}
    l = dome(r)
    assert_in_delta Loft.area(l), 2 * :math.pi() * r * r, 0.01 * 2 * :math.pi() * r * r

    m = Loft.shell(l, t, :plastic)
    v = Mesh.volume(m.points, m.faces) / 6
    exact = 2 * :math.pi() / 3 * (r ** 3 - (r - t) ** 3)
    assert_in_delta v, exact, 0.01 * exact

    # The apex is one point of the outside and one of the inside.
    {rows, _} = Loft.rows(l)
    assert length(List.last(rows)) == 1
    assert length(World.Mesh.triangles(m, 0)) > 0
  end

  test "an open shell along a bent spine: its volume is its area times its thickness" do
    spine = for i <- 0..10, a = :math.pi() / 2 * i / 10, do: {0.0, 0.3 * :math.sin(a), 0.3 * (1 - :math.cos(a))}
    l = Loft.new(spine, List.duplicate({0.2, 0.05, 4}, 11), arc: {180, 360}, up: {1, 0, 0})
    t = 0.005
    m = Loft.shell(l, t, :plastic)
    assert_in_delta Mesh.volume(m.points, m.faces) / 6, Loft.area(l) * t, 0.02 * Loft.area(l) * t
    assert length(World.Mesh.triangles(m, 0)) > 0
  end

  test "a bowl: the apex at the start of the spine, and u by default" do
    k = 8
    spine = for i <- 0..k, do: {0.0, 0.0, 0.1 * (1 - :math.cos(:math.pi() / 2 * i / k))}
    sections = for i <- 0..k, s = :math.sin(:math.pi() / 2 * i / k), do: {0.1 * s, 0.1 * s, 2}
    m = Loft.shell(Loft.new(spine, sections), 0.003, :plastic)
    assert Mesh.volume(m.points, m.faces) > 0
    assert length(World.Mesh.triangles(m, 0)) > 0
  end

  test "a section of no width has its normal out from the spine" do
    l = Loft.new([{0, 0, 0}, {0, 0, 0.1}, {0, 0, 0.2}], [{0.1, 0.1, 2}, {0.0, 0.1, 2}, {0.1, 0.1, 2}], up: {1, 0, 0})
    {rows, _} = Loft.rows(l)
    assert length(Enum.at(rows, 1)) == 24
    assert %Mesh{} = Loft.shell(l, 0.002, :plastic)
  end

  test "a loft has a section at each point of its spine" do
    assert_raise ArgumentError, fn -> Loft.new([{0, 0, 0}, {0, 0, 1}], [{1, 1, 2}]) end
  end

  test "the part of a shell: its area and its thickness in its params" do
    p = Loft.part(dome(0.1), "dome", :shell, [], 0.004, :paint, matter: :plastic, sources: ["a test"])
    assert p.params["thickness"] == 0.004 and p.params["area"] > 0.06
    assert hd(p.shapes).matter == :plastic
    assert hd(Loft.part(dome(0.1), "dome", :shell, [], 0.004, :plastic).shapes).matter == nil
  end

  test "a surface grows out along its normal" do
    {r, d} = {0.1, 0.02}
    l = Loft.grow(dome(r), d)
    assert_in_delta Loft.area(l), 2 * :math.pi() * (r + d) ** 2, 0.015 * 2 * :math.pi() * (r + d) ** 2
    # The apex moves up by d, and the rim out by d.
    {rows, _} = Loft.rows(l)
    {_, _, top} = rows |> List.last() |> hd()
    assert_in_delta top, r + d, 1.0e-6
    assert_in_delta World.Vec.len(hd(hd(rows))), r + d, 1.0e-3
  end

  describe "the half helmet of Việt Nam (QCVN 2:2021/BKHCN)" do
    test "each headform: its perimeter at the reference plane is its circumference within 2%, and its top is at Y" do
      for size <- Molds.sizes() do
        h = Molds.headform(size)
        {[row | _] = rows, _} = Loft.rows(h.loft)

        perimeter =
          (row ++ [hd(row)])
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> World.Vec.len(World.Vec.sub(b, a)) end)
          |> Enum.sum()

        assert_in_delta perimeter, h.circumference, 0.02 * h.circumference, "size #{size}"
        {_, _, top} = rows |> List.last() |> hd()
        assert_in_delta top, h.y, 1.0e-9
      end
    end

    test "a true model under the mass limit of its size; a bigger headform gives a bigger helmet" do
      masses =
        for size <- ~w(1 6 9) do
          g = Molds.half_helmet(size)
          assert g.kind == :helmet and World.Plan.trade(g) == :molder
          assert World.Check.model(g) == :ok
          %{mass: mass, unknown: []} = World.Mass.of(g)
          assert mass > 0.3 and mass <= Molds.mass_limit("half", size), "size #{size}: #{mass} kg"
          mass
        end

      assert masses == Enum.sort(masses)
      assert Molds.mass_limit("half", "1") == 0.8
    end

    test "the parts of Hình 2, each a part of its own" do
      g = Molds.half_helmet()

      assert Enum.map(g.nodes, &elem(&1, 0)) ==
               ~w(shell_helmet_half liner_helmet_half pad_helmet_half trim_helmet_half peak_helmet_half rivet_left_helmet_half rivet_right_helmet_half strap_left_helmet_half strap_right_helmet_half buckle_helmet_half)
    end

    test "it covers the headform over the line AA', the view up is 7 degrees or more, and a rivet is 2 mm or less" do
      g = Molds.half_helmet()
      [aa] = World.Standards.size({"helmet", "limits"}, "aa_line")
      [up] = World.Standards.size({"helmet", "vision"}, "up")
      [rivet] = World.Standards.size({"helmet", "limits"}, "rivet_head")

      # The rim of the liner and of the shell is under AA'.
      for {name, %World.Part{} = p, _} <- g.nodes, name in ~w(liner_helmet_half shell_helmet_half) do
        {{_, _, low}, _} = World.Part.bounds(p)
        assert low * 1000 < aa
      end

      assert Molds.vision_up(g, "6") >= up

      for {_, %World.Part{kind: :rivet} = p, _} <- g.nodes, do: assert(p.params["head"] * 1000 <= rivet)
    end
  end
end
