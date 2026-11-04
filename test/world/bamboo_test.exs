defmodule World.BambooTest do
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Mass, Mesh, Scene}
  alias World.Furniture.Bamboo
  alias World.Furniture.Bamboo.{Culm, Panel}

  doctest Culm

  test "a piece of a culm: hollow, its rings at its nodes, an end closed at a node" do
    open = Culm.piece({0, 0, 0}, {0, 0, 0.5}, d: 0.04, wall: 0.008)
    closed = Culm.piece({0, 0, 0}, {0, 0, 0.5}, d: 0.04, wall: 0.008, ends: {:node, :node})
    volume = fn m -> Mesh.volume(m.points, m.faces) / 6 end
    # A closed end adds a disc of the wall at each end.
    assert_in_delta volume.(closed) - volume.(open), 2 * :math.pi() * 0.012 ** 2 * 0.008, 2.0e-5

    # The rings of the nodes stand out of the culm; at far there are none.
    radius = fn m -> m.points |> Enum.map(fn {x, y, _} -> :math.sqrt(x * x + y * y) end) |> Enum.max() end
    assert radius.(open) > 0.0214
    assert radius.(Detail.with(:far, fn -> Culm.piece({0, 0, 0}, {0, 0, 0.5}, d: 0.04) end)) < 0.02001

    # A piece along x has its axis along x.
    {{x0, _, _}, {x1, _, _}} = World.Vec.bounds(Culm.piece({0, 0, 0}, {0.3, 0, 0}).points)
    assert_in_delta x1 - x0, 0.3, 1.0e-9
  end

  test "a panel of slats with its lashing, and the lashing goes at far" do
    rect = {{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}}
    meshes = Panel.slats(rect, 0.4, 0.3, lash: [0.3, 0.7])
    {cords, slats} = Enum.split_with(meshes, &(&1.matter == :nylon))
    # 16 mm slats with a gap of 3 mm in 300 mm: 15 slats; two rows of two cords.
    assert length(slats) == 15 and length(cords) == 4
    assert Detail.with(:far, fn -> Panel.slats(rect, 0.4, 0.3, lash: [0.5]) end) |> length() == 15
  end

  test "the models of the bamboo shop: true models, with a mass for each part, in their families" do
    for {name, fun} <- Bamboo.models() do
      item = fun.()
      assert World.Check.model(item) == :ok, name
      assert %{unknown: [], mass: mass} = Mass.of(item)
      assert mass > 1.0 and mass < 15.0, "#{name}: #{mass} kg"
      assert World.Places.family_of(item) == :bamboo

      for level <- [:near, :mid, :far] do
        tris = Scene.triangles(Build.scene(Detail.with(level, fun), level: level))
        assert tris < %{near: 30_000, mid: 15_000, far: 5_000}[level], "#{name} at #{level}: #{tris}"
      end
    end
  end

  test "the sizes: a seat at 0.42 to 0.45 m, a bench of 1.5 m, a low table" do
    size = fn item -> Build.scene(item).extras["size"] end
    [w, _, h] = size.(Bamboo.chair())
    assert_in_delta w, 0.45, 0.02
    assert_in_delta h, 0.9, 0.01
    assert hd(size.(Bamboo.armchair(width: 1.5, panels: 3))) > 1.5
    assert List.last(size.(Bamboo.table())) <= 0.46

    # The seat of a chair is at the height of a chair.
    seat = Enum.find(Bamboo.chair().nodes, fn {name, _, _} -> name == "seat_ghe_tre" end) |> elem(1)
    {_, {_, _, top}} = World.Part.bounds(seat)
    assert top > 0.42 and top < 0.46
  end

  test "the folding chair stands on its four feet, and folds flat" do
    chair = Bamboo.folding()

    points = fn pose ->
      for {f, p} <- Build.placed(chair, pose), m <- p.shapes, do: Enum.map(m.points, &World.Frame.point(f, &1))
    end

    low = points.(%{}) |> List.flatten() |> Enum.map(&elem(&1, 2)) |> Enum.min()
    assert abs(low) < 0.001

    # Each of the four legs has a point on the ground.
    legs = for {_, p} <- Build.placed(chair), p.kind in [:frame, :panel], m <- Enum.take(p.shapes, 2), do: m
    assert Enum.count(legs, fn m -> Enum.any?(m.points, fn {_, _, z} -> z < 1.0e-3 end) end) == 4

    # Two hinges and the clip that folds them: at its middle, the rear
    # legs and the seat lie along the posts, and the chair is flat.
    hinges = for {name, _, %{kind: :hinge, role: :fold, limits: limits}} <- chair.nodes, do: {name, limits}
    assert [{"rear_legs_ghe_tre_xep", [0, legs]}, {"seat_ghe_tre_xep", [seat, 0]}] = hinges
    assert legs > 60 and seat < -60
    [%{name: "fold", keys: [_, {1.5, folded}, {3.0, open}]}] = chair.clips
    assert folded == %{"rear_legs_ghe_tre_xep" => legs, "seat_ghe_tre_xep" => seat}
    assert Enum.all?(open, fn {_, v} -> v == 0.0 end)

    n = World.Vec.norm(World.Vec.cross({0.0, -0.32, 0.88}, {1.0, 0.0, 0.0}))

    depth = fn pose ->
      pose
      |> points.()
      |> List.flatten()
      |> Enum.map(&World.Vec.dot(&1, n))
      |> Enum.min_max()
      |> then(fn {a, b} -> b - a end)
    end

    assert depth.(%{}) > 0.5 and depth.(folded) < 0.08
    assert World.Check.model(chair, folded) == :ok
    assert Bamboo.folding(back: :bars).name == "ghe_tre_xep"
  end
end
