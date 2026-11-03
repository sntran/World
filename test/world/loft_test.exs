defmodule World.LoftTest do
  use ExUnit.Case, async: true

  alias World.{Loft, Mesh, Molds}

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

  test "the half helmet of Việt Nam: a true model, under the mass limit of QCVN 2:2021" do
    g = Molds.half_helmet()
    assert g.kind == :helmet and World.Places.family_of(g) == :molds
    assert World.Check.model(g) == :ok

    %{mass: mass, unknown: unknown} = World.Mass.of(g)
    assert mass > 0.3 and mass <= Molds.mass_limit()
    assert unknown == []

    # Each part of the helmet is a part of its own: the shell, the peak,
    # the liner, the comfort pad, the two straps and the buckle.
    assert Enum.map(g.nodes, &elem(&1, 0)) ==
             ~w(shell_helmet_half peak_helmet_half liner_helmet_half pad_helmet_half strap_left_helmet_half strap_right_helmet_half buckle_helmet_half)

    # A bigger head gives a bigger helmet.
    assert World.Mass.of(Molds.half_helmet(0.62)).mass > mass
  end
end
