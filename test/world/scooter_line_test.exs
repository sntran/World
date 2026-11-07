defmodule World.ScooterLineTest do
  # The people build a scooter as on the line of its maker (plan 0002, D5).
  use ExUnit.Case, async: true

  alias World.{Build, BuildSpec, Check, Detail, Drawing, Log, Orders, Scene}
  alias World.Orders.Blueprints
  alias World.Vehicles.HondaVision

  @moduletag :tmp_dir

  defp scooter(level) do
    {:ok, full} = Orders.check(%{"blueprint" => "scooter_line", "options" => %{}})
    {:ok, b} = Blueprints.fetch("scooter_line")
    Detail.with(level, fn -> b.build.(full["options"]) end)
  end

  defp joints(item, level), do: for(n <- Build.scene(item, level: level).nodes, n.extras["joint"], do: n.name)

  test "a scooter of the line at each level: the same parts, joints and size as the Honda Vision of one task" do
    for level <- [:near, :mid, :far] do
      line = scooter(level)
      one = Detail.with(level, &HondaVision.model/0)
      assert line.kind == :vehicle and Check.model(line) == :ok
      assert Scene.triangles(Build.scene(line, level: level)) == Scene.triangles(Build.scene(one, level: level))
      assert Enum.sort(joints(line, level)) == Enum.sort(joints(one, level))
      assert Scene.bounds(Build.scene(line, level: level)) == Scene.bounds(Build.scene(one, level: level))
    end

    assert Enum.any?(scooter(:near).sources, &(&1 =~ "1871 mm"))
  end

  test "the people build a scooter: the trades, the replay; the errors of the data", %{tmp_dir: dir} do
    {:ok, job} = Orders.job(%{"blueprint" => "scooter_line", "options" => %{}}, "near")
    {:ok, id} = World.build(Map.put(job, :budget, %{"workers" => 16}))
    assert {:ok, r} = World.await(id, 120_000)
    assert r.glb == World.GLB.encode(job.scene.(job.item.(:near), []))
    assert Log.check(r.log) == :ok
    assert BuildSpec.replay([r.log], dir) == :ok

    trades = for %{kind: "hired", data: %{"trade" => t}} <- Log.events(r.log), uniq: true, do: t
    assert Enum.sort(trades) == ~w(mechanic molder smith upholsterer welder)
    assert Drawing.estimate(job.drawing, :near) > Drawing.estimate(job.drawing, :far)

    d = %{"nodes" => [%{"name" => "frame", "skill" => %{"scooter_frame" => %{"model" => "vespa"}}}]}

    assert {:error, [%{"path" => "options.drawing.nodes.0.skill.scooter_frame.model"}]} =
             Orders.check(%{"blueprint" => "drawing", "options" => %{"drawing" => d}})
  end
end
