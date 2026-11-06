defmodule World.CheckTest do
  use ExUnit.Case, async: true

  alias World.{Assembly, Check, Mesh, Openings, Part, Shape}
  alias World.Materials.Fasteners

  doctest Check
  doctest Mesh, only: [skin: 3, matter: 2]

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # A model of a root with no shapes and its children, each on a port of
  # its own of the root (so no two children are on one port).
  defp model(children, opts \\ []) do
    ports = for {name, _} <- children, do: Part.port(name, {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
    root = Part.new("root", :mark, [], [@o | ports])

    Enum.reduce(children, Assembly.new("model", root, Keyword.merge([root: "root"], opts)), fn {name, part}, a ->
      Assembly.add(a, name, part, at: name, port: "o")
    end)
  end

  defp part(name, shapes, kind \\ :part), do: Part.new(name, kind, List.wrap(shapes), [@o])

  describe "stands/1" do
    test "a model with its mass over its base stands; one with its mass out of the base tips" do
      base = Shape.box({0.0, 0.0, 0.0}, {0.1, 0.1, 0.01}, :steel)

      assert Check.stands(
               model([
                 {"a", part("a", base)},
                 {"b", part("b", Shape.box({0.02, 0.02, 0.01}, {0.08, 0.08, 0.3}, :steel))}
               ])
             ) == :ok

      heavy = Shape.box({0.3, 0.0, 0.01}, {0.5, 0.1, 0.2}, :steel)

      assert {:error, {:tips, {x, _}, {{0.0, 0.0}, {0.1, 0.1}}}} =
               Check.stands(model([{"a", part("a", base)}, {"b", part("b", heavy)}]))

      assert x > 0.1
    end

    test "with a part of no mass, the center of the volume of the closed meshes" do
      base = Shape.box({0.0, 0.0, 0.0}, {0.1, 0.1, 0.01}, :paint)
      heavy = Shape.box({0.3, 0.0, 0.01}, {0.5, 0.1, 0.2}, :paint)
      assert {:error, {:tips, _, _}} = Check.stands(model([{"a", part("a", base)}, {"b", part("b", heavy)}]))
    end

    test "with no closed mesh, the mean of the points; with no points, it stands" do
      flat = %Mesh{points: [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}], faces: [[0, 1, 2]], material: :paint}
      assert Check.stands(part("flat", flat)) == :ok
      assert Check.stands(part("mark", [])) == :ok
    end

    test "a base of one point holds only a mass over it" do
      cone = Shape.lathe([{0.0, 0.0}, {0.1, 0.2}, {0.0, 0.2}], :steel)
      assert Check.stands(part("cone", cone)) == :ok
      side = Shape.box({0.2, -0.01, 0.15}, {0.4, 0.01, 0.2}, :steel)
      assert {:error, {:tips, _, _}} = Check.stands(model([{"cone", part("cone", cone)}, {"arm", part("arm", side)}]))
    end
  end

  describe "stands/1 with a stand" do
    # Two thin wheels in line on the y axis, a body over them, and a stand
    # at the left on a hinge, as the side stand of a motorcycle: the stand
    # is along the frame at 0 and goes down to 80 degrees.
    defp bike(body_x, leg) do
      pivot = {-0.1, 0.0, 0.3}
      stand_port = Part.port("stand", pivot, {1, 0, 0}, {0, 0, 1})
      wheels = for y <- [-0.5, 0.5], do: Shape.box({-0.001, y - 0.15, 0.0}, {0.001, y + 0.15, 0.3}, :steel)
      body = Shape.box({body_x - 0.05, -0.5, 0.3}, {body_x + 0.05, 0.5, 0.5}, :steel)
      frame = Part.new("frame", :frame, [body | wheels], [@o, stand_port])
      foot = Shape.box({-0.105, -leg, 0.295}, {-0.095, 0.0, 0.305}, :steel)
      stand = Part.new("stand", :stand, [foot], [Part.port("pivot", pivot, {1, 0, 0}, {0, 0, 1})])

      Assembly.new("bike", frame, root: "frame")
      |> Assembly.add("side_stand", stand, at: "stand", port: "pivot", kind: :hinge, role: :stand, limits: [0, 80])
    end

    test "a long stand stops where it touches the ground, and holds the model" do
      # At 80 degrees the foot is under the wheels: the stand stops at
      # the angle where it first touches.
      assert Check.stands(bike(-0.005, 0.32)) == :ok
    end

    test "a short stand: the model leans to it until it touches" do
      assert Check.stands(bike(0.005, 0.29)) == :ok
      # With no stand the same model tips off its line.
      {_, frame, _} = hd(bike(0.005, 0.29).nodes)
      assert {:error, {:tips, _, _}} = Check.stands(frame)
    end
  end

  describe "overlaps/1" do
    test "two parts in one place, and not joined, are an overlap" do
      a = part("a", Shape.box({0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}, :steel))
      b = part("b", Shape.box({0.1, 0.1, 0.1}, {0.9, 0.9, 0.9}, :steel))
      assert Check.overlaps(model([{"a", a}, {"b", b}])) == {:error, {:overlap, [{"a", "b"}]}}

      # Two parts of one name (two bricks) in one place.
      assert Check.overlaps(model([{"a", a}, {"a2", a}])) == {:error, {:overlap, [{"a", "a"}]}}
    end

    test "parts that a connection joins, on one port, and fasteners are not checked" do
      a = part("a", Shape.box({0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}, :steel))
      b = part("b", Shape.box({0.1, 0.1, 0.1}, {0.9, 0.9, 0.9}, :steel))

      # b is a child of a.
      joined = Assembly.new("joined", a, root: "a") |> Assembly.add("b", b, at: "o", port: "o")
      assert Check.overlaps(joined) == :ok

      # a and b on one port of the root.
      root = Part.new("root", :mark, [], [@o])

      same =
        Assembly.new("same", root, root: "root")
        |> Assembly.add("a", a, at: "o", port: "o")
        |> Assembly.add("b", b, at: "o", port: "o")

      assert Check.overlaps(same) == :ok

      bolt = %{Fasteners.bolt("M8", 0.04) | ports: %{"o" => @o}}
      assert Check.overlaps(model([{"a", a}, {"bolt", bolt}])) == :ok
    end

    test "a ring around a hub is not in one place with it; two rings in one place are" do
      ring = part("tire", Shape.lathe([{0.2, -0.05}, {0.3, -0.05}, {0.3, 0.05}, {0.2, 0.05}], :rubber, kind: :ring))

      hub =
        part("hub", Shape.cylinder(0.19, 0.1, :steel, frame: World.Frame.new({0.0, 0.0, -0.05}, {0, 0, 1}, {0, 1, 0})))

      assert Check.overlaps(model([{"tire", ring}, {"hub", hub}])) == :ok
      assert {:error, {:overlap, [{"tire", "tire"}]}} = Check.overlaps(model([{"tire", ring}, {"tire2", ring}]))
    end

    test "a skin and an open mesh have no inside" do
      solid = part("solid", Shape.box({0.1, 0.1, 0.1}, {0.9, 0.9, 0.9}, :steel))
      skin = part("skin", Mesh.skin(Shape.box({0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}, :paint), 0.001, :steel))

      # A box with no top: an open mesh around the solid.
      box = Shape.box({0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}, :steel)
      open = part("open", %{box | faces: Enum.drop(box.faces, -1)})

      assert Check.overlaps(model([{"solid", solid}, {"skin", skin}, {"open", open}])) == :ok
    end
  end

  describe "joints/2" do
    test "a value out of the limits of a joint; a name of no joint is not checked here" do
      door = Openings.prehung_sample()
      slab = "slab_door_prehung_36x80"
      assert Check.joints(door, %{slab => 50}) == :ok
      assert Check.joints(door, %{slab => 120}) == {:error, {:joints, [slab]}}
      assert Check.joints(door, %{"no_such_joint" => 120}) == :ok
      assert Check.joints(part("a", []), %{slab => 120}) == :ok
    end
  end

  describe "fits/2 and the door of model/2" do
    test "a model too big for the door of its workshop" do
      big = part("big", Shape.box({0.0, 0.0, 0.0}, {3.0, 3.0, 3.0}, :steel))
      assert {:error, [{:door, {3.0, 3.0, 3.0}, {w, h}}]} = Check.model(big)
      assert {w, h} == Check.door()
      assert Check.fits(part("small", Shape.box({0.0, 0.0, 0.0}, {0.5, 0.5, 3.0}, :steel)), Check.door()) == :ok
      assert Check.fits(part("mark", []), Check.door()) == :ok
    end

    test "a vehicle goes through the drive-in door; a house and a wall go through no door" do
      van = model([{"body", part("body", Shape.box({-1.2, -3.0, 0.0}, {1.2, 3.0, 2.8}, :steel))}], kind: :vehicle)
      assert Check.model(van) == :ok
      assert {:error, _} = Check.fits(van, Check.door())
      assert {_, _} = Check.drive_in()

      for kind <- [:house, :wall] do
        assert Check.model(
                 model([{"slab", part("slab", Shape.box({-4.0, -4.0, 0.0}, {4.0, 4.0, 0.1}, :concrete))}], kind: kind)
               ) == :ok
      end
    end

    test "a thing put together on its site goes through the door in its parts" do
      assert Check.model(Openings.overhead("door", 9 * 12 * 0.0254, 8 * 12 * 0.0254, 0.1)) == :ok

      long = part("beam", Shape.box({0.0, 0.0, 0.0}, {3.0, 3.0, 3.0}, :steel))
      assert {:error, [{:door, _, _}]} = Check.model(model([{"beam", long}], extras: %{"site" => true}))
    end
  end

  describe "model/2" do
    test "a door, a window and a material do not stand on their own" do
      tip =
        part(
          "tile",
          [Shape.box({0.0, 0.0, 0.0}, {0.1, 0.1, 0.01}, :steel), Shape.box({0.3, 0.0, 0.01}, {0.5, 0.1, 0.2}, :steel)],
          :material
        )

      assert Check.model(tip) == :ok
      assert {:error, [{:tips, _, _}]} = Check.model(%{tip | kind: :part})
    end

    test "the text of each reason" do
      assert Check.message({:tips, {0.1, -0.02}, {{0.0, 0.0}, {0.05, 0.05}}}) =~ "(100, -20 mm) is not over its base"
      assert Check.message({:overlap, [{"a", "b"}, {"c", "d"}]}) == "parts are in one place: a and b, c and d"

      assert Check.message({:door, {3.0, 1.0, 0.5}, {2.7432, 2.4384}}) =~
               "(2743 by 2438 mm): it is 3000 by 1000 by 500 mm"
    end

    test "an order with a model that is not true is refused, with the reason" do
      order = %{
        "blueprint" => "catalog",
        "options" => %{"name" => "door_prehung_36x80"},
        "joints" => %{"slab_door_prehung_36x80" => 200}
      }

      assert World.Orders.place(order, "https://world.example") ==
               {:error, [%{"path" => "model", "message" => "a joint is out of its limits: slab_door_prehung_36x80"}]}
    end
  end

  describe "the catalog" do
    for {name, _} <- World.Catalog.models(), name not in ~w(man woman traveler honda_vision_110_rider) do
      @name name
      # The statue casts its head and its hands on a grid of 3 cm.
      @tag timeout: 600_000
      test "#{name} is a true model" do
        {:ok, fun} = World.Catalog.fetch(@name)
        item = fun.()
        if is_struct(item, Assembly) or is_struct(item, Part), do: assert(Check.model(item) == :ok)
      end
    end
  end
end
