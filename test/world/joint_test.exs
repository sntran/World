defmodule World.JointTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.Joint

  test "a hinge, a slide and a ball: the names of their values" do
    hood = Joint.new("hood", :hinge, role: :hood, limits: [0, 50])
    assert Joint.values(hood) == ["hood"]
    assert Joint.values(Joint.new("drawer", :slide)) == ["drawer"]
    shoulder = Joint.new("shoulder_l", :ball, limits: %{flex: {-60, 180}})
    assert Joint.values(shoulder) == ["shoulder_l.flex", "shoulder_l.spread", "shoulder_l.twist"]
  end

  test "the limits, and the extras for the apps" do
    hood = Joint.new("hood", :hinge, role: :hood, limits: [0, 50])
    assert Joint.limits(hood, nil) == {0, 50}
    assert Joint.extras(hood) == %{"kind" => "hinge", "role" => "hood", "limits" => [0, 50]}

    elbow = Joint.new("elbow_l", :hinge, role: :elbow, limits: {0, 150})
    assert Joint.extras(elbow)["limits"] == [0, 150]

    wheel = Joint.new("wheel", :hinge)
    assert Joint.limits(wheel, nil) == nil
    assert Joint.extras(wheel) == %{"kind" => "hinge", "role" => nil, "limits" => nil}

    neck = Joint.new("neck", :ball, role: :neck, limits: %{flex: {-50, 60}})
    assert Joint.limits(neck, :flex) == {-50, 60}
    assert Joint.limits(neck, :twist) == nil
    assert Joint.extras(neck)["limits"] == %{"flex" => [-50, 60]}
  end

  property "a value stops at the nearest limit" do
    hood = Joint.new("hood", :hinge, limits: [0, 50])
    wheel = Joint.new("wheel", :hinge)

    check all v <- float(min: -1000.0, max: 1000.0) do
      c = Joint.clamp(hood, nil, v)
      assert c >= 0 and c <= 50
      if v >= 0 and v <= 50, do: assert(c == v)
      assert Joint.clamp(wheel, nil, v) == v
    end
  end
end
