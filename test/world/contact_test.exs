defmodule World.ContactTest do
  use ExUnit.Case, async: true
  doctest World.Contact

  alias World.{Contact, Detail, Figure, Frame, Shape}

  test "a point in a closed mesh at its place: the ray goes through the faces an odd count of times" do
    box = Shape.box({0, 0, 0}, {1, 1, 1}, :wood)
    tris = elem(Contact.solid(box), 2)
    assert Contact.inside?({0.5, 0.5, 0.5}, tris)
    refute Contact.inside?({1.5, 0.5, 0.5}, tris)

    # The frame moves the solid: the box is now from x = 2 to x = 3.
    moved = Contact.solid(box, Frame.move({2.0, 0.0, 0.0}))
    assert Contact.blocked?({2.5, 0.5, 0.5}, [moved])
    refute Contact.blocked?({0.5, 0.5, 0.5}, [moved])
    # Out of the box of the solid: no test of the triangles.
    refute Contact.blocked?({2.5, 0.5, 5.0}, [moved])
  end

  test "the reach of a move: 0 at a touch at the start, 1 with no touch, and a thin wall stops the move" do
    wall = fn {x, _, _} -> x > 1.0 end
    assert Contact.reach(fn _ -> [{2.0, 0.0, 0.0}] end, [wall]) == 0.0
    assert Contact.reach(fn t -> [{t, 0.0, 0.0}] end, [wall]) == 1.0

    # A slab from x = 0.5 to 0.62: the move from 0 to 1.6 goes through it,
    # and the end of the move is free again.
    slab = fn {x, _, _} -> x > 0.5 and x < 0.62 end
    t = Contact.reach(fn t -> [{1.6 * t, 0.0, 0.0}] end, [slab])
    assert_in_delta t, 0.5 / 1.6, 0.001
  end

  test "a person leans back to a wall behind the back, and stops at the touch" do
    f = Detail.with(:far, fn -> World.People.Human.person("p", pose: World.People.Pose.resolve("sit")) end)
    points = Contact.points(f)
    assert length(points) > 500
    assert Contact.lean(f, %{}, []) == {f, 1.0}

    # A wall 5 cm behind the back (the front of the person is +y).
    back = points |> Enum.map(&elem(&1, 1)) |> Enum.min()
    wall = fn {_, y, _} -> y < back - 0.05 end
    {g, t} = Contact.lean(f, %{"spine.flex" => -40}, [wall])
    assert t > 0.0 and t < 1.0
    refute Enum.any?(Contact.points(g), &wall.(&1))
    # The full lean goes through the wall; with no wall the person leans to
    # the end.
    assert Enum.any?(Contact.points(Figure.pose(f, %{"spine.flex" => -40}, %{})), &wall.(&1))
    assert {_, 1.0} = Contact.lean(f, %{"spine.flex" => -40}, [])

    # The place of the figure moves the points: the wall 1 m ahead of the
    # figure is then behind its back.
    {_, t2} =
      Contact.lean(f, %{"spine.flex" => -40}, [fn {_, y, _} -> y < back - 0.05 - 1.0 end], Frame.move({0.0, -1.0, 0.0}))

    assert_in_delta t2, t, 1.0e-9
  end
end
