defmodule World.Plants do
  @moduledoc """
  The nursery of the world (`docs/world.md`, step P7; the trade
  `gardener`): a plant grows from the rules of its species, the numbers
  of `priv/plants/species.json`, each with its source.

  - `coconut/1`: the coconut palm (dừa): a trunk that leans and curves, a
    crown of fronds with their leaflets in a V, a bunch of nuts.
  - `banana/1`: the banana (chuối sứ): a pseudostem, leaves on their
    petioles that arch and droop, a bunch on its stalk.
  - `bamboo/1`: a clump of thorny bamboo (tre gai): culms that lean out
    and arch at the top, branches on the high nodes with sprays of
    leaves, a thicket of spiny branches low down.
  - `frangipani/1`: the frangipani (hoa sứ): a trunk that forks again and
    again (the model of Leeuwenberg), with thick blunt branches, a rosette
    of leaves at each end, and flowers in their season (`month`).

  A plant is an assembly of the kind `:plant`. Its levels of detail come
  from the level of the build (`World.Detail`): fewer sides, fewer
  stations, fewer leaves; far away a frond or a spray of leaves is one
  card. The options of each: `height` (m, in the range of the species)
  and `seed` (an integer: the small changes from plant to plant).
  """
  alias World.{Assembly, Detail, Part, Shape, Vec}

  @external_resource path = Path.join([__DIR__, "..", "..", "priv", "plants", "species.json"])
  @species path |> File.read!() |> JSON.decode!() |> Map.delete("note")

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  @up {0.0, 0.0, 1.0}
  @golden 137.5

  @doc "The models of the nursery, as `{name, fun}`."
  def models do
    [
      {"coconut_palm", fn -> coconut() end},
      {"banana_chuoi_su", fn -> banana() end},
      {"bamboo_tre_gai", fn -> bamboo() end},
      {"frangipani_hoa_su", fn -> frangipani() end}
    ]
  end

  @doc "The species of the nursery, by their names."
  def species, do: @species |> Map.keys() |> Enum.sort()

  @doc "A number of a species (the first value of its key)."
  def number(species, key), do: @species |> Map.fetch!(species) |> Map.fetch!(key) |> hd()

  defp sources(species) do
    sp = Map.fetch!(@species, species)
    for {k, [_, source]} <- Enum.sort(sp), k != "name", do: source
  end

  # The steps of a curve, the sides of a ring and the count of leaves at
  # each level.
  defp steps(near), do: max(round(near * %{near: 1.0, mid: 0.5, far: 0.25}[Detail.level()]), 2)
  defp sides(near), do: max(round(near * %{near: 1.0, mid: 0.6, far: 0.4}[Detail.level()]), 3)

  # A number from 0 to 1 for a seed and a key: the same each time.
  defp jitter(seed, key), do: :erlang.phash2({seed, key}, 10_000) / 10_000

  # --- The coconut palm ---------------------------------------------------------------------

  @doc """
  A coconut palm. The options: `height`, `seed`, `nuts` (true: a bunch of
  nuts under the crown, at the near level).
  """
  def coconut(opts \\ []) do
    h = Keyword.get(opts, :height, number("coconut", "height"))
    seed = Keyword.get(opts, :seed, 1)
    lean = number("coconut", "lean") * :math.pi() / 180
    {r, rb} = {number("coconut", "trunk") / 2, number("coconut", "base") / 2}

    # The spine leans at its base and curves up toward the crown.
    n = steps(12)
    spine = for i <- 0..n, t = i / n, do: {h * :math.tan(lean) * t * (1 - 0.35 * t), 0.0, h * t}
    radii = for i <- 0..n, t = i / n, do: r + (rb - r) * :math.exp(-t * h / 1.2)
    trunk = Part.new("trunk_coconut", :trunk, [tube(spine, radii, :bark)], [@o], sources: sources("coconut"))

    top = List.last(spine)
    count = if Detail.level() == :far, do: 10, else: number("coconut", "fronds")

    fronds =
      for i <- 0..(count - 1) do
        age = i / max(count - 1, 1)
        az = i * @golden + 360 * jitter(seed, {:az, i})
        e0 = 55 - 95 * age
        frond(top, az, e0, number("coconut", "frond") * (0.9 + 0.1 * jitter(seed, {:l, i})))
      end
      |> List.flatten()

    crown = Part.new("crown_coconut", :leaves, fronds, [@o])

    asm =
      Assembly.new("coconut_palm", trunk,
        root: "trunk_coconut",
        kind: :plant,
        sources: ["A coconut palm of the tall type (#{Map.fetch!(@species, "coconut")["name"]})."],
        extras: %{"species" => "coconut", "height" => h}
      )
      |> Assembly.add("crown_coconut", crown, at: "o", port: "o")

    if Keyword.get(opts, :nuts, true) and Detail.level() == :near do
      {tx, ty, tz} = top

      nuts =
        for k <- 0..(number("coconut", "nuts") - 1) do
          a = 2 * :math.pi() * k / 6 + if(k >= 6, do: 0.5, else: 0.0)
          rr = if k >= 6, do: 0.22, else: 0.32

          Shape.sphere(0.13, :leaf,
            sides: 8,
            rings: 5,
            frame: World.Frame.move({tx + rr * :math.cos(a), ty + rr * :math.sin(a), tz - 0.35 - 0.12 * div(k, 6)})
          )
        end

      Assembly.add(asm, "nuts_coconut", %{Part.new("nuts_coconut", :fruit, nuts, [@o]) | detail: :near},
        at: "o",
        port: "o"
      )
    else
      asm
    end
  end

  # A frond from the crown: a rachis that arches down, the petiole (a
  # quarter of it) bare, and the leaflets in a V on each side. At the near
  # level each leaflet is a strip of its own (24 on each side); at mid and
  # far the leaflets of a side are one card.
  defp frond(base, az, e0, len) do
    leaflet = number("coconut", "leaflet")

    width = fn s ->
      if s <= 0.25, do: 0.03, else: leaflet * (0.35 + 0.65 * :math.sin(:math.pi() * (s - 0.25) / 0.75))
    end

    if Detail.level() == :near do
      n = 24
      rachis = path(base, az, e0, -40, len, n)
      spine = Enum.map(rachis, &elem(&1, 0))

      leaflets =
        for {{c, d}, i} <- Enum.with_index(rachis), s = i / n, s > 0.25, side <- [-1, 1] do
          across = Vec.norm(Vec.cross(d, @up) |> nonzero(d))
          out = Vec.norm(Vec.add(Vec.add(Vec.scale(across, side * 0.8), Vec.scale(d, 0.45)), {0.0, 0.0, -0.45}))
          l = width.(s)
          tip = Vec.add(c, Vec.scale(out, l))

          ribbon(
            [{c, out, 0.012}, {Vec.add(c, Vec.scale(out, l / 2)), out, 0.022}, {tip, out, 0.004}],
            0.0,
            0.002,
            :leaf
          )
        end

      [Shape.sweep(spine, 0.025, :leaf, sides: 5) | leaflets]
    else
      n = steps(10)
      stations = for {{c, d}, i} <- Enum.with_index(path(base, az, e0, -40, len, n)), do: {c, d, width.(i / n)}
      [ribbon(stations, 0.5, 0.012, :leaf)]
    end
  end

  # --- The banana ----------------------------------------------------------------------------

  @doc "A banana plant. The options: `height`, `seed`, `bunch` (true)."
  def banana(opts \\ []) do
    h = Keyword.get(opts, :height, number("banana", "height"))
    seed = Keyword.get(opts, :seed, 1)
    r = number("banana", "trunk") / 2
    n = steps(6)
    spine = for i <- 0..n, do: {0.0, 0.0, h * i / n}
    radii = for i <- 0..n, do: r * (1 - 0.3 * i / n)
    stem = Part.new("pseudostem_banana", :trunk, [tube(spine, radii, :leaf)], [@o], sources: sources("banana"))
    top = List.last(spine)
    count = if Detail.level() == :far, do: 6, else: number("banana", "leaves")
    {blade, width, petiole} = {number("banana", "blade"), number("banana", "width"), number("banana", "petiole")}

    leaves =
      for i <- 0..(count - 1) do
        age = i / max(count - 1, 1)
        az = i * @golden + 360 * jitter(seed, {:az, i})
        e0 = 80 - 60 * age
        m = steps(8)

        stations =
          path(top, az, e0, -(70 + 60 * age), petiole + blade, m)
          |> Enum.with_index()
          |> Enum.map(fn {{c, d}, k} ->
            s = (k / m * (petiole + blade) - petiole) / blade
            w = if s <= 0, do: 0.02, else: width / 2 * :math.pow(:math.sin(:math.pi() * min(s, 1.0)), 0.5) + 0.01
            {c, d, w}
          end)

        ribbon(stations, 0.15, 0.006, :leaf)
      end

    asm =
      Assembly.new("banana_chuoi_su", stem,
        root: "pseudostem_banana",
        kind: :plant,
        sources: ["A banana plant (#{Map.fetch!(@species, "banana")["name"]})."],
        extras: %{"species" => "banana", "height" => h}
      )
      |> Assembly.add("leaves_banana", Part.new("leaves_banana", :leaves, leaves, [@o]), at: "o", port: "o")

    if Keyword.get(opts, :bunch, true) and Detail.level() == :near,
      do: Assembly.add(asm, "bunch_banana", bunch(top), at: "o", port: "o"),
      else: asm
  end

  # The bunch: a stalk that comes out of the top and hangs down, with its
  # hands of fruits on it, each a ring of fingers that point up.
  defp bunch({x, y, z}) do
    stalk = [{x, y, z}, {x + 0.45, y, z + 0.1}, {x + 0.85, y, z - 0.3}, {x + 0.95, y, z - 1.3}]
    hands = number("banana", "hands")

    fingers =
      for k <- 0..(hands - 1), j <- 0..11 do
        hz = z - 0.45 - 0.065 * k
        a = 2 * :math.pi() * j / 12
        r = 0.08 + 0.03 * :math.sin(:math.pi() * k / hands)
        c = {x + 0.92 + r * :math.cos(a), y + r * :math.sin(a), hz}
        tip = Vec.add(c, {0.06 * :math.cos(a), 0.06 * :math.sin(a), 0.09})
        Shape.sweep([c, tip], 0.017, :leaf, sides: 5)
      end

    %{Part.new("bunch_banana", :fruit, [Shape.sweep(stalk, 0.02, :leaf, sides: 6) | fingers], [@o]) | detail: :near}
  end

  # --- The bamboo ----------------------------------------------------------------------------

  @doc "A clump of bamboo. The options: `height`, `culms`, `seed`."
  def bamboo(opts \\ []) do
    h = Keyword.get(opts, :height, number("bamboo", "height"))
    seed = Keyword.get(opts, :seed, 1)
    count = Keyword.get(opts, :culms, number("bamboo", "culms"))
    radius = number("bamboo", "clump")
    r = number("bamboo", "trunk") / 2

    {culms, foliage} =
      for i <- 0..(count - 1), reduce: {[], []} do
        {cs, fs} ->
          rho = radius * :math.sqrt((i + 0.5) / count)
          th = (i * @golden + 30 * jitter(seed, {:th, i})) * :math.pi() / 180
          out = {:math.cos(th), :math.sin(th), 0.0}
          hi = h * (0.85 + 0.15 * jitter(seed, {:h, i}))
          base = Vec.scale(out, rho)
          spine = culm(base, out, hi, 3 + 12 * rho / radius)
          n = length(spine) - 1
          radii = for k <- 0..n, do: r * (1 - 0.75 * k / n)
          {[tube(spine, radii, :leaf, 8) | cs], fs ++ sprays(spine, out, seed, i)}
      end

    culm_part = Part.new("culms_bamboo", :trunk, Enum.reverse(culms), [@o], sources: sources("bamboo"))

    Assembly.new("bamboo_tre_gai", culm_part,
      root: "culms_bamboo",
      kind: :plant,
      sources: ["A clump of thorny bamboo (#{Map.fetch!(@species, "bamboo")["name"]})."],
      extras: %{"species" => "bamboo", "height" => h, "culms" => count}
    )
    |> Assembly.add("leaves_bamboo", Part.new("leaves_bamboo", :leaves, foliage, [@o]), at: "o", port: "o")
  end

  # The spine of a culm: up at the lean of its place in the clump, then
  # out more in its top third (the top of a culm arches).
  defp culm(base, out, h, lean) do
    n = steps(12)

    for k <- 0..n do
      t = k / n
      a = (lean + 25 * :math.pow(max(t - 0.6, 0) / 0.4, 2)) * :math.pi() / 180
      # The sum of the steps of the arc, as a closed form: near enough.
      Vec.add(base, Vec.add(Vec.scale(out, h * t * :math.sin(a)), {0.0, 0.0, h * t * :math.cos(a)}))
    end
  end

  # The branches of the high nodes with a spray of leaves at each end, and
  # the spiny branches low down (near only). Far away, a few big cards.
  defp sprays(spine, out, seed, i) do
    n = length(spine) - 1
    from = round(n * (1 - number("bamboo", "branches")))
    every = %{near: 1, mid: 2, far: 3}[Detail.level()]
    leaf = number("bamboo", "leaf")

    high =
      for k <- from..(n - 1)//every, side <- [1, -1] do
        c = Enum.at(spine, k)
        a = side * (50 + 60 * jitter(seed, {:b, i, k, side})) * :math.pi() / 180
        {ox, oy, _} = out
        dir = Vec.norm({ox * :math.cos(a) - oy * :math.sin(a), ox * :math.sin(a) + oy * :math.cos(a), 0.5})
        len = 1.8 * (1 - (k - from) / max(n - from, 1)) + 0.6
        tip = Vec.add(c, Vec.scale(dir, len))
        branch = if Detail.level() == :far, do: [], else: [Shape.sweep([c, tip], 0.008, :bamboo, sides: 4)]
        size = if Detail.level() == :far, do: 3.0, else: 1.0

        # The sprays of leaves along the branch: many leaves together, a
        # card of 5 by 2 leaves (an estimate).
        sprays =
          for f <- [0.45, 0.75, 1.0],
              do: card(Vec.add(c, Vec.scale(dir, len * f)), dir, leaf * 5 * size, leaf * 2 * size)

        branch ++ if(Detail.level() == :far, do: [List.last(sprays)], else: sprays)
      end

    low =
      if Detail.level() == :near do
        for k <- 1..3 do
          c = Enum.at(spine, k)
          a = (120 * k + 360 * jitter(seed, {:low, i, k})) * :math.pi() / 180
          tip = Vec.add(c, {0.8 * :math.cos(a), 0.8 * :math.sin(a), 0.05})
          Shape.sweep([c, tip], 0.006, :bamboo, sides: 4)
        end
      else
        []
      end

    List.flatten(high) ++ low
  end

  # A spray of leaves: a card that hangs from a point, along a direction.
  defp card(at, dir, len, width) do
    {dx, dy, _} = dir
    flat = Vec.norm({dx, dy, -0.6})
    stations = for k <- 0..2, do: {Vec.add(at, Vec.scale(flat, len * k / 2)), flat, width / 2}
    ribbon(stations, 0.3, 0.004, :leaf)
  end

  # --- The frangipani ------------------------------------------------------------------------

  @doc """
  A frangipani. The options: `height`, `seed`, `month` (1 to 12, 6 by
  default): the tree has no leaves in the months of its dry season, and
  flowers in the months of its flowering (near only).
  """
  def frangipani(opts \\ []) do
    h = Keyword.get(opts, :height, number("frangipani", "height"))
    seed = Keyword.get(opts, :seed, 1)
    month = Keyword.get(opts, :month, 6)
    r = number("frangipani", "trunk") / 2
    k = h / 4.5
    stem = 0.8 * k
    trunk = tube([{0.0, 0.0, 0.0}, {0.0, 0.0, stem}], [r, r * 0.85], :bark)

    # The forks: 3, 3, 2, 2 and 2 shoots, each shorter and thinner; the low
    # ones go out more, the high ones up (a dome).
    levels = [
      {3, 0.9, 0.08, 0.9},
      {3, 0.75, 0.06, 0.7},
      {2, 0.6, 0.048, 0.55},
      {2, 0.5, 0.038, 0.45},
      {2, 0.4, 0.03, 0.4}
    ]

    # At far, the last three forks are one shoot of their length: the dome
    # has its size with a quarter of the tips.
    levels = if Detail.level() == :far, do: Enum.take(levels, 2) ++ [{2, 1.5, 0.048, 0.5}], else: levels

    {branches, tips} =
      Enum.reduce(levels, {[], [{{0.0, 0.0, stem}, @up, 0.0}]}, fn {forks, len, rad, spread}, {bs, ends} ->
        next =
          for {{p, d, az}, j} <- Enum.with_index(ends), f <- 0..(forks - 1) do
            a = az + 360 * f / forks + 40 * jitter(seed, {:f, j, f, forks, len})
            dir = Vec.norm(Vec.add(Vec.scale(d, 0.6), Vec.scale(horizontal(a), spread)))
            dir = Vec.norm(Vec.add(dir, {0.0, 0.0, 0.35}))
            q = Vec.add(p, Vec.scale(dir, len * k))
            {tube([p, q], [rad * k, rad * k * 0.9], :bark, 6), {q, dir, a}}
          end

        {bs ++ Enum.map(next, &elem(&1, 0)), Enum.map(next, &elem(&1, 1))}
      end)

    wood = Part.new("wood_frangipani", :trunk, [trunk | branches], [@o], sources: sources("frangipani"))
    leafless = month in number("frangipani", "leafless")
    flowering = month in number("frangipani", "flowering")

    leaves = if leafless, do: [], else: Enum.flat_map(Enum.with_index(tips), fn {t, j} -> rosette(t, seed, j) end)

    asm =
      Assembly.new("frangipani_hoa_su", wood,
        root: "wood_frangipani",
        kind: :plant,
        sources: ["A frangipani (#{Map.fetch!(@species, "frangipani")["name"]}), in the month #{month}."],
        extras: %{"species" => "frangipani", "height" => h, "month" => month}
      )

    asm =
      if leaves == [],
        do: asm,
        else:
          Assembly.add(asm, "leaves_frangipani", Part.new("leaves_frangipani", :leaves, leaves, [@o]),
            at: "o",
            port: "o"
          )

    if flowering and Detail.level() == :near do
      flowers = Enum.flat_map(tips, &flowers/1)

      Assembly.add(
        asm,
        "flowers_frangipani",
        %{Part.new("flowers_frangipani", :flowers, flowers, [@o]) | detail: :near},
        at: "o",
        port: "o"
      )
    else
      asm
    end
  end

  defp horizontal(deg) do
    a = deg * :math.pi() / 180
    {:math.cos(a), :math.sin(a), 0.0}
  end

  # The leaves at the end of a branch, out and up around it.
  defp rosette({p, _d, _az}, seed, j) do
    count = %{near: 9, mid: 4, far: 1}[Detail.level()]
    len = number("frangipani", "leaf")

    for i <- 0..(count - 1) do
      az = 360 * i / count + 30 * jitter(seed, {:leaf, j, i})
      dir = Vec.norm(Vec.add(horizontal(az), {0.0, 0.0, 0.7}))
      m = steps(4)

      stations =
        for k <- 0..m do
          s = k / m
          droop = Vec.norm(Vec.add(dir, {0.0, 0.0, -0.7 * s}))
          {Vec.add(p, Vec.scale(droop, len * s)), droop, 0.035 * :math.sin(:math.pi() * min(0.08 + s, 0.98)) + 0.005}
        end

      ribbon(stations, 0.05, 0.003, :leaf)
    end
  end

  # A cluster of flowers over the end of a branch: 4 flowers of 5 petals,
  # white, with a yellow center.
  defp flowers({p, _d, az}) do
    size = number("frangipani", "flower")

    for f <- 0..3, petal <- 0..5 do
      c = Vec.add(p, Vec.add(Vec.scale(horizontal(az + 90 * f), 0.05), {0.0, 0.0, 0.1 + 0.02 * rem(f, 2)}))

      case petal do
        5 ->
          Shape.sphere(size * 0.12, :orange, sides: 5, rings: 3, frame: World.Frame.move(c))

        _ ->
          d = horizontal(az + 90 * f + 72 * petal)

          stations = [
            {c, d, 0.006},
            {Vec.add(c, Vec.scale(d, size * 0.3)), d, size * 0.15},
            {Vec.add(c, Vec.scale(d, size * 0.5)), d, 0.005}
          ]

          ribbon(stations, 0.0, 0.002, :white)
      end
    end
  end

  # --- The shapes ----------------------------------------------------------------------------

  # A tube along a spine, with a radius at each point (a trunk, a culm, a
  # branch): a loft of round sections.
  defp tube(spine, radii, material, near_sides \\ 10) do
    tangents = tangents(spine)

    sections =
      for {{c, t}, r} <- Enum.zip(Enum.zip(spine, tangents), radii) do
        u = Vec.perpendicular(t)
        {c, u, Vec.cross(t, u), r, r, 2}
      end

    Shape.loft(sections, material, sides: sides(near_sides))
  end

  defp tangents(points) do
    dirs = points |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> Vec.norm(Vec.sub(b, a)) end)
    Enum.zip_with([hd(dirs) | dirs], dirs ++ [List.last(dirs)], &Vec.norm(Vec.add(&1, &2)))
  end

  # The points and the directions of a path from a point: it starts at
  # the azimuth `az` and the elevation `e0` (degrees), and its elevation
  # changes by `de` along its length (an arch that bends down).
  defp path(base, az, e0, de, len, n) do
    {points, _} =
      Enum.map_reduce(0..n, base, fn k, p ->
        e = (e0 + de * k / n) * :math.pi() / 180
        d = Vec.add(Vec.scale(horizontal(az), :math.cos(e)), {0.0, 0.0, :math.sin(e)})
        {{p, d}, Vec.add(p, Vec.scale(d, len / n))}
      end)

    points
  end

  # A thin blade along stations `{center, direction, half width}`: at each
  # station a ring of four points across the direction: the left edge,
  # the top of the midrib, the right edge, the bottom of the midrib. The
  # edges hang down by `v` times the half width (a V), and the midrib is
  # `t` thick.
  defp ribbon(stations, v, t, material) do
    rings =
      for {c, d, w} <- stations do
        across = Vec.norm(Vec.cross(d, @up) |> nonzero(d))
        normal = Vec.norm(Vec.cross(across, d))
        drop = Vec.scale(normal, -v * w)

        [
          Vec.add(c, Vec.add(Vec.scale(across, -w), drop)),
          Vec.add(c, Vec.scale(normal, t)),
          Vec.add(c, Vec.add(Vec.scale(across, w), drop)),
          Vec.sub(c, Vec.scale(normal, t))
        ]
      end

    Shape.rings(rings, material)
  end

  # A direction across a path that goes straight up or down.
  defp nonzero(v, d), do: if(Vec.len(v) < 1.0e-6, do: Vec.perpendicular(d), else: v)
end
