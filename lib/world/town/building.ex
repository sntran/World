defmodule World.Town.Building do
  @moduledoc """
  A building of a town from a request of a few words
  (`docs/plans/0018-quang-trung-street.md`, section 11): a hotel, an
  office, a villa. A house of a street in a row is `World.Town.House`.

  The request gives the plan (its corners, or the size of a rectangle),
  the storeys, the colors, and a list of fronts: a part of one side of
  the plan with a style (`windows`, `loggias`, `glass` or `plain`) and a
  count of equal bays. It can give a cornice, a roof (`flat` behind a
  parapet, or `tiles` with slopes and gables), porches, and a name in
  letters. `drawing/1` gives a model in parts, each part a sculpture of
  edits (`World.Skills.Sculpt`), from the tools of `World.Town.Wall`.

  The axes of a plan from a size: the front is side 1, on the line of
  y = 0, and the street is at +y. Side `k` goes from corner `k` to the
  next one. The corners go counterclockwise (seen from above), so the
  way `s` along a side goes from the left to the right for a person in
  front of it.
  """

  alias World.Town.Wall

  @colors %{
    "wall" => "#f1dc86",
    "trim" => "#e3aa6c",
    "band" => "#a9694f",
    "cornice" => "#f0e6c2",
    "glass" => "#55707c",
    "frame" => "#f4f1e4",
    "rail" => "#2f4a3c",
    "roof" => "#d8a544",
    "deck" => "#9a9d98",
    "ground" => "#8d8a80",
    "letters" => "#b3261e"
  }
  @styles ~w(plain windows loggias glass)
  @grounds ~w(piers windows blank)
  @rails ~w(cross bars none)
  @parts ~w(than mai chu nen)
  # (The path of a value at the start of the text of an error, as `fronts.2.bays: `.)
  @path ~r/^[a-z0-9_]+(\.[a-z0-9_]+)*: /

  @plaster %{"roughness" => 0.85, "surface" => %{"kind" => "plaster", "scale" => 0.04}}
  @pane %{"roughness" => 0.1, "metal" => 0.2}
  @iron %{"roughness" => 0.5, "metal" => 0.6}
  @white %{"roughness" => 0.6}

  # The strokes of each letter, in a box of 0.5 by 0.75.
  @letters %{
    "A" => [[[0, 0], [0.25, 0.75], [0.5, 0]], [[0.1, 0.28], [0.4, 0.28]]],
    "B" => [
      [[0, 0], [0, 0.75], [0.32, 0.75], [0.45, 0.65], [0.45, 0.5], [0.32, 0.4], [0, 0.4]],
      [[0.32, 0.4], [0.5, 0.28], [0.5, 0.12], [0.35, 0], [0, 0]]
    ],
    "C" => [[[0.5, 0.62], [0.35, 0.75], [0.14, 0.72], [0, 0.5], [0, 0.25], [0.14, 0.03], [0.35, 0], [0.5, 0.13]]],
    "D" => [[[0, 0], [0, 0.75], [0.3, 0.75], [0.5, 0.5], [0.5, 0.25], [0.3, 0], [0, 0]]],
    "E" => [[[0.5, 0.75], [0, 0.75], [0, 0], [0.5, 0]], [[0, 0.38], [0.4, 0.38]]],
    "F" => [[[0.5, 0.75], [0, 0.75], [0, 0]], [[0, 0.38], [0.4, 0.38]]],
    "G" => [
      [[0.5, 0.65], [0.35, 0.75], [0.12, 0.7], [0, 0.4], [0.12, 0.05], [0.38, 0], [0.5, 0.15], [0.5, 0.35], [0.3, 0.35]]
    ],
    "H" => [[[0, 0], [0, 0.75]], [[0.5, 0], [0.5, 0.75]], [[0, 0.38], [0.5, 0.38]]],
    "I" => [[[0.25, 0], [0.25, 0.75]]],
    "J" => [[[0.4, 0.75], [0.4, 0.15], [0.28, 0], [0.12, 0], [0, 0.15]]],
    "K" => [[[0, 0], [0, 0.75]], [[0.5, 0.75], [0, 0.32]], [[0.18, 0.45], [0.5, 0]]],
    "L" => [[[0, 0.75], [0, 0], [0.5, 0]]],
    "M" => [[[0, 0], [0, 0.75], [0.25, 0.3], [0.5, 0.75], [0.5, 0]]],
    "N" => [[[0, 0], [0, 0.75], [0.5, 0], [0.5, 0.75]]],
    "O" => [
      [[0.25, 0], [0.05, 0.15], [0, 0.38], [0.05, 0.6], [0.25, 0.75], [0.45, 0.6], [0.5, 0.38], [0.45, 0.15], [0.25, 0]]
    ],
    "P" => [[[0, 0], [0, 0.75], [0.35, 0.75], [0.5, 0.62], [0.5, 0.48], [0.35, 0.36], [0, 0.36]]],
    "Q" => [
      [
        [0.25, 0],
        [0.05, 0.15],
        [0, 0.38],
        [0.05, 0.6],
        [0.25, 0.75],
        [0.45, 0.6],
        [0.5, 0.38],
        [0.45, 0.15],
        [0.25, 0]
      ],
      [[0.3, 0.2], [0.5, 0]]
    ],
    "R" => [[[0, 0], [0, 0.75], [0.35, 0.75], [0.48, 0.6], [0.35, 0.42], [0, 0.42]], [[0.25, 0.42], [0.5, 0]]],
    "S" => [
      [
        [0.48, 0.63],
        [0.34, 0.75],
        [0.14, 0.72],
        [0.03, 0.58],
        [0.12, 0.43],
        [0.38, 0.33],
        [0.48, 0.18],
        [0.36, 0.02],
        [0.15, 0],
        [0.02, 0.12]
      ]
    ],
    "T" => [[[0, 0.75], [0.5, 0.75]], [[0.25, 0.75], [0.25, 0]]],
    "U" => [[[0, 0.75], [0, 0.2], [0.12, 0.02], [0.38, 0.02], [0.5, 0.2], [0.5, 0.75]]],
    "V" => [[[0, 0.75], [0.25, 0], [0.5, 0.75]]],
    "W" => [[[0, 0.75], [0.12, 0], [0.25, 0.5], [0.38, 0], [0.5, 0.75]]],
    "X" => [[[0, 0], [0.5, 0.75]], [[0, 0.75], [0.5, 0]]],
    "Y" => [[[0, 0.75], [0.25, 0.38], [0.5, 0.75]], [[0.25, 0.38], [0.25, 0]]],
    "Z" => [[[0, 0.75], [0.5, 0.75], [0, 0], [0.5, 0]]]
  }

  @doc "The styles of a front."
  def styles, do: @styles

  @doc "The colors of a building, each with its value when the request has none."
  def colors, do: @colors

  # --- The request ----------------------------------------------------------------

  @doc """
  The request with each choice made. A key that has a value keeps it.
  A value that is not possible raises an `ArgumentError`.

    * `name`: the name of the model (small letters, digits and `_`).
    * `sources`: lines of text for the sources of the model.
    * `plan`: the corners `[x, y]` (m), counterclockwise. Or `size`:
      `[long, deep]`, a rectangle with its front (side 1) on y = 0.
    * `storeys` (1 to 12), `ground` (the height of the ground storey to
      its lintel, m), `band` (the band between the ground storey and the
      first floor, m) and `storey` (from a floor to the next one, m).
    * `colors`: a value for a color of `colors/0`.
    * `fronts`: a list. Each front has `side`, `style` (`styles/0`),
      `from` and `to` (m along the side), `inset` (from its two ends to
      its bays), `bays`, `ground` (`piers`, `windows` or `blank`), `out`
      (the part stands out by this, m), `paint` (a color for the part
      from the ground storey up), `band` (true: the band has its color;
      a front of loggias has its bands with no word),
      `window` (`[wide, high]`), `sill`, `bars`, `places` (the middle of
      each window, m along the side, in the place of equal bays),
      `ledges`, `pilasters`, `pilaster` (its width), `deep` (of a
      loggia), `rail` (`cross`, `bars` or `none`), `pitch` (of the
      grid of a front of glass), `balcony` (a balcony at each floor
      over the ground storey stands out by this, m; 0: none) and `round`
      (`[left, right]`: the radius of a quarter of a circle at each
      front corner of a balcony; `[balcony, balcony]` gives round
      ends) and `storeys` (`[first, last]`: the front is on these storeys
      only; 1 is the ground storey).
    * `cornice`: `high` (0: none) and `out`.
    * `roof`: `kind` (`flat` or `tiles`), `parapet` (of a flat roof),
      and for tiles on a plan of four square corners `high`, `inset`
      (from the edge of the cornice; less than 0: the roof hangs over
      it) and `gables` (the sides with a gable; each other end has a
      slope).
    * `porches`: a list. Each has `side`, `at` (its middle, m along the
      side), `wide`, `deep`, `high`, `columns`, `steps`, `door`
      (`[wide, high]`, or nil), `board` (a color, or nil), `terrace`
      (true: a rail of iron round its top), `round` (`[left, right]`:
      the radius of a quarter of a circle at each front corner of the
      slab) and `fascia` (the height of a band round its front, m; 0:
      none).
    * `letters`: a list. Each has `side`, `at` (the middle of the text),
      `z`, `high`, `wide` (the width of a letter: 2/3 of `high` by
      default, from a quarter of `high` to two times `high`), `text` (A
      to Z and spaces) and `out` (from the wall or the cornice behind
      it; from the edge of the cornice when it stands on its top). In
      place of `wide`, `long` gives the length of the line (m): the
      full request has the `wide` that it gives.
    * `blocks`: a list of parts of the plan with their own storeys (a
      tower over the building, a lower wing, a storey set back behind a
      terrace). Each has `plan` (its corners, counterclockwise),
      `storeys`, `parapet` (of its flat roof; the parapet of the roof of
      the building by default) and `fronts` (on its own sides). Its
      walls go from the ground to the top of its parapet, with its deck
      behind it.
    * `apron` (the ground round the plan, m), `age` (0 to 1), and
      `more`: edits for a part (`than`: the body, `mai`: the roof,
      `chu`: the letters, `nen`: the ground), for a thing that the
      rules do not have.
  """
  def spec(opts \\ %{}) do
    need(is_map(opts), "the request of a building is a map")

    keys(
      opts,
      ~w(name sources plan size storeys ground band storey colors fronts cornice roof porches letters blocks apron age more),
      "building"
    )

    name = Map.get(opts, "name", "toa_nha")

    need(
      is_binary(name) and name =~ ~r/^[a-z][a-z0-9_]*$/,
      "name",
      "the name of a building has small letters, digits and _"
    )

    sources = Map.get(opts, "sources", [])

    need(
      is_list(sources) and Enum.all?(sources, &is_binary/1),
      "sources",
      "the sources of a building are lines of text"
    )

    plan = plan(opts)
    walls = walls(plan)
    storeys = Map.get(opts, "storeys", 3)
    need(is_integer(storeys) and storeys in 1..12, "storeys", "a building has from 1 to 12 storeys")
    given = Map.get(opts, "colors", %{})
    need(is_map(given), "colors", "the colors of a building are a map")

    within("colors", fn ->
      keys(given, Map.keys(@colors), "map of colors")
      Enum.each(given, fn {key, v} -> color(v, key) end)
    end)

    roof = within("roof", fn -> roof(Map.get(opts, "roof", %{}), plan, walls) end)
    more = Map.get(opts, "more", %{})

    need(
      is_map(more) and Enum.all?(more, fn {_, v} -> is_list(v) end),
      "more",
      "the key more is a map of lists of edits"
    )

    within("more", fn -> keys(more, @parts, "map of more edits") end)

    b = %{
      "name" => name,
      "sources" => sources,
      "plan" => plan,
      "storeys" => storeys,
      "ground" => number(opts, "ground", 3.0, 2.2, 8),
      "band" => number(opts, "band", 1.1, 0, 3),
      "storey" => number(opts, "storey", 3.5, 2.6, 6),
      "colors" => Map.merge(@colors, given),
      "cornice" => within("cornice", fn -> cornice(Map.get(opts, "cornice", %{}), roof) end),
      "roof" => roof,
      "apron" => number(opts, "apron", 0.6, 0, 10),
      "age" => number(opts, "age", 0.5, 0, 1),
      "more" => Map.merge(Map.new(@parts, &{&1, []}), more)
    }

    Map.merge(b, %{
      "fronts" => each(opts, "fronts", &front(&1, walls, storeys)),
      "porches" => each(opts, "porches", &porch(&1, walls, b)),
      "letters" => each(opts, "letters", &text(&1, walls)),
      "blocks" => each(opts, "blocks", &block(&1, roof))
    })
  end

  # A part of the plan with its own storeys: its walls go from the ground to the top of its own parapet.
  defp block(m, roof) do
    keys(m, ~w(plan storeys parapet fronts), "block")
    need(Map.has_key?(m, "plan"), "plan", "a block has its own plan: its corners [x, y], counterclockwise")
    plan = plan(m)
    storeys = Map.get(m, "storeys")
    need(is_integer(storeys) and storeys in 1..12, "storeys", "a block has from 1 to 12 storeys")

    %{
      "plan" => plan,
      "storeys" => storeys,
      "parapet" => number(m, "parapet", Map.get(roof, "parapet", 1.0), 0.3, 2),
      "fronts" => each(m, "fronts", &front(&1, walls(plan), storeys))
    }
  end

  defp plan(%{"plan" => points}) do
    need(
      is_list(points) and length(points) in 3..64 and
        Enum.all?(points, &match?([x, y] when is_number(x) and is_number(y), &1)),
      "plan",
      "the plan of a building is from 3 to 64 corners, each [x, y]"
    )

    plan = for [x, y] <- points, do: [r4(x * 1.0), r4(y * 1.0)]
    turns = for {[ax, ay], [bx, by]} <- sides(plan), do: ax * by - bx * ay
    need(Enum.sum(turns) > 0, "plan", "the corners of the plan of a building go counterclockwise, seen from above")

    need(
      Enum.all?(sides(plan), fn {a, b} -> a != b end),
      "plan",
      "two corners of the plan of a building are at the same place"
    )

    plan
  end

  defp plan(opts) do
    size = Map.get(opts, "size", [12.0, 10.0])

    need(
      match?([l, d] when is_number(l) and is_number(d) and l >= 3 and d >= 3 and l <= 200 and d <= 200, size),
      "size",
      "the size of a building is [long, deep], each from 3 m to 200 m"
    )

    [long, deep] = size
    [[r4(long * 1.0), 0.0], [0.0, 0.0], [0.0, r4(-deep * 1.0)], [r4(long * 1.0), r4(-deep * 1.0)]]
  end

  defp sides(plan), do: Enum.zip(plan, tl(plan) ++ [hd(plan)])
  defp walls(plan), do: for({a, b} <- sides(plan), do: Wall.new(a, b))

  defp roof(given, plan, walls) do
    need(is_map(given), "the roof of a building is a map")
    keys(given, ~w(kind parapet high inset gables), "roof")
    kind = Map.get(given, "kind", "flat")
    need(kind in ~w(flat tiles), "kind", "the roof of a building is flat or tiles")

    if kind == "flat" do
      keys(given, ~w(kind parapet), "flat roof")
      %{"kind" => "flat", "parapet" => number(given, "parapet", 1.0, 0.3, 2)}
    else
      keys(given, ~w(kind high inset gables), "roof of tiles")
      turns = for {w, v} <- sides(walls), do: abs(elem(w.t, 0) * elem(v.t, 0) + elem(w.t, 1) * elem(v.t, 1))
      need(length(plan) == 4 and Enum.all?(turns, &(&1 < 0.02)), "a roof of tiles is for a plan of four square corners")
      [w1, w2 | _] = walls
      {ridge, deep} = if w1.long >= w2.long, do: {w1, w2.long}, else: {w2, w1.long}
      gables = Map.get(given, "gables", [])
      ends = for {w, k} <- Enum.with_index(walls, 1), abs(dot(w.n, ridge.t)) > 0.5, do: k

      need(
        is_list(gables) and Enum.all?(gables, &(&1 in ends)),
        "gables",
        "a gable of this roof is at a short side: #{Enum.join(ends, " or ")}"
      )

      %{
        "kind" => "tiles",
        "high" => number(given, "high", Float.round(0.18 * deep, 1), 0.5, 12),
        "inset" => number(given, "inset", 1.0, -1, 3),
        "gables" => Enum.sort(gables)
      }
    end
  end

  defp cornice(given, roof) do
    need(is_map(given), "the cornice of a building is a map")
    keys(given, ~w(high out), "cornice")
    high = number(given, "high", if(roof["kind"] == "tiles", do: 1.2, else: 0.0), 0, 3)
    need(high == 0.0 or high >= 0.4, "high", "a cornice is 0.4 m high at the least (0: no cornice)")
    %{"high" => high, "out" => number(given, "out", 0.35, 0, 1)}
  end

  defp each(opts, key, f) do
    list = Map.get(opts, key, [])
    need(is_list(list) and Enum.all?(list, &is_map/1), key, "the #{key} of a building are a list of maps")
    for {m, i} <- Enum.with_index(list), do: within("#{key}.#{i}", fn -> f.(m) end)
  end

  defp side(m, walls, what) do
    k = Map.get(m, "side", 1)

    need(
      is_integer(k) and k >= 1 and k <= length(walls),
      "side",
      "the side of a #{what} is a number from 1 to #{length(walls)}"
    )

    {k, Enum.at(walls, k - 1)}
  end

  defp front(f, walls, storeys) do
    keys(
      f,
      ~w(side style from to inset bays ground out paint band window sill bars places ledges pilasters pilaster deep rail pitch balcony round storeys),
      "front"
    )

    {k, w} = side(f, walls, "front")
    style = Map.get(f, "style", "windows")
    need(style in @styles, "style", "the style of a front is one of #{Enum.join(@styles, ", ")}")
    range = Map.get(f, "storeys", [1, storeys])

    need(
      match?([a, z] when is_integer(a) and is_integer(z) and a >= 1 and a <= z and z <= storeys, range),
      "storeys",
      "the storeys of a front are [first, last], each from 1 to #{storeys} (1: the ground storey)"
    )

    need(
      style != "loggias" or List.last(range) >= 2,
      "style",
      "a front of loggias is for 2 storeys or more: its last storey is 2 or more"
    )

    long = r4(w.long)
    from = number(f, "from", 0.0, 0, long)
    to = number(f, "to", long, 0, long)
    inset = number(f, "inset", 0.0, 0, 5)
    run = to - from - 2 * inset
    need(run >= 1.5, "a front is 1.5 m long at the least between its insets")
    bays = Map.get(f, "bays", max(1, round(run / 4.0)))

    need(
      is_integer(bays) and bays >= 1 and run / bays >= 1.5,
      "bays",
      "a bay of a front is a whole count, each 1.5 m wide at the least"
    )

    ground = Map.get(f, "ground", if(style == "loggias", do: "piers", else: "windows"))
    need(ground in @grounds, "ground", "the ground storey of a front is one of #{Enum.join(@grounds, ", ")}")
    rail = Map.get(f, "rail", "cross")
    need(rail in @rails, "rail", "the rail of a front is one of #{Enum.join(@rails, ", ")}")
    window = Map.get(f, "window", [1.4, 1.5])

    need(
      match?([a, b] when is_number(a) and is_number(b) and a >= 0.3 and b >= 0.3, window),
      "window",
      "a window is [wide, high], each 0.3 m or more"
    )

    places = Map.get(f, "places")

    need(
      is_nil(places) or
        (is_list(places) and places != [] and Enum.all?(places, &(is_number(&1) and &1 >= from and &1 <= to))),
      "places",
      "the places of the windows of a front are numbers between its two ends"
    )

    paint = Map.get(f, "paint")
    if paint, do: color(paint, "paint")
    flags = for key <- ~w(band ledges pilasters), into: %{}, do: {key, Map.get(f, key, false)}

    need(
      Enum.all?(flags, fn {_, v} -> is_boolean(v) end),
      "the keys band, ledges and pilasters of a front are true or false"
    )

    bars = Map.get(f, "bars", 1)
    need(is_integer(bars) and bars in 0..8, "bars", "a window has from 0 to 8 bars")
    balcony = number(f, "balcony", 0.0, 0, 4)
    need(balcony == 0.0 or balcony >= 0.5, "balcony", "a balcony is 0.5 m deep at the least (0: no balcony)")

    need(
      balcony > 0 or Enum.all?(List.wrap(Map.get(f, "round", 0)), &(&1 == 0)),
      "round",
      "the round ends are for a front with a balcony"
    )

    Map.merge(flags, %{
      "side" => k,
      "style" => style,
      "from" => from,
      "to" => to,
      "inset" => inset,
      "bays" => bays,
      "ground" => ground,
      "out" => number(f, "out", 0.0, 0, 3),
      "paint" => paint,
      "window" => Enum.map(window, &(&1 * 1.0)),
      "sill" => number(f, "sill", 0.95, 0, 2),
      "bars" => bars,
      "places" => places && Enum.map(places, &(&1 * 1.0)),
      "pilaster" => number(f, "pilaster", 0.75, 0.2, 1.4),
      "deep" => number(f, "deep", 1.5, 0.3, 3),
      "rail" => rail,
      "pitch" => number(f, "pitch", 0.8, 0.3, 4),
      "balcony" => balcony,
      "round" => round(f, balcony, run, "the balconies of a front"),
      "storeys" => range
    })
  end

  defp porch(p, walls, b) do
    keys(p, ~w(side at wide deep high columns steps door board terrace round fascia), "porch")
    {k, w} = side(p, walls, "porch")
    wide = number(p, "wide", 6.0, 1.5, 40)
    columns = Map.get(p, "columns", 2)
    need(is_integer(columns) and columns in 0..12, "columns", "a porch has from 0 to 12 columns")
    steps = Map.get(p, "steps", 2)
    need(is_integer(steps) and steps in 0..6, "steps", "a porch has from 0 to 6 steps")
    door = Map.get(p, "door", [2.6, 2.7])

    need(
      is_nil(door) or match?([a, c] when is_number(a) and is_number(c) and a >= 0.6 and c >= 1.8, door),
      "door",
      "the door of a porch is [wide, high], or nil"
    )

    board = Map.get(p, "board")
    if board, do: color(board, "board")
    terrace = Map.get(p, "terrace", false)
    need(is_boolean(terrace), "terrace", "the key terrace of a porch is true or false")

    deep = number(p, "deep", 3.0, 1, 12)

    %{
      "side" => k,
      "at" => number(p, "at", r4(w.long / 2), wide / 2, w.long - wide / 2),
      "wide" => wide,
      "deep" => deep,
      "high" => number(p, "high", r4(b["ground"] + 0.5), 2.4, 12),
      "columns" => columns,
      "steps" => steps,
      "door" => door && Enum.map(door, &(&1 * 1.0)),
      "board" => board,
      "terrace" => terrace,
      "round" => round(p, deep, wide, "a porch"),
      "fascia" => number(p, "fascia", 0.0, 0, 3)
    }
  end

  # The radius of the quarter of a circle at the left and at the right front corner of a slab `deep` and `wide`.
  defp round(map, deep, wide, what) do
    v = Map.get(map, "round", [0, 0])

    need(
      match?([l, r] when is_number(l) and is_number(r) and l >= 0 and r >= 0 and l <= deep and r <= deep, v) and
        Enum.sum(v) <= r4(wide),
      "round",
      "the round of #{what} is [left, right], each from 0 to #{r4(deep)} m, the two #{r4(wide)} m at the most"
    )

    Enum.map(v, &(&1 * 1.0))
  end

  defp text(t, walls) do
    keys(t, ~w(side at z high wide long text out), "line of letters")
    {k, w} = side(t, walls, "line of letters")
    text = Map.get(t, "text", "")

    need(
      is_binary(text) and text =~ ~r/^[A-Z ]{1,40}$/ and String.trim(text) != "",
      "text",
      "the text of a line of letters is from 1 to 40 letters from A to Z, with spaces"
    )

    high = number(t, "high", 0.75, 0.3, 3)
    {narrow, broad} = {r4(0.25 * high), r4(2 * high)}

    # (A line of n letters is 1.7 n - 0.7 letters wide: after each letter, a space of 0.7 of its width.)
    wide =
      if Map.has_key?(t, "long") do
        long = number(t, "long", 0, 0.1, 200)
        wide = r4(long / (1.7 * String.length(text) - 0.7))

        need(
          wide >= narrow and wide <= broad,
          "long",
          "a line of #{String.length(text)} letters #{r4(long)} m long has letters #{wide} m wide: " <>
            "a letter is from #{narrow} m to #{broad} m wide (a quarter of its height to two times its height)"
        )

        wide
      else
        number(t, "wide", r4(high / 1.5), narrow, broad)
      end

    %{
      "side" => k,
      "at" => number(t, "at", r4(w.long / 2), 0, w.long),
      "z" => number(t, "z", 3.0, 0, 80),
      "high" => high,
      "wide" => wide,
      "text" => text,
      "out" => number(t, "out", 0.12, 0, 5)
    }
  end

  defp number(map, key, default, lo, hi) do
    v = Map.get(map, key, default)
    need(is_number(v) and v >= lo and v <= hi, key, "the value of #{key} is a number from #{r4(lo)} to #{r4(hi)}")
    v * 1.0
  end

  defp color(v, key),
    do: need(is_binary(v) and v =~ ~r/^#[0-9a-f]{6}$/, key, "the color #{key} is as #a1b2c3 (small letters)")

  defp keys(map, known, what) do
    case Map.keys(map) -- known do
      [] -> :ok
      [key | _] -> raise(ArgumentError, "a #{what} has no key #{inspect(key)}: its keys are #{Enum.join(known, ", ")}")
    end
  end

  defp need(true, _text), do: :ok
  defp need(false, text), do: raise(ArgumentError, text)

  # A check of the value at the key `key`: its error starts with the path of the value.
  defp need(true, _key, _text), do: :ok
  defp need(false, key, text), do: raise(ArgumentError, "#{key}: #{text}")

  # The checks of a part of the request at `path` (for example `fronts.2`): the path of an error starts with it.
  defp within(path, fun) do
    fun.()
  rescue
    e in ArgumentError ->
      message = if e.message =~ @path, do: "#{path}.#{e.message}", else: "#{path}: #{e.message}"
      reraise ArgumentError, [message: message], __STACKTRACE__
  end

  # --- The heights ----------------------------------------------------------------

  @doc """
  The heights of a request (m, over the ground): `ground` (the lintel of
  the ground storey), `floors` (the floor of each storey over it),
  `opening` (of a loggia over its floor), `eaves` (the top of the
  walls) and `top` (the top of the cornice, or of the parapet).
  """
  def heights(request) do
    b = spec(request)

    over =
      if b["roof"]["kind"] == "flat", do: max(b["cornice"]["high"], b["roof"]["parapet"]), else: b["cornice"]["high"]

    levels(b, b["storeys"], over)
  end

  # The heights of a building or of a block of `storeys`, with `over` from the eaves to the top.
  defp levels(b, storeys, over) do
    g = b["ground"]
    floors = for k <- 1..(storeys - 1)//1, do: r4(g + b["band"] + (k - 1) * b["storey"])
    eaves = if floors == [], do: r4(g + max(b["band"], 0.6)), else: r4(List.last(floors) + b["storey"] - 0.3)

    %{
      "ground" => g,
      "floors" => floors,
      "opening" => r4(b["storey"] - 0.75),
      "eaves" => eaves,
      "top" => r4(eaves + over)
    }
  end

  # --- The drawing ----------------------------------------------------------------

  @doc """
  The drawing of the building of a request (`spec/1`): a model in parts,
  each a sculpture with its cells and its image. The body (`_than`) has
  the walls with their fronts, and the rails in a detail of the near
  level. The roof (`_mai`), the letters (`_chu`) and the ground (`_nen`)
  are parts of their own.
  """
  def drawing(request \\ %{}) do
    b = spec(request)
    h = heights(b)
    walls = walls(b["plan"])
    c = b["colors"]

    # Each block, with its heights and its walls.
    blocks = for k <- b["blocks"], do: {k, levels(b, k["storeys"], k["parapet"]), walls(k["plan"])}

    {fronts, rails} =
      pairs(
        for(f <- b["fronts"], do: front_edits(f, Enum.at(walls, f["side"] - 1), h, c)) ++
          for({k, hk, wk} <- blocks, f <- k["fronts"], do: front_edits(f, Enum.at(wk, f["side"] - 1), hk, c))
      )

    {porches, porch_rails} = pairs(for p <- b["porches"], do: porch_edits(p, Enum.at(walls, p["side"] - 1), c))

    # The masses from the lowest to the highest: a part that is higher fills the deck of a lower part under it.
    # The fronts come after all of them, so that their paints are on each wall.
    masses =
      [{h["top"], mass(b, h)} | for({k, hk, _} <- blocks, do: {hk["top"], mass(block_body(b, k), hk)})]
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(&elem(&1, 1))

    body = masses ++ fronts ++ porches ++ cornice_edits(b, h) ++ b["more"]["than"]
    rails = rails ++ porch_rails

    area =
      Enum.sum([
        Enum.sum(for w <- walls, do: w.long) * h["top"]
        | for({_, hk, wk} <- blocks, do: Enum.sum(for w <- wk, do: w.long) * hk["top"])
      ])

    {long, deep} = extent(b["plan"])
    floor = long * deep
    letters = Enum.flat_map(b["letters"], &letter_edits(&1, Enum.at(walls, &1["side"] - 1), b, h)) ++ b["more"]["chu"]
    fine = Enum.min([0.75 | for(t <- b["letters"], do: t["high"])])

    count = length(letters)

    # (Each part: its edits, its details, its cells, its budgets and the least sides of its images.)
    parts =
      [
        {"than", body, rails, [0.05, 0.1, 0.25],
         [budget(28 * area, 500, 60_000), budget(5 * area, 100, 10_000), budget(0.55 * area, 50, 1_200)],
         [2048, 1024, 256]},
        {"mai", roof_edits(b, h) ++ b["more"]["mai"], [], [0.08, 0.15, 0.3],
         [budget(3 * floor, 2_000, 8_000), budget(floor, 600, 2_000), budget(0.2 * floor, 150, 400)], [1024, 256, 128]},
        {"chu", letters, [], [r4(0.027 * fine), r4(0.04 * fine), r4(0.08 * fine)],
         [budget(150 * count, 1_000, 12_000), budget(40 * count, 400, 3_000), budget(12 * count, 100, 800)],
         [256, 128, 64]},
        {"nen", ground(b) ++ b["more"]["nen"], [], [0.06, 0.12, 0.3], [2_500, 700, 150], [512, 256, 128]}
      ]
      |> Enum.reject(fn {_, edits, _, _, _, _} -> edits == [] end)

    look = %{"dirt" => r4(0.15 + 0.4 * b["age"]), "wear" => r4(0.3 * b["age"])}
    levels = fn list -> Map.new(Enum.zip(~w(near mid far), list)) end

    nodes =
      for {{part, edits, details, cells, budget, bake}, i} <- Enum.with_index(parts, 1) do
        role = "part_0#{i}"

        data =
          Map.merge(look, %{
            "edits" => role(edits, role),
            "cells" => levels.(cells),
            "budget" => levels.(budget),
            "bake" => levels.(Enum.zip_with(budget, bake, &image/2))
          })

        data =
          if details == [],
            do: data,
            else:
              Map.put(data, "details", [
                %{
                  "edits" => role(details, role),
                  "cells" => %{"near" => 0.012},
                  "budget" => %{"near" => max(2000, length(details) * 60)},
                  "levels" => ["near"]
                }
              ])

        %{"name" => "#{b["name"]}_#{part}", "skill" => %{"sculpt" => data}}
      end

    %{
      "name" => b["name"],
      "kind" => "house",
      "sources" => b["sources"],
      "materials" =>
        Map.new(1..length(parts), &{"part_0#{&1}", %{"color" => "#ffffff", "roughness" => 0.85, "metalness" => 0.0}}),
      "extras" => %{"building" => b},
      "nodes" => nodes
    }
  end

  defp pairs(list), do: {Enum.flat_map(list, &elem(&1, 0)), Enum.flat_map(list, &elem(&1, 1))}
  defp role(edits, role), do: Enum.map(edits, &Map.put(&1, "material", role))

  # A budget of triangles: a round count between two limits.
  defp budget(v, lo, hi), do: v |> round() |> div(50) |> Kernel.*(50) |> max(lo) |> min(hi)

  # The side of the image of a part: the least side for its budget, and not smaller than `side`.
  defp image(budget, side),
    do: Enum.find([64, 128, 256, 512, 1024, 2048, 4096], &(&1 >= max(side, World.Sculpt.Bake.least(budget))))

  defp extent(plan) do
    {xs, ys} = {Enum.map(plan, &hd/1), Enum.map(plan, &List.last/1)}
    {Enum.max(xs) - Enum.min(xs), Enum.max(ys) - Enum.min(ys)}
  end

  # The walls from the ground to the eaves. With a flat roof, they go up to
  # the top of the parapet, and the roof behind the parapet is taken away.
  defp mass(%{"roof" => %{"kind" => "flat", "parapet" => p}} = b, h) do
    {eaves, c} = {h["eaves"], b["colors"]}

    [
      Wall.outline(b["plan"], eaves + p, [0, 0, (eaves + p) / 2], c["wall"], @plaster),
      Wall.outline(offset(b["plan"], -0.4), 2 * p, [0, 0, eaves + p], c["deck"], %{
        "mode" => "subtract",
        "roughness" => 0.95,
        "surface" => %{"kind" => "concrete", "scale" => 0.05}
      })
    ]
  end

  defp mass(b, h), do: [Wall.outline(b["plan"], h["eaves"], [0, 0, h["eaves"] / 2], b["colors"]["wall"], @plaster)]

  # A block as a building of its own plan, with a flat roof behind its parapet.
  defp block_body(b, k), do: %{b | "plan" => k["plan"], "roof" => %{"kind" => "flat", "parapet" => k["parapet"]}}

  defp cornice_edits(%{"cornice" => %{"high" => high}}, _h) when high == 0.0, do: []

  defp cornice_edits(%{"cornice" => %{"high" => high, "out" => out}} = b, h) do
    {eaves, c} = {h["eaves"], b["colors"]}

    [
      Wall.outline(offset(b["plan"], out), high - 0.3, [0, 0, eaves + (high - 0.3) / 2], c["cornice"], @plaster),
      Wall.outline(offset(b["plan"], out + 0.15), 0.3, [0, 0, eaves + high - 0.15], c["trim"], @plaster)
    ]
  end

  defp ground(%{"apron" => apron} = b) do
    [
      Wall.outline(offset(b["plan"], apron), 0.3, [0, 0, -0.15], b["colors"]["ground"], %{
        "roughness" => 0.95,
        "surface" => %{"kind" => "concrete", "scale" => 0.06}
      })
    ]
  end

  # A plan with each side moved out by `d` (in, when `d` is less than 0).
  defp offset(plan, d) do
    walls = walls(plan)

    for {[x, y], {before, w}} <- Enum.zip(plan, Enum.zip([List.last(walls) | walls], walls)) do
      {{ax, ay}, {bx, by}} = {before.n, w.n}
      k = d / (1 + ax * bx + ay * by)
      [x + k * (ax + bx), y + k * (ay + by)]
    end
  end

  defp dot({ax, ay}, {bx, by}), do: ax * bx + ay * by

  # --- A front ----------------------------------------------------------------------

  # The edits of a front, and the tubes of its rails.
  defp front_edits(f, wall, h, c) do
    h = storeys(h, f["storeys"])
    {s0, s1, foot, head, g} = {f["from"], f["to"], h["foot"], h["head"], h["ground"]}
    mid = (s0 + s1) / 2
    w = Wall.out(wall, f["out"])

    base =
      if(f["out"] > 0,
        do: [
          Wall.box(
            wall,
            mid,
            (foot + head) / 2,
            {s1 - s0, head - foot, f["out"] + 0.5},
            c["wall"],
            Map.put(@plaster, "out", (f["out"] - 0.5) / 2)
          )
        ],
        else: []
      ) ++
        if(f["paint"],
          do: [
            Wall.paint(w, mid, (max(g, foot) + head) / 2, {s1 - s0, head - max(g, foot)}, f["paint"], %{
              "roughness" => 0.8
            })
          ],
          else: []
        ) ++
        if(f["band"] and f["style"] != "loggias" and h["first"] == 1 and h["floors"] != [] and hd(h["floors"]) > g,
          do: [band(w, mid, s1 - s0, g, hd(h["floors"]), c["band"])],
          else: []
        )

    {edits, rails} = style(f["style"], w, {s0 + f["inset"], s1 - f["inset"]}, f, h, c)
    {slabs, balcony_rails} = balconies(f, w, {s0 + f["inset"], s1 - f["inset"]}, h, c)
    {base ++ List.flatten(edits) ++ slabs, List.flatten(rails) ++ balcony_rails}
  end

  # The heights of a front of the storeys `first` to `last` (1: the ground storey): the floors in them, `foot`
  # (the foot of the first storey) and `head` (the top of the last one: the eaves, or the next floor).
  defp storeys(h, [first, last]) do
    floors = h["floors"]

    Map.merge(h, %{
      "floors" => Enum.slice(floors, max(first, 2) - 2, max(last - max(first, 2) + 1, 0)),
      "first" => first,
      "foot" => if(first == 1, do: 0.0, else: Enum.at(floors, first - 2)),
      "head" => if(last == length(floors) + 1, do: h["eaves"], else: Enum.at(floors, last - 1))
    })
  end

  # A balcony at each floor over the ground storey, along the front between its insets: a slab 0.2 m thick with
  # its top at the floor, with square or round ends, and a rail of the front along its edge.
  defp balconies(%{"balcony" => out}, _w, _run, _h, _c) when out == 0, do: {[], []}

  defp balconies(f, w, {a, b}, h, c) do
    slab = {a, b, f["balcony"]}
    plan = slab_plan(w, slab, f["round"], 0.0)
    line = [{a + 0.06, 0.0} | front_line(slab, f["round"], 0.06)] ++ [{b - 0.06, 0.0}]

    {for(z <- h["floors"], do: Wall.outline(plan, 0.2, [0, 0, z - 0.1], c["trim"], @plaster)),
     List.flatten(for z <- h["floors"], do: line_rail(f["rail"], w, line, z, c["rail"]))}
  end

  # A rail of iron along a line of points `{along, out}` on a floor: two bars, and posts with a cross between two
  # posts (about each 1.2 m), or upright bars (each 12 cm).
  defp line_rail("none", _w, _line, _floor, _color), do: []

  defp line_rail(kind, w, line, floor, color) do
    {lo, hi} = {floor + 0.08, floor + 0.95}
    at = fn {s, o}, z -> Wall.at(w, s, z, o) end

    bars =
      for z <- [lo, hi], do: bar(Enum.map(line, &at.(&1, z)), color)

    fill =
      if kind == "cross" do
        posts = spread(line, max(1, round(long(line) / 1.2)))

        for(p <- posts, do: Wall.tube([at.(p, lo), at.(p, hi)], [0.02, 0.02], color, @iron)) ++
          for {p, q} <- Enum.zip(posts, tl(posts)), {z0, z1} <- [{lo, hi}, {hi, lo}] do
            Wall.tube([at.(p, z0), at.(q, z1)], [0.014, 0.014], color, @iron)
          end
      else
        for p <- spread(line, max(2, round(long(line) / 0.12))),
            do: Wall.tube([at.(p, lo), at.(p, hi)], [0.012, 0.012], color, @iron)
      end

    bars ++ fill
  end

  defp band(w, mid, wide, z0, z1, color),
    do: Wall.paint(w, mid, (z0 + z1) / 2, {wide, z1 - z0}, color, %{"raise" => 0.02, "roughness" => 0.8})

  defp style("plain", _w, _run, _f, _h, _c), do: {[], []}

  defp style("windows", w, {a, b}, f, h, c) do
    pitch = (b - a) / f["bays"]
    places = f["places"] || for i <- 0..(f["bays"] - 1), do: a + pitch * (i + 0.5)
    [wide, high] = f["window"]
    floors = if(f["ground"] == "blank" or h["first"] > 1, do: [], else: [0.0]) ++ h["floors"]

    windows =
      for s <- places,
          z <- floors,
          do: Wall.window(w, s, z + f["sill"] + high / 2, {wide, high}, c["glass"], c["frame"], f["bars"])

    ledges =
      for {z, k} <- Enum.with_index(h["floors"]), f["ledges"] do
        cool = min(Enum.at(places, rem(k, length(places))) + wide / 2 + 0.6, b - 0.5)
        top = z + f["sill"] - 0.2

        [
          Wall.box(w, (a + b) / 2, top - 0.07, {b - a, 0.14, 0.5}, c["frame"], Map.put(@plaster, "out", 0.25)),
          # (The box of an air conditioner on the ledge, with its grille.)
          Wall.box(w, cool, top + 0.28, {0.8, 0.56, 0.3}, "#dfe1dc", %{"out" => 0.3, "roughness" => 0.5}),
          Wall.paint(w, cool, top + 0.28, {0.45, 0.4}, "#7c8184", %{"out" => 0.3, "raise" => -0.005})
        ]
      end

    pilasters =
      for i <- 0..f["bays"], f["pilasters"] do
        Wall.box(
          w,
          a + pitch * i,
          (h["foot"] + h["head"]) / 2,
          {f["pilaster"], h["head"] - h["foot"], 0.5},
          c["trim"],
          Map.put(@plaster, "out", 0.12)
        )
      end

    {[windows, ledges, pilasters], []}
  end

  defp style("glass", w, {a, b}, f, h, c) do
    z1 = h["head"] - 0.3

    z0 =
      cond do
        h["first"] > 1 -> h["foot"] + 0.3
        f["ground"] == "blank" -> h["ground"] + 0.5
        true -> 0.3
      end

    z0 = min(z0, z1 - 0.5)
    {wide, high, mid} = {b - a, z1 - z0, (z0 + z1) / 2}
    {ups, rows} = {max(1, round(wide / f["pitch"])), max(1, round(high / f["pitch"]))}
    bar = %{"blend" => 0.006, "roughness" => 0.6}

    {[
       Wall.paint(w, (a + b) / 2, mid, {wide, high}, c["glass"], Map.put(@pane, "raise", -0.05)),
       for(i <- 1..(ups - 1)//1, do: Wall.paint(w, a + wide * i / ups, mid, {0.06, high}, c["frame"], bar)),
       for(i <- 1..(rows - 1)//1, do: Wall.paint(w, (a + b) / 2, z0 + high * i / rows, {wide, 0.06}, c["frame"], bar))
     ], []}
  end

  # A row of equal bays between pilasters: a loggia at each storey over
  # the ground storey, with a door of glass at its back and a rail.
  defp style("loggias", w, {a, b}, f, h, c) do
    {count, g, eaves, open} = {f["bays"], h["ground"], h["head"], h["opening"]}
    {pitch, mid} = {(b - a) / count, (a + b) / 2}
    wide = pitch - f["pilaster"]
    # (A front over the ground storey has no openings and no piers at the ground storey, and no band under its
    # first loggia: that band starts at its foot.)
    ground? = h["first"] == 1
    piers? = f["ground"] == "piers" and ground?
    below = [if(ground?, do: g, else: h["foot"]) | Enum.map(h["floors"], &(&1 + open))]

    # The fronts of the balconies, and the band under the cornice.
    bands =
      for({floor, z} <- Enum.zip(h["floors"], below), floor > z, do: band(w, mid, b - a, z, floor, c["band"])) ++
        [band(w, mid, b - a, List.last(below), eaves, c["trim"])]

    bays =
      for i <- 0..(count - 1), s = a + pitch * (i + 0.5) do
        [
          for(floor <- h["floors"], do: loggia(w, s, floor, wide, f["deep"], open, c)),
          if(ground?, do: ground_bay(f, w, s, pitch, g, c), else: [])
        ]
      end

    pilasters =
      for i <- 0..count, s = a + pitch * i do
        foot = if piers?, do: g, else: h["foot"]

        [
          Wall.box(
            w,
            s,
            (foot + eaves) / 2,
            {f["pilaster"], eaves - foot, 0.5},
            c["trim"],
            Map.put(@plaster, "out", 0.12)
          ),
          # (Three lines at the head of the pilaster, at each storey.)
          for floor <- h["floors"], k <- 0..2 do
            Wall.paint(w, s, floor + open - 0.25 - 0.22 * k, {f["pilaster"] + 0.05, 0.06}, shade(c["trim"], 0.88), %{
              "out" => 0.14,
              "raise" => -0.01
            })
          end,
          if piers? do
            [
              Wall.box(w, s, g / 2, {f["pilaster"] + 0.35, g, 0.6}, c["trim"], Map.put(@plaster, "out", 0.15)),
              Wall.box(w, s, g - 0.45, {f["pilaster"] + 0.55, 0.25, 0.8}, c["trim"], Map.put(@plaster, "out", 0.15)),
              Wall.box(w, s, g - 0.15, {f["pilaster"] + 0.75, 0.3, 1.0}, c["trim"], Map.put(@plaster, "out", 0.15))
            ]
          else
            []
          end
        ]
      end

    lintel =
      if piers?,
        do: [Wall.box(w, mid, g - 0.15, {b - a, 0.3, 0.5}, c["trim"], Map.put(@plaster, "out", 0.05))],
        else: []

    rails =
      for i <- 0..(count - 1),
          floor <- h["floors"],
          do: rail(f["rail"], w, a + pitch * (i + 0.5), wide, floor, c["rail"])

    {[bands, bays, pilasters, lintel], rails}
  end

  defp loggia(w, s, floor, wide, deep, open, c) do
    back = 0.03 - deep
    door = min(2.3, open - 0.2)
    at = s + min(0.5, max(0.0, wide / 2 - 0.75))

    [
      Wall.box(w, s, floor + open / 2, {wide, open, 2 * deep}, c["wall"], Map.put(@plaster, "mode", "subtract")),
      Wall.box(w, at, floor + door / 2, {1.3, door, 0.08}, c["frame"], Map.put(@white, "out", back)),
      Wall.box(w, at, floor + door / 2, {1.1, door - 0.2, 0.1}, c["glass"], Map.put(@pane, "out", back + 0.01)),
      Wall.box(w, at, floor + door / 2, {0.05, door - 0.2, 0.12}, c["frame"], Map.put(@white, "out", back + 0.02))
    ]
  end

  # The ground storey of a bay: an opening between two piers with a window at its back, or a window in the wall.
  defp ground_bay(%{"ground" => "piers"} = f, w, s, pitch, g, c) do
    high = g - 0.7
    wide = min(1.5, pitch - f["pilaster"] - 1.1)

    [
      Wall.box(
        w,
        s,
        0.2 + high / 2,
        {pitch - f["pilaster"] - 0.45, high, 1.6},
        c["wall"],
        Map.put(@plaster, "mode", "subtract")
      ),
      Wall.box(w, s, 0.25 + high / 2, {wide + 0.2, high - 0.5, 0.08}, c["frame"], Map.put(@white, "out", -0.78)),
      Wall.box(w, s, 0.25 + high / 2, {wide, high - 0.7, 0.1}, c["glass"], Map.put(@pane, "out", -0.76))
    ]
  end

  defp ground_bay(%{"ground" => "windows", "window" => [wide, high]} = f, w, s, _pitch, _g, c),
    do: Wall.window(w, s, f["sill"] + high / 2, {wide, high}, c["glass"], c["frame"], f["bars"])

  defp ground_bay(_f, _w, _s, _pitch, _g, _c), do: []

  # A rail of iron across an opening: two bars, and posts with a cross between them, or upright bars.
  defp rail("none", _w, _s, _wide, _floor, _color), do: []

  defp rail(kind, w, s, wide, floor, color) do
    {lo, hi, left} = {floor + 0.08, floor + 0.95, s - wide / 2}
    at = fn s, z -> Wall.at(w, s, z, -0.08) end
    bars = for z <- [lo, hi], do: Wall.tube([at.(left, z), at.(left + wide, z)], [0.022, 0.022], color, @iron)

    fill =
      if kind == "cross" do
        for k <- 0..4, s = left + wide * k / 4 do
          [
            Wall.tube([at.(s, lo), at.(s, hi)], [0.02, 0.02], color, @iron)
            | if(k < 4,
                do: [
                  Wall.tube([at.(s, lo), at.(s + wide / 4, hi)], [0.014, 0.014], color, @iron),
                  Wall.tube([at.(s, hi), at.(s + wide / 4, lo)], [0.014, 0.014], color, @iron)
                ],
                else: []
              )
          ]
        end
      else
        count = max(2, round(wide / 0.12))

        for k <- 0..count,
            s = left + wide * k / count,
            do: Wall.tube([at.(s, lo), at.(s, hi)], [0.012, 0.012], color, @iron)
      end

    [bars, fill]
  end

  # --- A porch ----------------------------------------------------------------------

  # A slab on columns in front of a door, with steps; a board on its
  # front, or a rail of iron round its top.
  defp porch_edits(p, w, c) do
    {s, wide, deep, high} = {p["at"], p["wide"], p["deep"], p["high"]}
    stone = %{"roughness" => 0.9, "surface" => %{"kind" => "concrete", "scale" => 0.03}}

    {s0, s1} = {s - wide / 2, s + wide / 2}
    curved? = p["round"] != [0.0, 0.0]

    # (On a curved front, the columns are at equal steps along the line 0.4 m in from the edge.)
    places =
      cond do
        p["columns"] == 0 -> []
        p["columns"] == 1 -> [{s, deep - 0.4}]
        curved? -> spread(front_line({s0, s1, deep}, p["round"], 0.4), p["columns"] - 1)
        true -> for i <- 0..(p["columns"] - 1), do: {s0 + 0.4 + (wide - 0.8) * i / (p["columns"] - 1), deep - 0.4}
      end

    columns =
      for {along, out} <- places do
        Wall.edit("cylinder", [0.2, r4((high - 0.3) / 2)], Wall.at(w, along, (high - 0.3) / 2, out), c["frame"], %{
          "roughness" => 0.7
        })
      end

    steps =
      for i <- 1..p["steps"]//1 do
        {rise, reach} = {0.15 * (p["steps"] - i + 1), 0.6 + 0.4 * (i - 1)}
        Wall.box(w, s, rise / 2, {wide + 0.4, rise, 2 * reach}, "#b9bbb6", Map.put(stone, "out", reach))
      end

    door =
      case p["door"] do
        nil -> []
        [dw, dh] -> Wall.window(w, s, 0.15 * p["steps"] + dh / 2, {dw, dh}, c["glass"], c["frame"], 3)
      end

    board =
      if p["board"],
        do: [
          Wall.box(w, s, high + 0.45, {wide * 0.66, 0.9, 0.18}, p["board"], %{"out" => deep - 0.2, "roughness" => 0.5})
        ],
        else: []

    rails =
      cond do
        not p["terrace"] ->
          []

        curved? ->
          line = [{s0 + 0.1, 0.3} | front_line({s0, s1, deep}, p["round"], 0.1)] ++ [{s1 - 0.1, 0.3}]
          posts = spread(front_line({s0, s1, deep}, p["round"], 0.1), max(2, round(wide / 0.6)))
          terrace_rail(w, line, posts, high, c["rail"])

        true ->
          line =
            for {along, out} <- [{-1, 0.3}, {-1, deep - 0.1}, {1, deep - 0.1}, {1, 0.3}],
                do: {s + along * wide / 2, out}

          count = max(2, round(wide / 0.6))
          terrace_rail(w, line, for(i <- 0..count, do: {s0 + wide * i / count, deep - 0.1}), high, c["rail"])
      end

    # A curved slab is the extrude of its plan; the trim on it reaches 0.1 m past its edge.
    slab =
      if curved? do
        [
          Wall.outline(slab_plan(w, {s0, s1, deep}, p["round"], 0.0), 0.3, [0, 0, high - 0.15], c["cornice"], @plaster),
          Wall.outline(
            slab_plan(w, {s0, s1, deep}, p["round"], -0.1),
            0.12,
            [0, 0, high + 0.02],
            c["trim"],
            @plaster
          )
        ]
      else
        [
          Wall.box(w, s, high - 0.15, {wide, 0.3, deep}, c["cornice"], Map.put(@plaster, "out", deep / 2)),
          Wall.box(w, s, high + 0.02, {wide + 0.2, 0.12, deep + 0.1}, c["trim"], Map.put(@plaster, "out", deep / 2))
        ]
      end

    # The fascia: a band 0.2 m thick round the front and the ends of the slab, from 0.1 m over its top down.
    fascia =
      if p["fascia"] > 0 do
        band = [{s0 - 0.1, 0.0} | front_line({s0, s1, deep}, p["round"], -0.1)] ++ [{s1 + 0.1, 0.0}]
        inside = [{s0 + 0.1, 0.0} | front_line({s0, s1, deep}, p["round"], 0.1)] ++ [{s1 - 0.1, 0.0}]
        plan = plan(w, band ++ Enum.reverse(inside))
        [Wall.outline(plan, p["fascia"], [0, 0, high + 0.1 - p["fascia"] / 2], c["trim"], @plaster)]
      else
        []
      end

    {slab ++ fascia ++ columns ++ steps ++ door ++ board, rails}
  end

  # The rail of iron round the terrace on a porch: two bars along the line (`{along, out}`), and a post at each
  # place.
  defp terrace_rail(w, line, posts, high, color) do
    {z0, z1} = {high + 0.2, high + 1.05}

    for(
      z <- [z0, z1],
      do: bar(for({s, o} <- line, do: Wall.at(w, s, z, o)), color)
    ) ++
      for {s, o} <- posts, do: Wall.tube([Wall.at(w, s, z0, o), Wall.at(w, s, z1, o)], [0.016, 0.016], color, @iron)
  end

  # A bar of iron through points (two points that are at the same place after their round are one).
  defp bar(points, color) do
    points = Enum.dedup(points)
    Wall.tube(points, List.duplicate(0.022, length(points)), color, @iron)
  end

  # --- A slab with round corners ------------------------------------------------------

  # The front of a slab out of a wall, from `s0` to `s1` along it and `deep` out of it, with a quarter of a circle
  # of the radius `left` and `right` at its two front corners: the points `{along, out}` from its left end to its
  # right end, `d` m in from the edge (out of it, when `d` is less than 0).
  defp front_line({s0, s1, deep}, [left, right], d) do
    {ml, mr} = {max(left, d), max(right, d)}

    corner = fn {cs, co}, r, from ->
      for i <- 0..8, a = from - :math.pi() / 16 * i, do: {cs + r * :math.cos(a), co + r * :math.sin(a)}
    end

    Enum.dedup(
      corner.({s0 + ml, deep - ml}, ml - d, :math.pi()) ++ corner.({s1 - mr, deep - mr}, mr - d, :math.pi() / 2)
    )
  end

  # The plan `[x, y]` of a slab with round corners, from the wall out, `d` m in from its edge.
  defp slab_plan(w, {s0, s1, _deep} = slab, round, d),
    do: plan(w, [{s0 + d, 0.0} | front_line(slab, round, d)] ++ [{s1 - d, 0.0}])

  defp plan(w, points), do: Enum.dedup(for({s, o} <- points, do: Enum.take(Wall.at(w, s, 0, o), 2)))

  # `count` + 1 places at equal steps along a line of points `{along, out}`, from its first point to its last.
  defp spread(points, count) do
    points = Enum.dedup(points)
    steps = for {a, b} <- Enum.zip(points, tl(points)), do: {a, b, long([a, b])}
    for i <- 0..count, do: place(steps, long(points) * i / count)
  end

  # The length of a line of points `{along, out}`.
  defp long(points),
    do:
      Enum.sum(
        for {{as, ao}, {bs, bo}} <- Enum.zip(points, tl(points)), do: :math.sqrt((bs - as) ** 2 + (bo - ao) ** 2)
      )

  defp place([{_, _, long} | [_ | _] = rest], at) when at > long, do: place(rest, at - long)

  defp place([{{as, ao}, {bs, bo}, long} | _], at) do
    k = min(at / long, 1.0)
    {as + (bs - as) * k, ao + (bo - ao) * k}
  end

  # --- The letters --------------------------------------------------------------------

  # A line of letters on a wall, each letter from tubes: in front of the
  # wall, in front of the cornice, or on the top of the cornice.
  defp letter_edits(t, w, b, h) do
    k = t["high"] / 0.75
    # (The scale along the line: the width of a letter is 0.5 in the box of its strokes. A letter of the width
    # by default keeps the scale of its height.)
    along = if t["wide"] == r4(t["high"] / 1.5), do: k, else: t["wide"] / 0.5

    out =
      cond do
        t["z"] >= h["top"] -> b["cornice"]["out"] - t["out"]
        t["z"] >= h["eaves"] -> b["cornice"]["out"] + t["out"]
        true -> t["out"]
      end

    chars = String.graphemes(t["text"])
    start = t["at"] - (0.85 * along * length(chars) - 0.35 * along) / 2

    for {ch, i} <- Enum.with_index(chars), line <- Map.get(@letters, ch, []) do
      points = for [x, z] <- line, do: Wall.at(w, start + 0.85 * along * i + x * along, t["z"] + z * k, out)
      Wall.tube(points, List.duplicate(0.08 * t["high"], length(points)), b["colors"]["letters"], %{"roughness" => 0.5})
    end
  end

  # --- The roof -----------------------------------------------------------------------

  defp roof_edits(%{"roof" => %{"kind" => "flat"}}, _h), do: []

  # A roof of tiles on a rectangle: a prism along the long sides, cut to a
  # slope at each end that has no gable.
  defp roof_edits(%{"roof" => roof, "plan" => plan} = b, h) do
    [w1, w2 | _] = walls = walls(plan)
    {ridge, cross} = if w1.long >= w2.long, do: {w1, w2}, else: {w2, w1}
    {{rx, ry}, c, high} = {ridge.t, b["colors"], roof["high"]}
    out = b["cornice"]["out"] - roof["inset"]
    {long, deep} = {ridge.long + 2 * out, cross.long + 2 * out}
    [cx, cy] = for i <- [0, 1], do: Enum.sum(Enum.map(plan, &Enum.at(&1, i))) / 4
    z = h["top"] - 0.05
    tiles = %{"roughness" => 0.7}
    along = %{"axis" => [r6(rx), r6(ry), 0], "up" => [0, 0, 1]}
    # (The ends of the ridge with a gable: 1 at the end to which the ridge goes, -1 at the other.)
    gables = for k <- roof["gables"], do: if(dot(Enum.at(walls, k - 1).n, ridge.t) > 0, do: 1, else: -1)

    # (The outline of the cut is in the axes of the edit: its first axis goes against the ridge.)
    edge = fn sign ->
      if -sign in gables,
        do: {sign * (long / 2 + 0.2), sign * (long / 2 + 0.2)},
        else: {sign * long / 2, sign * (long / 2 - deep / 2)}
    end

    {{left, left_top}, {right, right_top}} = {edge.(-1), edge.(1)}
    cut = Enum.dedup([[left, 0], [right, 0], [right_top, high], [left_top, high]])

    slopes =
      [Wall.outline([[-deep / 2, 0], [deep / 2, 0], [0, high]], long, [cx, cy, z], c["roof"], Map.merge(tiles, along))] ++
        if(length(gables) == 2,
          do: [],
          else: [
            Wall.outline(
              cut,
              deep + 3.0,
              [cx, cy, z],
              c["roof"],
              Map.merge(tiles, %{"axis" => [r6(-ry), r6(rx), 0], "up" => [0, 0, 1], "mode" => "crop"})
            )
          ]
        )

    # The wall of each gable, under the end of the roof.
    walls_of_gables =
      for e <- gables do
        at = [cx + rx * e * (long / 2 - 0.1), cy + ry * e * (long / 2 - 0.1), z]
        half = deep / 2 - 0.6

        Wall.outline(
          [[-half, 0], [half, 0], [0, high * half / (deep / 2) - 0.1]],
          0.3,
          at,
          c["wall"],
          Map.merge(@plaster, along)
        )
      end

    # The flat part behind the cornice, round the slopes (6 cm over the top of the cornice: not in its plane).
    flat =
      if roof["inset"] > 0,
        do: [Wall.outline(plan, 0.12, [0, 0, h["top"]], c["deck"], %{"roughness" => 0.9})],
        else: []

    lines = max(3, round(high / 0.3))

    # The rows of the tiles: thin dark lines.
    rows =
      for k <- 1..lines do
        Wall.edit(
          "box",
          [r4(long), r4(long), 0.012],
          [r4(cx), r4(cy), r4(z + high * k / (lines + 1))],
          shade(c["roof"], 0.85),
          %{
            "mode" => "paint",
            "raise" => -0.008,
            "blend" => 0.012
          }
        )
      end

    # (The walls of the gables are after the rows of the tiles: a paint is for the edits before it.)
    slopes ++ flat ++ rows ++ walls_of_gables
  end

  defp r4(v), do: Wall.r4(v)
  defp r6(v), do: Float.round(v * 1.0, 6) + 0.0

  # A color, darker by a part.
  defp shade("#" <> hex, part) do
    <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :mixed)
    "#" <> Base.encode16(<<round(r * part), round(g * part), round(b * part)>>, case: :lower)
  end
end
