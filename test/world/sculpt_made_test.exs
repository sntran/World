defmodule World.Sculpt.MadeTest do
  # The surfaces of made things (plan 0020, step 3: R10 to R13): the
  # windows of a building, the plates of a hull and the sheets of a roof.
  use ExUnit.Case, async: true

  alias World.{Detail, Frame, Mesh, SDF}
  alias World.Sculpt.{Finish, Texture}
  alias World.Skills.Sculpt

  @up {0.0, 0.0, 1.0}
  @front {0.0, 1.0, 0.0}
  @side {1.0, 0.0, 0.0}

  # The tower of Humans Must Die (issue #48): 40 storeys of 3.5 m with 30
  # windows of 1.5 m on each side, on a podium, with a roof of plates.
  defp tower(far) do
    %{
      "edits" => [
        %{
          "shape" => "box",
          "size" => [24, 24, 3],
          "at" => [0, 0, 3],
          "color" => "#6f7478",
          "surface" => %{"kind" => "windows", "pane" => [2.6, 4.0], "frame" => [0.4, 2.0], "lit" => 0.6, "seed" => 41}
        },
        %{
          "shape" => "box",
          "size" => [22.5, 22.5, 70],
          "at" => [0, 0, 76],
          "color" => "#9aa3a8",
          "surface" => %{"kind" => "windows", "pane" => [1.1, 2.2], "frame" => [0.4, 1.3], "lit" => 0.35, "seed" => 40}
        },
        %{
          "shape" => "box",
          "size" => [20, 20, 2.5],
          "at" => [0, 0, 148.5],
          "color" => "#5c6166",
          "surface" => %{"kind" => "panels", "plate" => [2.0, 1.0], "seam" => 0.02, "depth" => 0.01}
        }
      ],
      "cells" => %{"far" => 2.0},
      "budget" => %{"far" => 200},
      "bake" => far
    }
  end

  defp far(data, name \\ "made"),
    do: Detail.with(:far, fn -> Sculpt.make(data, %{}, %{level: :far, name: name}) end)

  defp triangles(part), do: part.shapes |> Enum.map(&length(&1.faces)) |> Enum.sum()

  # The pieces of a set of texels: each texel with the texels next to it (at its four sides).
  defp pieces(set) do
    {n, _} =
      Enum.reduce(set, {0, MapSet.new()}, fn k, {n, seen} ->
        if MapSet.member?(seen, k), do: {n, seen}, else: {n + 1, fill([k], MapSet.put(seen, k), set)}
      end)

    n
  end

  defp fill([], seen, _set), do: seen

  defp fill([{x, y} | rest], seen, set) do
    next =
      for {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}],
          q = {x + dx, y + dy},
          MapSet.member?(set, q),
          not MapSet.member?(seen, q),
          do: q

    fill(next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)), set)
  end

  test "the three kinds and their data: each word with its default, and the panes that fit the faces of a box (R10)" do
    assert Texture.made_kinds() == ~w(corrugated panels windows)
    assert Enum.all?(Texture.made_kinds(), &(&1 in Texture.kinds()))

    assert {{:windows, w}, 1.0} = Texture.kind("windows")
    assert {w.pane, w.frame, w.lit, w.seed, w.phase} == {{1.2, 1.5}, {0.3, 0.3}, 0.0, 1, {0.0, 0.0, 0.0}}
    assert {w.warm, w.cold} == {{255.0, 208.0, 138.0}, {214.0, 228.0, 255.0}}

    # A face of 30 pitches across and 40 up has whole panes from its middle; a face of 3 pitches has a pane at its middle.
    data = %{"pane" => [1.1, 2.2], "frame" => [0.4, 1.3]}
    assert {:windows, %{frame: {0.4, 1.3}, phase: {+0.0, +0.0, +0.0}}} = Texture.made("windows", data, {22.5, 22.5, 70.0})
    assert {:windows, %{phase: {0.75, +0.0, 1.75}}} = Texture.made("windows", data, {2.25, 1.5, 1.75})

    assert Texture.made("panels", %{}) == {:panels, %{plate: {1.0, 0.5}, seam: 0.006, depth: 0.002, rivets: nil}}
    assert {:panels, %{rivets: 0.05}} = Texture.made("panels", %{"rivets" => 0.05})

    assert Texture.made("corrugated", %{}) ==
             {:corrugated, %{profile: :square, pitch: 0.25, depth: 0.032, top: 0.03}}

    # In the data of a sculpture: a kind by its name, a kind with its data on a shape that is not a box, and in a group at a scale.
    edits = fn list, groups -> Sculpt.edits(list, groups) end

    assert [%{surface: {{:corrugated, %{pitch: 0.25}}, 1.0}}] =
             edits.([%{"shape" => "box", "size" => [1, 1, 1], "surface" => "corrugated"}], %{})

    tank = %{
      "shape" => "cylinder",
      "size" => [1, 2],
      "surface" => %{"kind" => "windows", "pane" => [0.5, 0.5], "scale" => 2}
    }

    assert [%{surface: {{:windows, %{phase: {+0.0, +0.0, +0.0}, pane: {0.5, 0.5}}}, 2.0}}] = edits.([tank], %{})

    assert [%{surface: {{:windows, _}, 6.0}}] =
             edits.([%{"shape" => "group", "group" => "g", "scale" => 3}], %{"g" => [tank]})

    assert Texture.glows?({Texture.made("windows", %{"lit" => 0.2}), 1.0})
    refute Texture.glows?(Texture.kind("windows")) or Texture.glows?({:wood, 0.006}) or Texture.glows?(nil)
  end

  test "the check of each value of the data of a surface, with its path (R10)" do
    check = fn surface ->
      %{"edits" => [%{"shape" => "box", "size" => [1, 1, 1], "surface" => surface}]}
      |> Sculpt.check("s")
      |> Enum.map(&elem(&1, 0))
    end

    at = "s.edits.0.surface"

    good = %{
      "kind" => "windows",
      "pane" => [1, 2],
      "frame" => [0.2, 1],
      "lit" => 0.5,
      "seed" => 3,
      "warm" => "#ffcc88",
      "cold" => "#CCDDFF",
      "scale" => 2
    }

    assert check.(good) == [] and check.("windows") == [] and check.("panels") == [] and check.("corrugated") == []
    assert check.(%{"kind" => "windows", "frame" => 0}) == []
    assert check.(%{"kind" => "panels", "rivets" => nil}) == [] and check.(%{"kind" => "panels", "rivets" => 0.1}) == []
    assert check.(%{"kind" => "corrugated", "profile" => "round", "pitch" => 0.05, "depth" => 0.02}) == []

    for {word, value} <- [
          {"pane", 1},
          {"pane", [0.01, 1]},
          {"frame", [1]},
          {"frame", -1},
          {"lit", 2},
          {"seed", -1},
          {"seed", 1.5},
          {"warm", "red"},
          {"cold", "#12345"},
          {"glass", 1}
        ] do
      assert check.(%{"kind" => "windows", word => value}) == ["#{at}.#{word}"], inspect({word, value})
    end

    for {word, value} <- [{"plate", [0, 1]}, {"seam", 1}, {"depth", 1}, {"rivets", 0.001}, {"pane", [1, 1]}] do
      assert check.(%{"kind" => "panels", word => value}) == ["#{at}.#{word}"], inspect({word, value})
    end

    for {word, value} <- [{"profile", "wavy"}, {"pitch", 5}, {"depth", 0}, {"top", 0}] do
      assert check.(%{"kind" => "corrugated", word => value}) == ["#{at}.#{word}"], inspect({word, value})
    end

    # A square rib: its top and its two sides in one pitch, with the default of a word that is not there too.
    assert check.(%{"kind" => "corrugated", "top" => 0.2}) == ["#{at}.top"]
    assert check.(%{"kind" => "corrugated", "pitch" => 0.05}) == ["#{at}.top"]
    assert check.(%{"kind" => "corrugated", "profile" => "round", "top" => 0.2}) == []
    # The surfaces of before keep their check.
    assert check.(%{"kind" => "wood", "lit" => 1}) == ["#{at}.lit"]
    assert check.(%{"kind" => "windows", "scale" => 0}) == ["#{at}.scale"]
  end

  test "windows: glass in the panes, the color of the edit in the frames, the light of some panes, and their mean" do
    {:windows, w} = Texture.made("windows", %{})
    # (A pane is 1.2 by 1.5 m with frames of 0.3 m: the frames at 0, 1.5, 3 m across, and at 0, 1.8 m up.)
    assert Texture.look({:windows, w}, {0.75, 0.0, 0.9}, @up, 0.01) == {0.0, 1.0, nil}

    assert {h, 1.0, {{39.0, 49.0, 61.0}, {0.05, metal, glow}, part}} =
             Texture.look({:windows, w}, {0.75, 0.0, 0.9}, @front, 0.01)

    assert_in_delta h, -0.02, 1.0e-9
    assert_in_delta part, 1.0, 1.0e-9
    assert metal == 0.0 and glow == 0.0

    for {q, face} <- [{{0.0, 0.0, 0.9}, @front}, {{0.0, 0.75, 1.8}, @side}] do
      {h, 1.0, {_, {_, _, glow}, part}} = Texture.look({:windows, w}, q, face, 0.01)
      assert h == 0.0 and glow == 0.0 and part == 0.0
    end

    # The color and the finish of a place: the color of the edit times the tone, then the part of the glass.
    assert Texture.apply({0.0, 0.5, nil}, {200.0, 100.0, 50.0}, {0.6, 0.2, 0.0}) ==
             {{100.0, 50.0, 25.0}, {0.6, 0.2, 0.0}}

    assert Texture.apply({0.0, 1.0, {{0.0, 0.0, 0.0}, {0.0, 1.0, 1.0}, 0.5}}, {200.0, 100.0, 50.0}, {0.6, 0.0, 0.0}) ==
             {{100.0, 50.0, 25.0}, {0.3, 0.5, 0.5}}

    # A share of the panes has light, by a hash of the seed, the face, the row and the column: the same each time.
    {:windows, lit} = Texture.made("windows", %{"lit" => 0.35, "seed" => 40})

    panes =
      for face <- [@front, @side], i <- 0..29, j <- 0..39 do
        q = if face == @front, do: {1.5 * i + 0.75, 0.0, 1.8 * j + 0.9}, else: {0.0, 1.5 * i + 0.75, 1.8 * j + 0.9}
        {_, _, {color, {_, _, glow}, _}} = look = Texture.look({:windows, lit}, q, face, 0.01)
        assert Texture.look({:windows, lit}, q, face, 0.01) == look
        {color, glow}
      end

    near = fn {a, b, c}, {d, e, f} -> abs(a - d) + abs(b - e) + abs(c - f) < 1.0e-6 end
    on = Enum.filter(panes, &(elem(&1, 1) > 0.0))
    assert_in_delta length(on) / length(panes), 0.35, 0.04

    assert Enum.all?(on, fn {color, glow} ->
             abs(glow - 0.9) < 1.0e-9 and (near.(color, lit.warm) or near.(color, lit.cold))
           end)

    assert_in_delta Enum.count(on, &near.(elem(&1, 0), lit.warm)) / length(on), 2 / 3, 0.06
    # The panes of the other side of a box are not the panes of this side.
    back =
      for i <- 0..29,
          j <- 0..39,
          do:
            elem(
              elem(Texture.look({:windows, lit}, {1.5 * i + 0.75, 0.0, 1.8 * j + 0.9}, {0.0, -1.0, 0.0}, 0.01), 2),
              1
            )

    refute Enum.map(back, &elem(&1, 2)) == for({_, g} <- Enum.take(panes, 1200), do: g)

    # A square of a few panes: the glass of the panes in it, the light of each by its area.
    {_, _, {_, {_, _, glow}, part}} = Texture.look({:windows, lit}, {3.0, 0.0, 1.8}, @front, 0.36)
    assert part > 0.0 and part < 1.0 and glow >= 0.0 and glow <= 0.9
    # A square of more than half a pitch: the mean of all the panes (the part of the glass, the share of the light).
    {_, _, {_, {_, _, glow}, part}} = Texture.look({:windows, lit}, {3.3, 0.0, 2.2}, @front, 0.9)
    assert_in_delta part, 1.2 * 1.5 / (1.5 * 1.8), 1.0e-9
    assert_in_delta glow, 0.9 * 0.35, 1.0e-9
    # (Over 8 panes on an axis, the panes are not counted one by one.)
    {height, 1.0, {_, {_, _, glow}, part}} = Texture.look({:windows, lit}, {3.3, 0.0, 2.2}, @front, 30.0)
    assert_in_delta part, 1.2 * 1.5 / (1.5 * 1.8), 0.02
    assert_in_delta height, -0.02 * part, 1.0e-9
    assert_in_delta glow, 0.9 * 0.35, 1.0e-9
    # With no lit pane in the square, the mean color of the light stays.
    {:windows, dark} = Texture.made("windows", %{"lit" => 0.0})
    assert {_, _, {{39.0, 49.0, 61.0}, {_, _, glow}, _}} = Texture.look({:windows, dark}, {3.0, 0.0, 1.8}, @front, 0.5)
    assert glow == 0.0
  end

  test "panels: dark seams at the borders of the plates, rivets on the seams, and their mean in a large square" do
    {:panels, k} = Texture.made("panels", %{"rivets" => 0.06})
    assert Texture.look({:panels, k}, {0.5, 0.25, 0.0}, @up, 0.001) == {0.0, 1.0, nil}
    # A seam (across x at each 1 m, across y at each 0.5 m): lower and darker.
    assert {h, tone, nil} = Texture.look({:panels, k}, {0.0, 0.25, 0.0}, @up, 0.001)
    assert_in_delta h, -0.002, 1.0e-9
    assert_in_delta tone, 0.6, 1.0e-9
    assert {h, _, nil} = Texture.look({:panels, k}, {0.0, 0.0, 0.25}, @front, 0.001)
    assert_in_delta h, -0.002, 1.0e-9
    assert {h, _, nil} = Texture.look({:panels, k}, {0.0, 0.5, 0.0}, @side, 0.001)
    assert_in_delta h, -0.002, 1.0e-9
    # A rivet: 1.5 rivets from the seam, at each 6 cm along it.
    {h, tone, nil} = Texture.look({:panels, k}, {0.012, 0.06, 0.0}, @up, 0.001)
    assert_in_delta h, 0.003, 1.0e-9
    assert tone > 1.0
    # In a large square, the mean: a little lower and darker everywhere, and a little higher with the rivets.
    {:panels, plain} = Texture.made("panels", %{})
    assert Texture.look({:panels, plain}, {0.012, 0.06, 0.0}, @up, 0.001) == {0.0, 1.0, nil}
    {h, tone, nil} = Texture.look({:panels, plain}, {0.3, 0.2, 0.0}, @up, 3.0)
    assert h < 0.0 and h > -0.002 and tone < 1.0 and tone > 0.95
    assert elem(Texture.look({:panels, k}, {0.3, 0.2, 0.0}, @up, 3.0), 0) > h
  end

  test "corrugated: square and round ribs, along z on a face that stands up and along y on a face that faces z" do
    {:corrugated, sq} = Texture.made("corrugated", %{})
    mean = (0.032 * 0.03 + 0.032 * 0.032) / 0.25
    # The top of a rib, its side, and the pan; the mean of the sheet is its surface.
    assert_in_delta elem(Texture.look({:corrugated, sq}, {0.0, 0.0, 0.0}, @up, 0.0), 0), 0.032 - mean, 1.0e-9
    assert_in_delta elem(Texture.look({:corrugated, sq}, {0.031, 0.0, 0.0}, @up, 0.0), 0), 0.016 - mean, 1.0e-9
    assert_in_delta elem(Texture.look({:corrugated, sq}, {0.125, 0.0, 0.0}, @up, 0.0), 0), -mean, 1.0e-9
    # (On a face that faces x the ribs go along z, and the profile goes along y.)
    assert_in_delta elem(Texture.look({:corrugated, sq}, {0.125, 0.0, 0.3}, @side, 0.0), 0), 0.032 - mean, 1.0e-9
    assert_in_delta elem(Texture.look({:corrugated, sq}, {0.0, 0.125, 0.3}, @side, 0.0), 0), -mean, 1.0e-9

    # A square of one pitch or more is the mean of the ribs: no relief.
    for s <- [0.0, 0.07, -0.33, 1.9] do
      assert_in_delta elem(Texture.look({:corrugated, sq}, {s, 0.0, 0.0}, @front, 0.25), 0), 0.0, 1.0e-9
      assert abs(elem(Texture.look({:corrugated, sq}, {s, 0.0, 0.0}, @front, 0.1), 0)) < 0.032
    end

    {:corrugated, round} = Texture.made("corrugated", %{"profile" => "round", "pitch" => 0.08, "depth" => 0.012})
    assert {h, 1.0, nil} = Texture.look({:corrugated, round}, {0.0, 0.0, 0.0}, @front, 0.0)
    assert_in_delta h, 0.006, 1.0e-9
    assert_in_delta elem(Texture.look({:corrugated, round}, {0.04, 0.0, 0.0}, @front, 0.0), 0), -0.006, 1.0e-9
    assert_in_delta elem(Texture.look({:corrugated, round}, {0.013, 0.0, 0.0}, @front, 0.16), 0), 0.0, 1.0e-9
  end

  test "at a level with a bake, the surface goes into the maps: the panes, their light, and the relief of the ribs" do
    windows = %{"kind" => "windows", "pane" => [0.5, 0.6], "frame" => 0.1, "lit" => 0.5, "seed" => 2}

    data = %{
      "edits" => [
        %{
          "shape" => "box",
          "size" => [1.5, 0.1, 1.05],
          "at" => [0, 0, 1.05],
          "color" => "#8a8f94",
          "surface" => windows
        }
      ],
      "cells" => %{"far" => 0.05},
      "budget" => %{"far" => 300},
      "bake" => %{"far" => 256}
    }

    {part, %{"materials" => %{"paint" => m}}, _} = far(data)
    # (At a level with maps, no look at the points.)
    assert Enum.all?(part.shapes, &(&1.finish == nil))
    {"image/png", png} = m["glow_image"]
    {w, _h, 3, rows} = World.PNG.decode(png)
    glows = for row <- Tuple.to_list(rows), x <- 0..(w - 1), do: :binary.at(row, 3 * x)
    # Some texels have the warm or the cold light of a pane; most have none.
    assert Enum.count(glows, &(&1 > 150)) > 100 and Enum.count(glows, &(&1 == 0)) > Enum.count(glows, &(&1 > 0))
    # A sheet with no lit pane has no glow image.
    {_, %{"materials" => %{"paint" => m}}, _} = far(put_in(data, ["edits", Access.at(0), "surface", "lit"], 0))
    refute Map.has_key?(m, "glow_image")
  end

  test "at a level with no bake, a surface gives its mean to the points; a pane of more than about two cells keeps its own points (R12)" do
    edit = fn pane, frame, lit ->
      %{
        "shape" => "box",
        "size" => [6, 0.5, 6],
        "at" => [0, 0, 6],
        "color" => "#8a8f94",
        "surface" => %{"kind" => "windows", "pane" => pane, "frame" => frame, "lit" => lit, "seed" => 5}
      }
    end

    glows = fn part -> for m <- part.shapes, {_, _, g} <- m.finish, do: g end

    # Panes of 2.5 m, cells of 0.25 m: the points of a lit pane glow, the points of the frames and of the dark panes do not.
    big = %{"edits" => [edit.([2.5, 2.5], 0.5, 0.5)], "cells" => %{"far" => 0.25}, "budget" => %{"far" => 50_000}}
    {part, _, _} = far(big)
    assert Enum.count(glows.(part), &(&1 >= 200)) > 50 and Enum.count(glows.(part), &(&1 == 0)) > 50

    # Small panes in a budget of few faces: each point has the mean of the panes, and the sheet stays a box.
    small = %{"edits" => [edit.([0.3, 0.4], 0.1, 0.5)], "cells" => %{"far" => 0.25}, "budget" => %{"far" => 300}}
    {part, _, _} = far(small)
    assert triangles(part) <= 300

    front =
      for m <- part.shapes,
          {{x, y, z}, {_, _, g}} <- Enum.zip(m.points, m.finish),
          y > 0.49 and abs(x) < 5.5 and z > 0.5 and z < 11.5,
          do: g

    assert front != [] and Enum.all?(front, &(&1 > 0 and &1 < 0.9 * 255))
    points = for m <- part.shapes, p <- m.points, do: p

    assert Enum.all?(points, fn {x, y, z} ->
             abs(abs(x) - 6) < 0.05 or abs(abs(y) - 0.5) < 0.05 or z < 0.05 or z > 11.95
           end)

    # The flat look: each face has the mean color of its middle.
    {flat, _, _} = far(Map.put(small, "look", "flat"))
    assert Enum.all?(flat.shapes, &(&1.colors != nil))
  end

  test "the field: the edits of a level with no maps, the color and the finish of their look, the glow of the edits alone" do
    windows = Texture.made("windows", %{"pane" => [1.0, 1.0], "frame" => 0.5, "lit" => 1.0})
    box = SDF.edit(:box, {3.0, 0.5, 3.0}, frame: Frame.identity(), color: {138, 143, 148}, surface: {windows, 1.0})
    lamp = SDF.edit(:ball, {0.2}, frame: Frame.move({5.0, 0.0, 0.0}), glow: 0.4)
    refute SDF.made?([box, lamp])
    [made, ^lamp] = SDF.on_points([box, lamp], 0.1)
    assert SDF.made?([made]) and made.id != box.id
    assert {{:windows, %{cell: 0.1}}, 1.0} = made.surface

    # A pane (its middle at 0.75 m across and up), and a frame.
    pane = {0.75, 0.5, 0.75}
    assert_in_delta elem(SDF.finish([made, lamp], pane), 2), 0.9, 1.0e-9
    assert SDF.finish([box, lamp], pane) |> elem(2) == 0.0
    assert SDF.light([made, lamp], pane) == 0.0
    assert SDF.color([made], pane) in [{255, 208, 138}, {214, 228, 255}]
    assert SDF.color([made], {0.0, 0.5, 0.75}) == SDF.color([box], {0.0, 0.5, 0.75})
    # The mean over a square of 3 m: the mean of the panes.
    assert_in_delta elem(SDF.finish([made], pane, %{}, 3.0), 2), 0.9 * 1 / 2.25, 1.0e-6
    refute SDF.color([made], pane, 1.0, 3.0) in [{255, 208, 138}, {214, 228, 255}]
    assert SDF.finished?([made]) and not SDF.finished?([box])

    # The square of each point: a third of the area of its faces; of each face, its own area.
    mesh = Mesh.new([{0.0, 0.0, 0.0}, {2.0, 0.0, 0.0}, {0.0, 2.0, 0.0}, {9.0, 9.0, 9.0}], [[0, 1, 2]], :paint)
    {points, faces} = Finish.sizes(mesh.points, mesh.faces)
    assert_in_delta elem(points, 0), :math.sqrt(2 / 3), 1.0e-9
    assert elem(points, 3) == 0.0 and elem(faces, 0) == :math.sqrt(2.0)
  end

  test "a tower of 40 storeys with 30 windows on each side: some edits and one surface on each, and its far level shows the lit windows (R13)" do
    {part, %{"materials" => %{"paint" => m}}, _} = far(tower(%{"far" => 512}), "tower")
    assert triangles(part) <= 200
    {"image/png", png} = m["glow_image"]
    {w, h, 3, rows} = World.PNG.decode(png)

    lit =
      for {row, y} <- Enum.with_index(Tuple.to_list(rows)),
          x <- 0..(w - 1),
          <<r, g, b>> = binary_part(row, 3 * x, 3),
          max(r, max(g, b)) > 60,
          into: MapSet.new(),
          do: {x, y}

    # About 35 % of the 4 800 panes of the tower (and the lit panes of the podium), each a piece of its own.
    assert pieces(lit) in 1_400..2_200
    assert MapSet.size(lit) < w * h / 10

    # With no bake at far: the mean of the panes at each point, and no point as bright as a lit pane.
    {part, _, _} = far(tower(%{}), "tower")
    glows = for s <- part.shapes, {_, _, g} <- s.finish, do: g
    assert Enum.any?(glows, &(&1 > 0)) and Enum.all?(glows, &(&1 < 100))
    assert h == 512
  end
end
