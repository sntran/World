defmodule World.YardTest do
  # The first start of the node: the people build the warehouse and the
  # factories, then the trucks, then the models at their places (plan
  # 0002, D7), and the log of the yard replays in specs/Places.tla. Not
  # async: the yard is the one of the node, and each build asks it.
  use ExUnit.Case, async: false

  alias Accord.TLA.Checker
  alias World.{Haul, Log, Orders, PlacesSpec, Yard}

  @moduletag :tmp_dir
  @model Path.expand("../../specs/MCPlaces.tla", __DIR__)

  defp kind_of(kind), do: fn -> receive(do: ({:world, %{"kind" => ^kind} = e} -> e)) end

  test "the first start raises the buildings, opens the places, makes the trucks; a model waits for its place", %{
    tmp_dir: dir
  } do
    haul = start_supervised!({Haul, name: :yard_haul})
    :ok = World.watch(:world)
    start_supervised!({Yard, haul: haul, level: "far"})

    # The factory of the vehicles is not open yet: the yard holds the scooter.
    {:ok, scooter} = Orders.job(%{"blueprint" => "scooter", "options" => %{}}, "far")
    {:ok, id} = World.build(scooter)
    # The site is open: a house starts at once.
    {:ok, house} = Orders.job(%{"blueprint" => "tube_house", "options" => %{"floors" => 1}}, "far")
    {:ok, hid} = World.build(house)

    assert {:ok, h} = World.await(hid, 60_000)
    assert {:ok, r} = World.await(id, 120_000)
    for _ <- 1..2, do: kind_of("truck_made").()

    %{open: open, trucks: trucks, log: log} = Yard.state()
    assert open == ~w(gate nui_nho site vehicles warehouse workshop)
    assert trucks == ~w(truck_1 truck_2)
    assert Log.check(log) == :ok
    kinds = for e <- Log.events(log), do: {e.kind, e.data["place"] || e.data["truck"]}
    assert {"place_held", "vehicles"} in kinds and {"place_open", "warehouse"} in kinds
    assert PlacesSpec.replay(log, [r.log, h.log], dir) == :ok

    # With no place_open of the factory, the start of the scooter has no
    # step; in the fault model it is a construction at a place that is closed.
    shut = %{log | events: Enum.reject(log.events, &(&1.kind == "place_open" and &1.data["place"] == "vehicles"))}
    assert {:error, {:diverged, %{kind: "place_started"}}} = PlacesSpec.replay(shut, [], Path.join(dir, "shut"))

    assert {:error, {:violated, "AtOpen", %{kind: "place_started"}}} =
             PlacesSpec.replay(shut, [], Path.join(dir, "early"), guard: false)

    assert PlacesSpec.replay(Log.new(log.clock), [], Path.join(dir, "none")) == :ok

    # The scooter starts only after its factory is open.
    held = Enum.find_index(kinds, &(&1 == {"place_held", "vehicles"}))
    open_at = Enum.find_index(kinds, &(&1 == {"place_open", "vehicles"}))
    assert held < open_at

    # With the trucks of the yard, the haul rents no more trucks.
    {:ok, more} = Orders.job(%{"blueprint" => "tube_house", "options" => %{"floors" => 1, "width" => 5.0}}, "far")
    {:ok, mid} = World.build(more)
    assert {:ok, _} = World.await(mid, 60_000)
    events = Log.events(Haul.log(haul))

    ids =
      for %{kind: "haul_asked", data: d} <- events,
          String.starts_with?(d["for"], mid <> "|"),
          l <- d["loads"],
          do: l["id"]

    assert ids != [] and
             Enum.all?(
               events,
               &(&1.kind != "haul_asked" or &1.data["from"] == "warehouse" or
                   not String.starts_with?(&1.data["for"], mid))
             )

    trucks = for %{kind: "loaded", data: d} <- events, d["load"] in ids, uniq: true, do: d["truck"]
    assert trucks -- ~w(truck_1 truck_2) == []

    # A statue goes to the hill of Núi Nhỏ, on its top (plan 0006, D4),
    # and its model has its place in the game (D5).
    part = World.Part.new("box", :part, [World.Shape.box({0, 0, 0}, {1, 1, 1}, :concrete)], [])
    {:start, job} = Yard.place(%{id: "statue-geo", drawing: %{"kind" => "statue"}, item: fn _ -> part end})
    {:ok, hill} = World.Places.fetch("nui_nho")
    assert job.place == "nui_nho" and job.lot == "top" and job.geo == World.Places.geo(hill, "top")
    assert %{data: %{"lot" => "top", "place" => "nui_nho"}} = List.last(Yard.state().log |> Log.events())
    {:ok, gid} = World.build(%{job | drawing: nil})

    assert {:ok, %{glb: <<"glTF", _::binary-8, n::little-32, "JSON", json::binary-size(n), _::binary>>}} =
             World.await(gid, 30_000)

    assert JSON.decode!(json)["scenes"] |> hd() |> get_in(["extras", "geo"]) == job.geo
  end

  test "a building or a truck of the yard that fails or stops: the yard makes it again" do
    haul = start_supervised!({Haul, name: :again_haul})
    {:ok, s, _} = Yard.init(haul: haul, level: "far")
    s = %{s | own: %{"w" => {:building, "workshop"}, "t" => {:truck, "truck_9"}}}
    {:noreply, s} = Yard.handle_info({:stopped, "w", "seconds"}, s)
    {:noreply, s} = Yard.handle_info({:failed, "t", "a message"}, s)
    assert Enum.sort(Map.values(s.own)) == [{:building, "workshop"}, {:truck, "truck_9"}]
    for id <- Map.keys(s.own), do: assert({:ok, _} = World.await(id, 60_000))
  end

  test "a build with no yard, or with no place for its kind, starts at once" do
    {:ok, job} = Orders.job(%{"blueprint" => "scooter", "options" => %{}}, "far")
    assert {:start, ^job} = Yard.place(job, :no_yard)
    assert {:start, j} = Yard.place(%{job | drawing: Map.put(job.drawing, "kind", "statue")}, :no_yard)
    assert j.drawing["kind"] == "statue"
    assert {:start, %{drawing: nil}} = Yard.place(%{job | drawing: nil}, :no_yard)
  end

  test "the model of the first start: each place opens, each construction is done; the checker finds each fault" do
    assert {:ok, %{distinct_states: states}} = Checker.check(@model)
    assert states > 20
    assert {:error, _, _} = Checker.check(@model, config: Path.rootname(@model) <> "Lost.cfg")

    assert {:error, %{kind: :invariant, property: "AtOpen"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Early.cfg")
  end
end
