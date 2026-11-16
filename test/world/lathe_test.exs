defmodule World.LatheTest do
  use ExUnit.Case, async: true

  alias World.{Detail, Lathe, Mesh, Turned}

  doctest Lathe
  doctest Turned

  # The volume of the mesh of a turned part (m³).
  defp mesh_volume(assembly) do
    [{_, part, _}] = assembly.nodes
    [%Mesh{points: points, faces: faces}] = part.shapes
    Mesh.volume(points, faces) / 6
  end

  test "the volume of each turned part from its mesh is the volume of its profile (Pappus), within 1%" do
    for {name, fun} <- Turned.models() do
      a = fun.()
      v = mesh_volume(a)
      assert v > 0
      assert abs(v - a.extras["volume"]) / a.extras["volume"] < 0.01, "#{name}: #{v} #{a.extras["volume"]}"
    end
  end

  test "the sizes of the turned parts are the sizes of their sources" do
    size = fn fun ->
      e = fun.().extras
      {Float.round(e["diameter"] * 100, 1), Float.round(e["height"] * 100, 1)}
    end

    assert size.(&Turned.chen_tra/0) == {6.0, 4.0}
    assert size.(&Turned.bat_com/0) == {11.5, 6.0}
    assert size.(&Turned.bottle/0) == {6.1, 23.1}
    assert size.(&Turned.pot/0) == {20.3, 20.3}
    assert size.(&Turned.baluster/0) == {12.0, 60.0}
  end

  test "a vessel holds its capacity: the bottle about 355 ml, to the brim a little more" do
    ml = fn fun -> fun.().extras["capacity"] * 1000 end
    assert ml.(&Turned.bottle/0) > 355 and ml.(&Turned.bottle/0) < 390
    # A tea cup holds a few sips; a rice bowl a bowl of rice.
    assert ml.(&Turned.chen_tra/0) > 40 and ml.(&Turned.chen_tra/0) < 80
    assert ml.(&Turned.bat_com/0) > 250 and ml.(&Turned.bat_com/0) < 450
    # A solid post has no capacity.
    refute Map.has_key?(Turned.baluster().extras, "capacity")
  end

  test "far away a turned part has fewer sides and fewer points" do
    count = fn level ->
      Detail.with(level, fn -> Turned.bottle() end).nodes
      |> hd()
      |> elem(1)
      |> Map.fetch!(:shapes)
      |> hd()
      |> Map.fetch!(:points)
      |> length()
    end

    assert count.(:far) < count.(:mid) and count.(:mid) < count.(:near)
  end

  test "a turned part is of the family of the turnery, and stands on its foot" do
    a = Turned.pot()
    assert a.kind == :turned and World.Plan.trade(a) == :turner
    [{_, part, _}] = a.nodes
    assert part.ports["foot"].axis == {0.0, 0.0, -1.0}
  end
end
