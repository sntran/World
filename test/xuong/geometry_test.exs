defmodule Xuong.GeometryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Xuong.{Frame, Vec}

  defp close?(a, b, eps \\ 1.0e-9), do: Vec.len(Vec.sub(a, b)) < eps

  defp vec, do: tuple({float(min: -10.0, max: 10.0), float(min: -10.0, max: 10.0), float(min: -10.0, max: 10.0)})

  describe "Vec" do
    test "the basic operations" do
      assert Vec.add({1, 2, 3}, {1, 1, 1}) == {2, 3, 4}
      assert Vec.sub({1, 2, 3}, {1, 1, 1}) == {0, 1, 2}
      assert Vec.cross({1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}) == {0.0, 0.0, 1.0}
      assert Vec.dot({1, 2, 3}, {4, 5, 6}) == 32
      assert Vec.neg({1, -2, 3}) == {-1, 2, -3}
      assert Vec.lerp({0.0, 0.0, 0.0}, {2.0, 4.0, 6.0}, 0.5) == {1.0, 2.0, 3.0}
      assert Vec.float({1, 2, 3}) == {1.0, 2.0, 3.0}
      assert Vec.mean([{0.0, 0.0, 0.0}, {2.0, 2.0, 2.0}]) == {1.0, 1.0, 1.0}
      assert Vec.bounds([{1, 5, 2}, {-1, 0, 3}]) == {{-1, 0, 2}, {1, 5, 3}}
    end

    test "norm gives a unit vector, and +z for a vector of length 0" do
      assert Vec.norm({0.0, 0.0, 0.0}) == {0.0, 0.0, 1.0}
      assert close?(Vec.norm({3.0, 0.0, 4.0}), {0.6, 0.0, 0.8})
    end

    property "perpendicular gives a unit vector at a right angle" do
      check all v <- vec(), Vec.len(v) > 0.01 do
        p = Vec.perpendicular(v)
        assert abs(Vec.len(p) - 1) < 1.0e-9
        assert abs(Vec.dot(p, Vec.norm(v))) < 1.0e-9
      end
    end
  end

  describe "Frame" do
    property "invert undoes a frame" do
      check all at <- vec(), axis <- vec(), deg <- float(min: -360.0, max: 360.0), Vec.len(axis) > 0.01 do
        f = Frame.compose(Frame.move(at), Frame.turn(axis, deg))
        p = {0.3, -1.2, 2.5}
        assert close?(Frame.point(Frame.invert(f), Frame.point(f, p)), p, 1.0e-7)
      end
    end

    property "new gives a frame with its z on the axis and the right hand" do
      check all axis <- vec(), Vec.len(axis) > 0.01 do
        up = Vec.perpendicular(axis)
        f = Frame.new({1, 2, 3}, axis, up)
        assert close?(f.z, Vec.norm(axis), 1.0e-9)
        assert close?(Vec.cross(f.x, f.y), f.z, 1.0e-9)
        assert close?(f.y, up, 1.0e-9)
      end
    end

    test "a turn around a point keeps the point" do
      f = Frame.turn({0.0, 0.0, 1.0}, 90.0, {1.0, 0.0, 0.0})
      assert close?(Frame.point(f, {1.0, 0.0, 0.0}), {1.0, 0.0, 0.0})
      assert close?(Frame.point(f, {2.0, 0.0, 0.0}), {1.0, 1.0, 0.0})
    end

    property "the quaternion turns as the frame" do
      check all axis <- vec(), deg <- float(min: -179.0, max: 179.0), Vec.len(axis) > 0.01 do
        {x, y, z, w} = Frame.quaternion(Frame.turn(axis, deg))
        assert abs(x * x + y * y + z * z + w * w - 1) < 1.0e-9
        half = deg / 2 * :math.pi() / 180
        assert abs(abs(w) - abs(:math.cos(half))) < 1.0e-6
      end
    end

    test "the quaternion of each case of the trace" do
      for {axis, deg} <- [{{1, 0, 0}, 180}, {{0, 1, 0}, 180}, {{0, 0, 1}, 180}, {{0, 0, 1}, 0}] do
        {x, y, z, w} = Frame.quaternion(Frame.turn(axis, deg))
        assert abs(x * x + y * y + z * z + w * w - 1) < 1.0e-9
      end
    end

    test "the matrix has the columns of the frame" do
      assert Frame.matrix(Frame.move({1.0, 2.0, 3.0})) ==
               [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 2.0, 3.0, 1.0]

      assert Frame.identity() == %Frame{}
    end
  end
end
