defmodule World.LaminateTest do
  use ExUnit.Case, async: true

  alias World.Materials.Laminate

  doctest Laminate

  test "a ply of mat of 450 g/m2 is about 1 mm (TAP Plastics: 1.04 mm); a ply of roving has more glass" do
    mat = Laminate.new(["csm_450"], gel: false)
    assert_in_delta Laminate.thickness(mat) * 1000, 1.04, 0.05
    assert_in_delta Laminate.areal(mat), 1.5, 1.0e-9
    roving = Laminate.new(["wr_600"], gel: false)
    assert Laminate.density(roving) > Laminate.density(mat)
    assert_raise ArgumentError, fn -> Laminate.new(["felt"]) end

    # The gel coat: 0.5 mm of 1.22 g/cm3.
    gel = Laminate.new(["csm_450"])
    assert_in_delta Laminate.thickness(gel) - Laminate.thickness(mat), 0.0005, 1.0e-12
    assert_in_delta Laminate.areal(gel) - Laminate.areal(mat), 0.61, 1.0e-9
  end

  test "the shell chair: a shell of the laminate on four legs, of its mass, it stands, the mold shop makes it" do
    c = World.Molds.shell_chair()
    assert World.Check.model(c) == :ok
    assert World.Places.family_of(c) == :molds
    %{mass: mass, unknown: []} = World.Mass.of(c)
    assert mass > 3 and mass < 5
    {_, shell, _} = List.keyfind(c.nodes, "shell_chair_frp", 0)
    assert_in_delta shell.params["thickness"], 0.00365, 1.0e-5
    {{_, _, z0}, {_, _, z1}} = World.Part.bounds(shell)
    assert z0 > 0.3 and z1 > 0.79 and z1 < 0.81
    assert World.Molds.shell_chair(plies: ["csm_450", "csm_450"]).extras["thickness"] < c.extras["thickness"]
  end
end
