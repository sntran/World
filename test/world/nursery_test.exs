defmodule World.NurseryTest do
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Plants, Scene}

  test "each plant of the nursery: its height, its levels, its checks, the nursery makes it" do
    for {name, fun} <- Plants.models() do
      near = Detail.with(:near, fun)
      assert World.Check.model(near) == :ok, name
      assert World.Plan.trade(near) == :gardener
      tris = for l <- [:near, :mid, :far], do: Scene.triangles(Build.scene(Detail.with(l, fun), level: l))
      assert tris == Enum.sort(tris, :desc), "#{name}: #{inspect(tris)}"
      [_, _, h] = Build.scene(near, level: :near).extras["size"]
      assert h > 0.8 * near.extras["height"] and h < 1.6 * near.extras["height"], "#{name}: #{h}"
    end
  end

  test "the far level of a palm has less than 500 faces; a taller palm is taller" do
    far = Build.scene(Detail.with(:far, &Plants.coconut/0), level: :far)
    assert Scene.triangles(far) < 500
    [_, _, h] = Build.scene(Detail.with(:far, fn -> Plants.coconut(height: 22) end), level: :far).extras["size"]
    assert h > 22
  end

  test "the frangipani has no leaves in the dry season, and flowers from May to August" do
    names = fn month -> Enum.map(Plants.frangipani(month: month).nodes, &elem(&1, 0)) end
    refute "leaves_frangipani" in names.(2)
    assert "flowers_frangipani" in names.(6)
    refute "flowers_frangipani" in names.(10)
    assert "leaves_frangipani" in names.(10)
  end

  test "the species and their numbers come with their sources" do
    assert Plants.species() == ~w(bamboo banana coconut frangipani)
    assert Plants.number("coconut", "fronds") == 30
    assert Plants.bamboo(culms: 5).extras["culms"] == 5
    assert Plants.coconut(nuts: false).nodes |> Enum.map(&elem(&1, 0)) |> Enum.member?("nuts_coconut") == false
    assert Plants.banana(bunch: false).nodes |> length() == 2
  end
end
