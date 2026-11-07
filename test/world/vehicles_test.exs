defmodule World.VehiclesTest do
  # The vehicles of World as blueprints in data, made by the skills of
  # the vehicle trades only (plan 0002, D5): each gives the model of the
  # catalog, and other numbers give other vehicles.
  use ExUnit.Case, async: true

  alias World.{Build, BuildSpec, Check, Detail, Log, Orders, Scene}
  alias World.Orders.Blueprints

  @moduletag :tmp_dir

  defp model(blueprint, level, options \\ %{}) do
    {:ok, full} = Orders.check(%{"blueprint" => blueprint, "options" => options})
    {:ok, b} = Blueprints.fetch(blueprint)
    Detail.with(level, fn -> b.build.(full["options"]) end)
  end

  # The triangles, the joints and the size of the scene of a model.
  defp shape(item, level) do
    s = Build.scene(item, level: level)
    {Scene.triangles(s), Enum.sort(s.extras["joints"]), Scene.bounds(s)}
  end

  defp same(a, b) do
    {ta, ja, {lo_a, hi_a}} = a
    {tb, jb, {lo_b, hi_b}} = b
    assert {ta, ja} == {tb, jb}

    for {u, v} <- Enum.zip(Tuple.to_list(lo_a) ++ Tuple.to_list(hi_a), Tuple.to_list(lo_b) ++ Tuple.to_list(hi_b)),
        do: assert_in_delta(u, v, 1.0e-9)
  end

  defp built(blueprint, options, dir) do
    {:ok, job} = Orders.job(%{"blueprint" => blueprint, "options" => options}, "mid")
    {:ok, id} = World.build(Map.put(job, :budget, %{"workers" => 16}))
    assert {:ok, r} = World.await(id, 120_000)
    assert r.glb == World.GLB.encode(job.scene.(job.item.(:mid), []))
    assert World.Drawing.estimate(job.drawing, :near) > World.Drawing.estimate(job.drawing, :far)
    assert Log.check(r.log) == :ok and BuildSpec.replay([r.log], dir) == :ok
    for %{kind: "hired", data: %{"trade" => t}} <- Log.events(r.log), uniq: true, do: t
  end

  test "a bicycle from its geometry sheet: the touring bicycle of the catalog, and a frame of 58 cm", %{tmp_dir: dir} do
    for level <- [:near, :mid, :far] do
      bike = model("bicycle", level)
      assert bike.kind == :vehicle and Check.model(bike) == :ok
      same(shape(bike, level), shape(Detail.with(level, &World.Vehicles.TouringBicycle.model/0), level))
    end

    big = %{"stack" => 0.62, "reach" => 0.39, "seat_tube" => 0.58, "wheelbase" => 1.06, "head_angle" => 72.5}
    assert Check.model(model("bicycle", :near, big)) == :ok
    {_, _, {{_, y0, _}, {_, y1, _}}} = shape(model("bicycle", :far, big), :far)
    assert y1 - y0 > 1.06

    assert Enum.sort(built("bicycle", %{}, dir)) == ~w(mechanic smith welder wheelwright)

    assert {:error, [%{"path" => "drawing.nodes.0.skill.bicycle_frame.tire"} | _]} =
             Orders.check(%{"blueprint" => "bicycle", "options" => %{"tire" => "no tire"}})
  end

  test "a scooter and a motorcycle from their parts: the Honda Vision and the Himalayan of the catalog", %{tmp_dir: dir} do
    for {blueprint, reference} <- [
          {"scooter", &World.Vehicles.HondaVision.model/0},
          {"motorcycle", &World.Vehicles.RoyalEnfieldHimalayan.model/0}
        ],
        level <- [:near, :mid, :far] do
      bike = model(blueprint, level)
      assert bike.kind == :vehicle and Check.model(bike) == :ok, "#{blueprint} #{level}"
      same(shape(bike, level), shape(Detail.with(level, reference), level))
    end

    assert ~w(mechanic molder smith upholsterer welder wheelwright) -- built("scooter", %{}, Path.join(dir, "s")) == []

    assert ~w(electrician mechanic sheet_metal_worker welder wheelwright) --
             built("motorcycle", %{}, Path.join(dir, "m")) == []
  end
end
