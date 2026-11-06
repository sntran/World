defmodule World.TownLimitsTest do
  # The limits of a whole house for a town of Vũng Tàu (W22): each level
  # of each house is measured, and the test fails when one is over its
  # limit or has a material role that is not of a house.
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Scene}
  alias World.Buildings.Lot

  # The heaviest options: the most floors, the widest and deepest lot,
  # windows in both side walls, a room at the back and on the terrace.
  @heavy [floors: 8, width: 6.0, depth: 25.0, left: :free, right: :free, extension: true, terrace_room: true]

  defp measure(name, fun) do
    for level <- [:near, :mid, :far] do
      scene = Detail.with(level, fn -> Build.scene(fun.(), level: level) end)
      roles = for n <- scene.nodes, p <- n.primitives, uniq: true, do: p.material
      {name, level, Scene.triangles(scene), roles}
    end
  end

  defp check(rows) do
    for {name, level, tris, roles} <- rows do
      assert tris <= Lot.limits()[level], "#{name} at #{level}: #{tris} triangles, the limit is #{Lot.limits()[level]}"

      assert roles -- Lot.roles() == [],
             "#{name} at #{level}: the roles #{inspect(roles -- Lot.roles())} are not of a house"
    end
  end

  test "the limits of a house: near 40,000, mid 3,000, far 300 triangles" do
    assert Lot.limits() == %{near: 40_000, mid: 3_000, far: 300}
    assert length(Lot.roles()) == 12
  end

  test "each house of the catalog is in the limits at each level" do
    rows = Enum.flat_map(Lot.models(), fn {name, fun} -> measure(name, fun) end)
    assert length(rows) == 9
    check(rows)
  end

  @tag timeout: 600_000
  test "the heaviest house of each style, roof and ground floor is in the limits at each level" do
    c = Lot.choices()

    rows =
      for style <- c.style, roof <- c.roof, ground <- c.ground do
        opts = @heavy ++ [style: style, roof: roof, ground: ground, seed: 2]
        measure(inspect(opts), fn -> Lot.house(opts) end)
      end

    check(List.flatten(rows))
    # The far level keeps the roof: it is seen from Núi Lớn and Núi Nhỏ.
    for {_, :far, _, roles} <- List.flatten(rows),
        do: assert(Enum.any?(roles, &(&1 in [:roof_clay, :roof_corrugated, :concrete])))
  end
end
