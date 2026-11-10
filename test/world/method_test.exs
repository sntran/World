defmodule World.MethodTest do
  # The methods of a site (plan 0006, D6 to D8; R4 to R6): the statue on
  # Núi Nhỏ with the method of today and with the true history of 1974,
  # the facts of the history and their sources, and the old statue in a
  # pause.
  use ExUnit.Case, async: true

  alias World.{Clock, Drawing, Log, Method, Orders}

  @moduletag :tmp_dir

  defp order(method), do: put_in(Drawing.raw("tuong_chua_kito_vua"), ["options", "method"], method)

  test "the history of the statue: each fact names its sources, each stage its facts, the dates in order" do
    h = Method.history("tuong_chua_kito_vua")
    sources = Map.keys(h["sources"])
    facts = for f <- h["facts"], into: %{}, do: {f["id"], f}
    assert map_size(facts) == 13 and length(sources) == 6

    for f <- h["facts"] do
      assert f["sources"] != [] and f["sources"] -- sources == [], f["id"]
      assert is_binary(f["text"])
    end

    for st <- h["stages"] ++ h["changes"], do: assert(st["facts"] != [] and st["facts"] -- Map.keys(facts) == [])

    assert Enum.map(h["stages"], & &1["name"]) == ~w(first_build first_pause first_down rough pause finish)
    pairs = Enum.chunk_every(h["stages"], 2, 1, :discard)
    for [a, b] <- pairs, do: assert(a["to"] == b["from"])
    assert hd(h["changes"])["date"] == Enum.find(h["stages"], &(&1["name"] == "first_down"))["from"]
    # Each value with no source says so.
    assert Enum.find(h["stages"], &(&1["name"] == "first_build"))["estimate"] =~ "no source"
    assert Method.history("nobody") == nil
  end

  test "the stages of a method: one build today; the six stages of 1974 with their days" do
    assert [%{name: "build", work: "build", until: "all", to: nil}] = Method.stages(order("today"))
    stages = Method.stages(order("1974"))
    assert Enum.map(stages, & &1.work) == ~w(build pause change build pause build)
    assert hd(stages).from == 0 and hd(stages).lot == "cape"
    # 16 February 1974 is day 595 of the site (from 1 July 1972).
    assert Enum.at(stages, 2).from == 595 and Enum.at(stages, 2).lot == "top"
    # The pause of 17 years: 30 April 1975 to 28 January 1992.
    pause = Enum.at(stages, 4)
    assert pause.to - pause.from == 6117 and pause.lost == ["the copper cable of the lightning rod"]
    assert List.last(stages).repair and List.last(stages).to == 8188
    assert Method.of(%{"options" => %{}}) == "today" and Method.workers("1974") == 50
    # A statue with no history: 1974 is one stage, at the rates of 1974.
    other = put_in(order("1974"), ["options", "name"], "another")
    assert [%{name: "build"}] = Method.stages(other)
  end

  test "the statue today and in 1974: the same model, two schedules, the six stages, the change and the pauses",
       %{tmp_dir: dir} do
    {:ok, today} = Orders.job(order("today"), "far")
    {:ok, old} = Orders.job(order("1974"), "far")
    assert today.hash != old.hash and old.method == "1974" and old.lot == "cape"
    # The first statue: 8.6 m on its base.
    assert Enum.find(old.drawing["nodes"], &(&1["name"] == "survey"))["skill"]["cast_survey"]["height"] == 8.6

    {:ok, a} = World.build(%{today | id: "method-today-#{System.unique_integer([:positive])}"})
    {:ok, b} = World.build(%{old | id: "method-1974-#{System.unique_integer([:positive])}"})
    assert {:ok, ra} = World.await(a, 60_000)
    assert {:ok, rb} = World.await(b, 120_000)
    assert ra.glb == rb.glb
    assert Log.check(ra.log) == :ok and Log.check(rb.log) == :ok
    assert World.BuildSpec.replay([rb.log], dir) == :ok

    events = Log.events(rb.log)
    start = hd(events).at
    day = fn e -> (e.at - start) / Clock.day() end
    stages = for e <- events, e.kind == "stage_started", do: e.data["name"]
    assert stages == ~w(first_build first_pause first_down rough pause finish)

    # Each stage starts at its date, or later when the computer is slow:
    # at 1,000 days in a second, the work of the computer on the figure
    # (0.8 s) is 800 days (at one day in a second, less than one day).
    # The days of the tasks of a stage are fitted to the days that are left.
    plan = Method.stages(order("1974"))

    for e <- events, e.kind == "stage_started" do
      st = Enum.find(plan, &(&1.name == e.data["name"]))
      assert day.(e) >= st.from - 1, st.name

      if st.work == "build" do
        drawing = if st.name == "first_build", do: old.drawing, else: today.drawing
        span = World.Site.span(World.Site.schedule(drawing, "1974", e.data["tasks"]))
        assert_in_delta e.data["fit"] * span, max(st.to - max(day.(e), st.from), 1), 5.0
      end
    end

    # The change of 16 February 1974: the first statue comes down at the cape.
    assert %{data: %{"lot" => "top", "remove" => [_ | _] = removes}} = Enum.find(events, &(&1.kind == "changed"))
    gone = for e <- events, e.kind == "element_removed", do: e.data["task"]
    assert length(gone) == length(removes) and gone != []

    # The pauses: the statue gets old with the years, the cable of the
    # lightning rod goes in the middle of the pause of 17 years, and the
    # repair of 1992 makes it clean (plan 0006, D8).
    aged = for e <- events, e.kind == "aged", do: e.data
    # The first pause at its end (it is short when the computer is slow);
    # the pause of 17 years each year that is left of it, and at its end.
    assert length(aged) >= 12 and List.last(aged)["days"] > 4000
    # The new statue has no age at the change: its dirt grows in the long pause.
    long = Enum.find_index(events, &(&1.kind == "stage_started" and &1.data["name"] == "pause"))
    dirt = for e <- Enum.drop(events, long), e.kind == "aged", do: e.data["dirt"]
    assert dirt == Enum.sort(dirt)
    # The dirt and the weeds from the years (a pause that starts late is shorter).
    last = List.last(aged)
    assert_in_delta last["dirt"], 1 - :math.exp(-last["days"] / 365 / 8), 0.001
    assert_in_delta last["weeds"], min(last["days"] / 365 / 5, 1.0), 0.001
    assert [["the copper cable of the lightning rod"]] = for(a <- aged, a["lost"] != [], do: a["lost"])

    assert %{data: %{"parts" => ["the copper cable of the lightning rod"]}} =
             Enum.find(events, &(&1.kind == "repaired"))

    assert Enum.find_index(events, &(&1.kind == "repaired")) > Enum.find_index(events, &(&1.kind == "aged"))

    # The end: on or after 1 December 1994.
    assert day.(List.last(events)) >= 8188 - 1
    # Today: one stage, about a year.
    assert [%{data: %{"name" => "build", "fit" => 1.0}}] =
             for(e <- Log.events(ra.log), e.kind == "stage_started", do: e)

    span = (List.last(Log.events(ra.log)).at - hd(Log.events(ra.log)).at) / Clock.day()
    # About a year of the plan; more with the work of a slow computer.
    assert span > 300 and World.Site.span(World.Site.schedule(today.drawing)) < 400
  end

  test "the replay of the statue has each part that a person sees on the site, with its tasks; the model passes its checks" do
    glb = Orders.build(order("1974"), "mid", "replay") |> elem(1)
    <<"glTF", _::binary-8, n::little-32, "JSON", json::binary-size(n), _::binary>> = glb
    nodes = for n <- JSON.decode!(json)["nodes"], e = n["extras"], e["from"], into: %{}, do: {e["from"], e["to"]}

    for i <- 1..8 do
      assert nodes["scaffold_#{i}"] == "unscaffold" and nodes["form_#{i}"] == "strip_#{i}"
      assert nodes["pour_#{i}"] == "tuong_chua_kito_vua"
    end

    # The parts of the end stay: no task takes them down.
    assert Map.has_key?(nodes, "tuong_chua_kito_vua") and nodes["be"] == nil
    {:ok, job} = Orders.job(order("1974"), "mid")
    stream = World.Detail.with(:mid, fn -> Drawing.build(job.model, stream: true) end)
    assert World.Check.model(stream) == :ok

    # The tower crane of a site of today (D6): up after the base, down
    # after the scaffold; no crane in 1974.
    {:ok, today} = Orders.job(order("today"), "mid")
    crane = Enum.find(today.drawing["nodes"], &(&1["name"] == "crane"))
    assert crane["down"] == "crane_down" and crane["temporary"] and not Map.has_key?(crane, "only")
    assert Enum.find(today.drawing["nodes"], &(&1["name"] == "crane_down"))["after"] == ["unscaffold"]
    refute Enum.any?(job.model["nodes"], &(&1["name"] in ~w(crane crane_down)))
    stream = World.Detail.with(:mid, fn -> Drawing.build(today.drawing, stream: true) end)
    assert World.Check.model(stream) == :ok
    {p, _, _} = World.Skills.Crane.make(crane["skill"]["crane"], %{}, %{name: "crane"})
    {{_, _, _}, {_, _, top}} = World.Part.bounds(p)
    # Its jib over the top of the statue (the halo at 7.7 + 28 m).
    assert top > 7.7 + 28.0 + 7 and World.Skills.Crane.check(%{"at" => [1]}, "c") != []
  end
end
