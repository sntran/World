defmodule World.VanLineTest do
  # The people build a van as on the line of its maker (plan 0002, D5).
  use ExUnit.Case, async: true

  alias World.{Build, BuildSpec, Check, Detail, Drawing, Log, Orders, Scene}
  alias World.Orders.Blueprints
  alias World.Vehicles.Van

  @moduletag :tmp_dir

  defp van(level, options) do
    {:ok, full} = Orders.check(%{"blueprint" => "van_line", "options" => options})
    {:ok, b} = Blueprints.fetch("van_line")
    Detail.with(level, fn -> b.build.(full["options"]) end)
  end

  defp names(item), do: Enum.map(item.nodes, &elem(&1, 0))
  defp triangles(item, level), do: Scene.triangles(Build.scene(item, level: level))

  # The triangles, the joints and the size of the scene of a model.
  defp shape(item, level) do
    s = Build.scene(item, level: level)
    {Scene.triangles(s), Enum.sort(s.extras["joints"]), Scene.bounds(s)}
  end

  @tag timeout: 300_000
  test "a cargo van of the line at each level: the same parts and joints as the van of the line in one task" do
    for level <- [:near, :mid, :far] do
      line = van(level, %{})
      one = Detail.with(level, fn -> Van.build("transit_148", name: "van") end)
      assert line.kind == :vehicle and Check.model(line) == :ok
      assert shape(line, level) == shape(one, level)
      assert "front_right_wheel" in elem(shape(line, level), 1)
    end

    near = van(:near, %{})

    assert ~w(body inside closure_hood closure_sliding_door glass seats chassis_engine_bay chassis_rear_left) --
             names(near) == []

    # No item on the roof: no upfit.
    refute "upfit" in names(near)
    assert Enum.any?(near.sources, &(&1 =~ "Ford"))
    refute Map.has_key?(near.extras, "place")

    # At mid, nothing of the inside: no seats, no cab, no small parts.
    refute Enum.any?(~w(inside seats trim_cab trim_details), &(&1 in names(van(:mid, %{}))))
    assert triangles(van(:near, %{}), :near) > triangles(van(:far, %{}), :far)
  end

  @tag timeout: 300_000
  test "a van of other options: the passenger windows, two rows, the items of DIY in the bay and on the roof" do
    options = %{
      "model" => "transit_148",
      "windows" => "passenger",
      "rows" => 2,
      "engine_bay" => ["dc_charger"],
      "roof" => [%{"kind" => "fan", "at" => 3.1}, %{"kind" => "solar", "at" => 4.5}]
    }

    near = van(:near, options)
    assert Check.model(near) == :ok and "upfit" in names(near)

    one =
      Detail.with(:near, fn ->
        Van.build("transit_148",
          name: "van",
          windows: "passenger",
          rows: 2,
          engine_bay: [:dc_charger],
          roof: [{:fan, 3.1}, {:solar, 4.5}]
        )
      end)

    assert triangles(near, :near) == triangles(one, :near)
  end

  test "the people build a van: the stations at one time, the trades, the replay", %{tmp_dir: dir} do
    {:ok, job} = Orders.job(%{"blueprint" => "van_line", "options" => %{}}, "mid")
    {:ok, id} = World.build(Map.put(job, :budget, %{"workers" => 16}))
    assert {:ok, r} = World.await(id, 120_000)
    assert r.glb == World.GLB.encode(job.scene.(job.item.(:mid), []))
    assert Log.check(r.log) == :ok
    assert BuildSpec.replay([r.log], dir) == :ok

    trades = for %{kind: "hired", data: %{"trade" => t}} <- Log.events(r.log), uniq: true, do: t
    assert ~w(engineer fitter glazier mechanic sheet_metal_worker trimmer) -- trades == []
    assert Drawing.estimate(job.drawing, :near) > Drawing.estimate(job.drawing, :mid)
    assert Drawing.estimate(job.drawing, :mid) > Drawing.estimate(job.drawing, :far)
  end

  test "the errors of the data of the skills of a van" do
    d = %{
      "nodes" => [
        %{"name" => "order", "skill" => %{"van_order" => %{"model" => "transit_148", "size" => %{"length" => 9.0}}}},
        %{"name" => "body", "skill" => %{"van_body" => %{"x" => 1}}},
        %{"name" => "hood", "skill" => %{"van_closure" => %{"group" => "roof"}}},
        %{"name" => "w", "skill" => %{"van_order" => %{"rows" => 9}}},
        %{"name" => "v", "skill" => %{"van_order" => 3}}
      ]
    }

    assert {:error, errors} = Orders.check(%{"blueprint" => "drawing", "options" => %{"drawing" => d}})

    assert Enum.map(errors, & &1["path"]) == [
             "options.drawing.nodes.0.skill.van_order.size.length",
             "options.drawing.nodes.1.skill.van_body.x",
             "options.drawing.nodes.2.skill.van_closure.group",
             "options.drawing.nodes.3.skill.van_order.rows",
             "options.drawing.nodes.4.skill.van_order"
           ]

    assert {:error, [%{"path" => "options.model"}]} =
             Orders.check(%{"blueprint" => "van_line", "options" => %{"model" => "bus"}})
  end

  @tag timeout: 300_000
  test "a van from the data of its model in the order: the same van as its name, and a van of other numbers" do
    vans = "priv/data/vans.json" |> File.read!() |> JSON.decode!()
    transit = vans["models"]["transit_148"]
    data = Map.put(transit, "make", vans["makes"][transit["make"]])

    for level <- [:mid, :far] do
      assert shape(van(level, %{"model" => data}), level) == shape(van(level, %{}), level)
    end

    other = %{data | "length" => 5.6, "wheelbase" => 3.4, "name" => "A van of 3.4 m"}
    short = van(:far, %{"model" => other})
    assert Check.model(short) == :ok
    {_, _, {{_, y0, _}, {_, y1, _}}} = shape(short, :far)
    assert_in_delta y1 - y0, 5.6, 0.2

    bad = fn model -> elem(Orders.check(%{"blueprint" => "van_line", "options" => %{"model" => model}}), 1) end
    assert [%{"path" => "options.model.length"} | _] = bad.(Map.delete(data, "length"))
    assert [%{"path" => "options.model.make"}] = bad.(%{data | "make" => "ford_transit"})
    assert [%{"path" => "options.model.make.traces"}] = bad.(%{data | "make" => Map.delete(data["make"], "traces")})

    assert [%{"path" => "options.model", "message" => "does not make the hull of a van" <> _}] =
             bad.(put_in(data, ["make", "traces"], %{}))

    assert [%{"path" => "options.rows"}] =
             elem(Orders.check(%{"blueprint" => "van_line", "options" => %{"model" => data, "rows" => 9}}), 1)

    assert [{"o.rows", _}] = World.Skills.Van.check(%{"model" => data, "rows" => 9}, "o")
  end
end
