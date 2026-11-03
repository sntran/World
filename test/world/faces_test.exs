defmodule World.FacesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Assembly, Build, Detail, Faces, Frame, Mesh, Part, Port, Shape, Vec}

  # A cabinet of 1 by 0.5 by 0.8 m, a door on a hinge at its front left
  # edge, a knob of 1 cm on the door, and a mark with no mesh.
  defp cabinet do
    body =
      Part.new("cabinet", :cabinet, Shape.box({-0.5, -0.25, 0}, {0.5, 0.25, 0.8}, :white), [
        Part.port("hinge", {-0.5, 0.25, 0.0}, {0, 0, 1}, {0, 1, 0})
      ])

    door =
      Part.new("door", :door, Shape.box({0, 0, 0}, {1, 0.02, 0.8}, :stainless), [
        Part.port("pin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
        Part.port("knob", {0.9, 0.02, 0.4}, {0, 1, 0}, {0, 0, 1})
      ])

    knob =
      Part.new("knob", :knob, Shape.box({-0.005, -0.005, 0}, {0.005, 0.005, 0.01}, :black), [
        Part.port("base", {0, 0, 0}, {0, 0, -1}, {0, 1, 0})
      ])

    mark = Part.new("mark", :mark, [], [Part.port("base", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})])

    Assembly.new("cabinet", body, kind: :item, sources: ["A test."])
    |> Assembly.add("door", door, at: "hinge", port: "pin", kind: :hinge, role: :door, limits: [0, 120])
    |> Assembly.add("knob", knob, to: "door", at: "knob", port: "base")
    |> Assembly.add("mark", mark, at: Port.new("m", {0, 0, 0.8}, {0, 0, 1}, {0, 1, 0}), port: "base")
  end

  defp shapes(map), do: Enum.flat_map(map["parts"], & &1["shapes"])

  test "a mesh has its faces as polygons, not cut into triangles, with the normal of each" do
    faces = Mesh.faces(Shape.box({0, 0, 0}, {1, 2, 3}, :paint))
    assert length(faces) == 6
    assert Enum.all?(faces, fn {points, _} -> length(points) == 4 end)

    # -0.0 + 0.0 is 0.0: the sign of a zero does not count.
    clean = fn {x, y, z} -> {x + 0.0, y + 0.0, z + 0.0} end
    normals = faces |> Enum.map(&clean.(elem(&1, 1))) |> MapSet.new()

    sides =
      for {x, y, z} <- [{1, 0, 0}, {0, 1, 0}, {0, 0, 1}],
          s <- [1.0, -1.0],
          into: MapSet.new(),
          do: clean.({x * s, y * s, z * s})

    assert normals == sides

    # A smooth mesh has more faces, each a quad of the core of Wings.
    smooth = Mesh.faces(Shape.box({0, 0, 0}, {1, 1, 1}, :paint), 1)
    assert length(smooth) == 24
    assert Enum.all?(smooth, fn {points, _} -> length(points) == 4 end)

    # A plate has a face on each side.
    plate = Mesh.new([{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}], [[0, 1, 2, 3], [3, 2, 1, 0]], :paint)

    assert plate |> Mesh.faces() |> Enum.map(&clean.(elem(&1, 1))) |> Enum.sort() == [
             {0.0, 0.0, -1.0},
             {0.0, 0.0, 1.0}
           ]
  end

  property "the faces of a box cover its surface, and each normal looks out" do
    check all(
            w <- float(min: 0.01, max: 3.0),
            d <- float(min: 0.01, max: 3.0),
            h <- float(min: 0.01, max: 3.0)
          ) do
      faces = Mesh.faces(Shape.box({0, 0, 0}, {w, d, h}, :paint))
      center = {w / 2, d / 2, h / 2}

      area =
        for {[a | rest], n} <- faces, [b, c] <- Enum.chunk_every(rest, 2, 1, :discard), reduce: 0.0 do
          sum ->
            assert Vec.dot(Vec.sub(a, center), n) > 0
            assert_in_delta Vec.len(n), 1.0, 1.0e-9
            sum + Vec.len(Vec.cross(Vec.sub(b, a), Vec.sub(c, a))) / 2
        end

      assert_in_delta area, 2 * (w * d + d * h + w * h), 1.0e-6 * (1 + w * d + d * h + w * h)
    end
  end

  test "the pieces of a model: each part a level keeps, at its place in a pose, with its node" do
    near = Build.pieces(cabinet())

    assert Enum.map(near, fn {_, p, path, node} -> {p.name, path, node} end) == [
             {"cabinet", "body", "cabinet"},
             {"mark", "mark", "cabinet"},
             {"door", "door", "door"},
             {"knob", "knob", "door"}
           ]

    # The knob of 1 cm is not at mid. Each frame is the frame of the GLB.
    mid = Build.pieces(Detail.with(:mid, &cabinet/0), level: :mid)
    assert Enum.map(mid, &elem(&1, 2)) == ~w(body mark door)
    scene = Build.scene(cabinet(), pose: %{"door" => 90})
    frames = World.Scene.world_frames(scene)
    {door_frame, _, _, "door"} = Enum.at(Build.pieces(cabinet(), pose: %{"door" => 90}), 2)
    assert Frame.point(door_frame, {0, 0, 0}) == Frame.point(frames[1], {0, 0, 0})

    # Build.placed/1 has the same parts at near.
    assert Enum.map(Build.placed(cabinet()), &elem(&1, 1).name) == Enum.map(near, &elem(&1, 1).name)
  end

  test "the faces of a model: its parts, the shapes of each with a box, and the colors of the roles" do
    map = Faces.build(cabinet())
    assert map["name"] == "cabinet"
    assert map["level"] == "near"
    assert map["size"] == [1.0, 0.52, 0.8]

    # The mark has no mesh: it is not a part of the faces.
    assert Enum.map(map["parts"], &{&1["path"], &1["node"]}) == [
             {"body", "cabinet"},
             {"door", "door"},
             {"knob", "door"}
           ]

    [body | _] = map["parts"]
    assert body["box"] == [[-0.5, -0.25, 0.0], [0.5, 0.25, 0.8]]

    assert [%{"role" => "white", "points" => points, "faces" => faces, "normals" => normals} = shape] =
             body["shapes"]

    assert shape["box"] == [[-0.5, -0.25, 0.0], [0.5, 0.25, 0.8]]

    assert length(points) == 8
    assert length(faces) == 6 and length(normals) == 6
    # No -0.0 in the file.
    refute Faces.encode(cabinet()) =~ "-0.0"
    assert Enum.all?(faces, fn f -> length(f) == 4 and Enum.all?(f, &(&1 in 0..7)) end)

    # The colors of the roles, from the palette.
    palette = World.GLB.palette()
    assert map["colors"]["white"] == %{"color" => palette["white"]["color"], "alpha" => 1.0}
    assert Map.keys(map["colors"]) == ~w(black stainless white)

    # The JSON is the same map.
    assert JSON.decode!(Faces.encode(cabinet())) == map
  end

  test "the faces in a pose and in the colors of an order, at a level" do
    open = Faces.build(cabinet(), pose: %{"door" => 90})
    [_, door, _] = open["parts"]
    # The door turns on its hinge at the front left edge: it goes to the front.
    assert [[x0, y0, _], [x1, y1, _]] = door["box"]
    assert_in_delta x0, -0.52, 1.0e-3
    assert_in_delta x1, -0.5, 1.0e-3
    assert_in_delta y0, 0.25, 1.0e-3
    assert_in_delta y1, 1.25, 1.0e-3

    red = Faces.build(cabinet(), materials: %{stainless: %{color: [200, 0, 0], roughness: 0.3, metalness: 1.0}})
    assert red["colors"]["stainless"] == %{"color" => [200, 0, 0], "alpha" => 1.0}

    mid = Faces.build(Detail.with(:mid, &cabinet/0), level: :mid)
    assert mid["level"] == "mid"
    assert Enum.map(mid["parts"], & &1["path"]) == ~w(body door)
    assert "black" not in Map.keys(mid["colors"])
  end

  test "the faces of an order have its pose and its colors" do
    order = %{
      "blueprint" => "catalog",
      "options" => %{"name" => "washer_lg_wm4000hwa"},
      "colors" => %{"white" => "#ff0000"},
      "joints" => %{"door" => 90}
    }

    {:ok, json} = World.Orders.build(order, "far", "faces")
    map = JSON.decode!(json)
    assert map["level"] == "far"
    assert map["colors"]["white"]["color"] == [255, 0, 0]

    {:ok, shut} = World.Orders.build(Map.delete(order, "joints"), "far", "faces")
    door = fn map -> Enum.find(map["parts"], &(&1["node"] == "door"))["box"] end
    assert door.(map) != door.(JSON.decode!(shut))
  end

  test "a model with no mesh has no parts, and the size 0" do
    mark = Part.new("mark", :mark, [], [])
    map = Faces.build(mark)
    assert {map["parts"], map["size"], map["colors"]} == {[], [0.0, 0.0, 0.0], %{}}
  end

  test "glass has its alpha, and a model of the catalog has its faces" do
    {:ok, fun} = World.Catalog.fetch("washer_lg_wm4000hwa")
    map = Faces.build(Detail.with(:far, fun), level: :far)
    assert map["colors"]["glass_dark"]["alpha"] < 1.0
    assert Enum.map(map["parts"], & &1["node"]) |> Enum.uniq() == ["washer_lg_wm4000hwa", "door"]

    for s <- shapes(map), [[x0, y0, z0], [x1, y1, z1]] = s["box"], [x, y, z] <- s["points"] do
      assert x >= x0 and x <= x1 and y >= y0 and y <= y1 and z >= z0 and z <= z1
    end
  end
end
