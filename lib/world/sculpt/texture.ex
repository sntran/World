defmodule World.Sculpt.Texture do
  @moduledoc """
  The surfaces of the edits of a sculpture
  (`docs/plans/0012-a-world-of-sites.md`, D3): the grain of wood, the
  ridges of bark, the strips of a weave. A flat color with one roughness
  looks like plastic; a real thing has a small relief, and its color and
  its roughness change from place to place.

  A surface is a function of a place: `at/3` gives the relief, the
  change of the color and the change of the finish there. The place is
  in the axes of the edit, in units of the scale of the surface (the
  size of one mark: a ring of the wood, a strip of the weave). So the
  grain of a leg of a chair goes along the leg, and turns with it. Only
  the maps have a surface (`World.Sculpt.Bake`): the mesh does not
  change.

  The kinds:

  | Kind | What it is | One mark (the scale by default) |
  |---|---|---|
  | `wood` | Rings round an axis next to the z of the edit, and streaks along it. | A ring: 6 mm. |
  | `bark` | Ridges along the z of the edit, with dark cracks. | A ridge: 30 mm. |
  | `brushed` | Fine lines along the z of the edit: a metal from a mill. | A line: 2 mm. |
  | `cast` | Small bumps: a cast metal, a forged head. | A bump: 3 mm. |
  | `plaster` | Soft bumps and patches: a wall with plaster. | A bump: 10 mm. |
  | `concrete` | Patches, fine grains and some pits. | A patch: 20 mm. |
  | `fabric` | The threads of a cloth, over and under, on the side that the surface faces. | A thread: 2 mm. |
  | `weave` | Strips over and under, flat across the z of the edit and pressed to its shape: a basket. | A strip: 20 mm. |
  | `leather` | A net of fine creases. | A cell: 4 mm. |
  | `rubber` | A fine grain with no shine. | A grain: 3 mm. |
  | `leaves` | Clumps, light at their tops and dark between them. | A clump: 120 mm. |
  | `stone` | Bumps of three sizes and spots. | A bump: 50 mm. |
  | `rust` | Patches of rust on a metal: brown, rough, no metal there. | A patch: 30 mm. |
  | `hair` | Strands that go out and down from the z of the edit (the top of a head), in locks: each strand has its height and its tone, and some are light. | A strand: 1.5 mm, at 9 cm from the z. |

  | `palm` | Leaves of palm that go out and down from the z of the edit (a nón lá): 40 blades, each with its tone and its fibers, and a dark line between two blades. | A fiber: 1 mm, at 6 cm from the z. |

  The height of a strand of `hair` (`strand/1`) is also how far it
  stands out of a mass of hair: the alpha of the image of a sculpture
  with strands is from it (`World.Sculpt.Bake`).

  ## The surfaces of made things

  Three kinds are the surfaces of large made things (plan 0020, D8 to
  D10): the windows of a building, the plates of a hull and the sheets of
  a roof. Each has its data, with its sizes in metres (times the scale
  of the surface, 1 by default), in the axes of the edit, not along the
  long axis of a box:

  | Kind | What it is | The data (the default) |
  |---|---|---|
  | `windows` | Rows and columns of panes on each face that stands up (a face that faces z has none). A pane has the finish of glass (roughness 0.05, no metal) and is 2 cm in from its frame; the frame has the color and the finish of the edit. A lit pane has the color of its light and a glow of 0.9. | `pane` [width, height] ([1.2, 1.5]), `frame` (the width between two panes: one number, or [across, up]; 0.3), `lit` (the share of the lit panes, 0 to 1; 0), `seed` (1), `warm` (`#ffd08a`) and `cold` (`#d6e4ff`): the colors of the light. |
  | `panels` | Plates with dark seams in the plane that the face faces most, and rivets on the seams as an option. | `plate` [width, height] ([1.0, 0.5]), `seam` (the width of a seam: 0.006), `depth` (of a seam: 0.002), `rivets` (the step of the rivets on a seam, or none). |
  | `corrugated` | Ribs along the z of the edit (along its y on a face that faces z). | `profile` (`round`: a sine; `square`: flat tops with sides at 45 degrees and flat pans; `square`), `pitch` (0.25), `depth` (0.032) and `top` (the width of the flat top of a square rib: 0.03). |

  The panes go in rows from the middle of the edit. On a box, the panes
  fit each face: a face of 30 pitches has 30 whole panes. A pane is lit
  by a hash of the seed, the face, its row and its column, so the same
  edit has the same lit panes each time. Two of three lit panes have the
  warm light.

  The value of a place is the mean over a square of the size of the
  texel (`look/4`; at a level with no maps, the square of a point: a
  third of the area of its faces, two cells at least): a pane, a seam or
  a rib that is smaller than that is its mean (a frame and a pane
  together, a mean glow), not the value of the place that a texel
  happens to be at. Where the square is more than a quarter of the pitch
  of the panes, the texels or the points are too far apart to show the
  rows: the panes go to the mean of all of them (in full at half a pitch).
  """

  @kinds %{
    "wood" => {:wood, 0.006},
    "bark" => {:bark, 0.03},
    "brushed" => {:brushed, 0.002},
    "cast" => {:cast, 0.003},
    "plaster" => {:plaster, 0.01},
    "concrete" => {:concrete, 0.02},
    "fabric" => {:fabric, 0.002},
    "weave" => {:weave, 0.02},
    "leather" => {:leather, 0.004},
    "rubber" => {:rubber, 0.003},
    "leaves" => {:leaves, 0.12},
    "stone" => {:stone, 0.05},
    "rust" => {:rust, 0.03},
    "hair" => {:hair, 0.0015},
    "palm" => {:palm, 0.003}
  }

  # The color of rust (linear light is not needed: a mix of two colors of the image).
  @rust {120, 62, 30}

  # The surfaces of made things, and the default of each word of their data.
  @made %{
    "windows" => %{
      "pane" => [1.2, 1.5],
      "frame" => 0.3,
      "lit" => 0,
      "seed" => 1,
      "warm" => "#ffd08a",
      "cold" => "#d6e4ff"
    },
    "panels" => %{"plate" => [1.0, 0.5], "seam" => 0.006, "depth" => 0.002, "rivets" => nil},
    "corrugated" => %{"profile" => "square", "pitch" => 0.25, "depth" => 0.032, "top" => 0.03}
  }

  # The glass of a pane (the color of `glass_dark` of the palette), and its finish.
  @glass {39.0, 49.0, 61.0}
  @pane_finish {0.05, 0.0}
  # The glow of a lit pane, and how far a pane is in from its frame (m).
  @lit_glow 0.9
  @pane_in 0.02

  @doc "The names of the kinds."
  def kinds, do: (Map.keys(@kinds) ++ Map.keys(@made)) |> Enum.sort()

  @doc "The kinds of made things (`windows`, `panels`, `corrugated`)."
  def made_kinds, do: @made |> Map.keys() |> Enum.sort()

  @doc """
  The kind of a name (an atom) and its scale by default (m), or nil. A
  kind of a made thing is `{atom, data}`, with the default data, and a
  scale of 1.
  """
  def kind(name) when is_map_key(@made, name), do: {made(name, %{}), 1.0}
  def kind(name), do: @kinds[name]

  @doc """
  The kind of a made thing with its data (`"windows"` and a map of the
  words of its data, each word that is not there with its default), as
  `look/4` takes it: `{:windows, data}`. With `size` (the half sizes of a
  box, in units of the scale), the panes fit each face of the box.
  """
  def made(name, data, size \\ nil) do
    d = Map.merge(@made[name], Map.take(data, Map.keys(@made[name])))
    made(String.to_existing_atom(name), d, size, nil)
  end

  defp made(:windows, d, size, _) do
    [pw, ph] = Enum.map(d["pane"], &(&1 / 1))

    {fu, fv} =
      case d["frame"] do
        [a, b] -> {a / 1, b / 1}
        f -> {f / 1, f / 1}
      end

    {pu, pv} = {pw + fu, ph + fv}

    # (The frames at the middle of a box, or a pane at its middle: so its faces have whole panes.)
    phase =
      case size do
        {x, y, z} -> {fit(x, pu), fit(y, pu), fit(z, pv)}
        nil -> {0.0, 0.0, 0.0}
      end

    {:windows,
     %{
       pane: {pw, ph},
       frame: {fu, fv},
       phase: phase,
       lit: d["lit"] / 1,
       seed: d["seed"],
       warm: rgb(d["warm"]),
       cold: rgb(d["cold"])
     }}
  end

  defp made(:panels, d, _size, _) do
    [w, h] = Enum.map(d["plate"], &(&1 / 1))
    {:panels, %{plate: {w, h}, seam: d["seam"] / 1, depth: d["depth"] / 1, rivets: d["rivets"] && d["rivets"] / 1}}
  end

  defp made(:corrugated, d, _size, _) do
    {:corrugated,
     %{
       profile: String.to_existing_atom(d["profile"]),
       pitch: d["pitch"] / 1,
       depth: d["depth"] / 1,
       top: d["top"] / 1
     }}
  end

  # The place of the first frame on an axis of a box: 0 with an even count of whole pitches, half a pitch with an odd one.
  defp fit(half, pitch), do: if(rem(floor(2 * half / pitch + 1.0e-6), 2) == 0, do: 0.0, else: pitch / 2)

  defp rgb("#" <> hex) do
    <<r, g, b>> = Base.decode16!(hex, case: :mixed)
    {r / 1, g / 1, b / 1}
  end

  @doc """
  The checks of the data of a surface of a made thing: `[{path, message}]`.
  """
  def check(name, data, path) when is_map_key(@made, name) do
    words = Map.keys(@made[name]) ++ ["kind", "scale"]

    errors =
      for(k <- Map.keys(data) -- words, do: {"#{path}.#{k}", "is not a word of a surface #{name}"}) ++
        Enum.flat_map(Map.take(data, Map.keys(@made[name])), fn {k, v} -> word(name, k, v, "#{path}.#{k}") end)

    if errors == [], do: rib(name, Map.merge(@made[name], data), path), else: errors
  end

  defp word("windows", "pane", v, path), do: pair(v, path, 0.05, 50)

  defp word("windows", "frame", v, path) when is_number(v), do: number(v, path, 0.0, 50)
  defp word("windows", "frame", v, path), do: pair(v, path, 0.0, 50)
  defp word("windows", "lit", v, path), do: number(v, path, 0, 1)

  defp word("windows", "seed", v, path),
    do:
      if(is_integer(v) and v >= 0 and v < 4_294_967_296,
        do: [],
        else: [{path, "must be a whole number from 0 to 4294967295"}]
      )

  defp word("windows", k, v, path) when k in ~w(warm cold), do: color(v, path)
  defp word("panels", "plate", v, path), do: pair(v, path, 0.01, 50)
  defp word("panels", "seam", v, path), do: number(v, path, 0.0005, 0.5)
  defp word("panels", "depth", v, path), do: number(v, path, 0, 0.1)
  defp word("panels", "rivets", nil, _path), do: []
  defp word("panels", "rivets", v, path), do: number(v, path, 0.01, 2)

  defp word("corrugated", "profile", v, path),
    do: if(v in ~w(round square), do: [], else: [{path, "must be one of: round, square"}])

  defp word("corrugated", "pitch", v, path), do: number(v, path, 0.01, 2)
  defp word("corrugated", "depth", v, path), do: number(v, path, 0.001, 0.5)

  defp word("corrugated", "top", v, path), do: number(v, path, 0.001, 2)

  # A square rib: its top and its two sides of 45 degrees in one pitch.
  defp rib("corrugated", %{"profile" => "square", "pitch" => p, "depth" => d, "top" => t}, path) when t + 2 * d > p,
    do: [{"#{path}.top", "must be at most the pitch less two times the depth (#{Float.round((p - 2 * d) / 1, 4)} m)"}]

  defp rib(_name, _data, _path), do: []

  defp number(v, path, lo, hi),
    do: if(is_number(v) and v >= lo and v <= hi, do: [], else: [{path, "must be a number from #{lo} to #{hi}"}])

  defp pair([a, b], _path, lo, hi) when is_number(a) and is_number(b) and a >= lo and a <= hi and b >= lo and b <= hi,
    do: []

  defp pair(_v, path, lo, hi), do: [{path, "must be two numbers [width, height], each from #{lo} to #{hi}"}]

  defp color(v, path) do
    if is_binary(v) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, v), do: [], else: [{path, "must be a color #rrggbb"}]
  end

  @doc "A surface of a made thing gives light (`windows` with lit panes)."
  def glows?({{:windows, %{lit: lit}}, _scale}), do: lit > 0.0
  def glows?(_surface), do: false

  @doc """
  The surface of a made thing at the place `q` (in the axes of the edit,
  in units of the scale), where the surface faces `n` (in the axes of the
  edit), as the mean over a square of `size` (in units of the scale):
  `{height, tone, to}`.

  - `height`: the relief, in units of the scale (more is out).
  - `tone`: the color times this (1 for no change).
  - `to`: `{color, {roughness, metal, glow}, part}`, the part of the place
    that has that color and that finish (the glass of the panes), or nil.
  """
  def look({:windows, w}, {x, y, z}, {nx, ny, nz}, size) do
    if abs(nz) > 0.5 do
      {0.0, 1.0, nil}
    else
      # (The panes go across the face and up; the face is one of four sides.)
      {u, axis, face} = if abs(nx) >= abs(ny), do: {y, 1, {:x, nx > 0}}, else: {x, 0, {:y, ny > 0}}
      {{pw, ph}, {fu, fv}} = {w.pane, w.frame}
      {pu, pv} = {pw + fu, ph + fv}
      {su, sv} = {u - elem(w.phase, axis), z - elem(w.phase, 2)}
      size = max(size, 1.0e-6)
      {columns, rows} = {panes(su, size, pu, fu / 2, pw), panes(sv, size, pv, fv / 2, ph)}
      part = Enum.sum(Enum.map(columns, &elem(&1, 1))) * Enum.sum(Enum.map(rows, &elem(&1, 1))) / (size * size)
      {on, light} = light(w, face, columns, rows)
      # (A square of more than a quarter of a pitch cannot show the rows: the points or the texels of
      # that size are too far apart. Then the mean of all the panes, in full at half a pitch.)
      mean = min(max(4 * max(size / pu, size / pv) - 1, 0.0), 1.0)
      part = part + (pw * ph / (pu * pv) - part) * mean
      {on, light} = {on + (w.lit - on) * mean, mix3(light, mix3(w.cold, w.warm, 2 / 3), mean)}
      glass = mix3(@glass, light, on)
      {rough, metal} = @pane_finish
      {0.0 - @pane_in * part, 1.0, {glass, {rough, metal, @lit_glow * on}, part}}
    end
  end

  def look({:panels, k}, q, n, size) do
    {a, b} = across(q, n)
    {w, h} = k.plate
    sw = k.seam
    {sa, sb} = {band(a, size, w, -sw / 2, sw), band(b, size, h, -sw / 2, sw)}
    seam = 1.0 - (1.0 - sa) * (1.0 - sb)
    rivet = if k.rivets, do: rivets(a, b, k, size), else: 0.0
    {-k.depth * seam + 0.003 * rivet, 1.0 - 0.4 * seam + 0.08 * rivet, nil}
  end

  def look({:corrugated, c}, {x, y, _z}, {nx, ny, nz}, size) do
    # (Ribs along z on a face that stands up, along y on a face that faces z.)
    s = if abs(nx) > abs(ny) and abs(nx) >= abs(nz), do: y, else: x
    {lo, hi} = {s - size / 2, s + size / 2}

    h =
      if size > 1.0e-9,
        do: (rib_area(c, hi) - rib_area(c, lo)) / size,
        else: rib(c, s)

    # (The mean height of the sheet is its surface.)
    {h - rib_area(c, c.pitch) / c.pitch, 1.0, nil}
  end

  @doc """
  The color and the finish of a place with the look of a made thing
  (`look/4`): `{color, finish}` (the color 0 to 255, not rounded).
  """
  def apply({_height, tone, to}, {r, g, b}, {rough, metal, glow}) do
    {r, g, b} = {r * tone, g * tone, b * tone}

    case to do
      nil ->
        {{r, g, b}, {rough, metal, glow}}

      {{tr, tg, tb}, {fr, fm, fg}, part} ->
        {{r + (tr - r) * part, g + (tg - g) * part, b + (tb - b) * part},
         {rough + (fr - rough) * part, metal + (fm - metal) * part, glow + (fg - glow) * part}}
    end
  end

  # The panes in a square of `size` round `s` on one axis: `[{index,
  # length}]`, each pane (from k * pitch + from, `width` long) with the
  # length of it in the square. (Over 8 panes: their sum only.)
  defp panes(s, size, pitch, from, width) do
    {a, b} = {s - size / 2, s + size / 2}
    {first, last} = {floor((a - from) / pitch), floor((b - from) / pitch)}

    if last - first > 8 do
      [{nil, size * band(s, size, pitch, from, width)}]
    else
      for k <- first..last,
          len = min(b, k * pitch + from + width) - max(a, k * pitch + from),
          len > 0.0,
          do: {k, len}
    end
  end

  # The share of the light in the panes of a square, by their areas, and
  # the mean color of their light: the mean of all the panes when the
  # square has many.
  defp light(w, face, columns, rows) do
    mean = mix3(w.cold, w.warm, 2 / 3)

    if Enum.any?(columns ++ rows, &(elem(&1, 0) == nil)) do
      {w.lit, mean}
    else
      {area, lit, {r, g, b}} =
        for {i, lu} <- columns, {j, lv} <- rows, reduce: {0.0, 0.0, {0.0, 0.0, 0.0}} do
          {area, lit, {r, g, b}} ->
            a = lu * lv

            if :erlang.phash2({w.seed, face, i, j}, 1_000_000) < w.lit * 1_000_000 do
              {cr, cg, cb} = if :erlang.phash2({w.seed, face, i, j, :warm}, 3) < 2, do: w.warm, else: w.cold
              {area + a, lit + a, {r + a * cr, g + a * cg, b + a * cb}}
            else
              {area + a, lit, {r, g, b}}
            end
        end

      if lit > 0.0, do: {lit / area, {r / lit, g / lit, b / lit}}, else: {0.0, mean}
    end
  end

  # The part of a square of `size` round `s` (on one axis) that is in the
  # bands [k * pitch + from, k * pitch + from + width], for each k.
  defp band(s, size, pitch, from, width) do
    size = max(size, 1.0e-6)
    (inside(s + size / 2, pitch, from, width) - inside(s - size / 2, pitch, from, width)) / size
  end

  # The length of the bands from 0 to `s` (less a constant).
  defp inside(s, pitch, from, width) do
    t = s - from
    k = floor(t / pitch)
    k * width + min(max(t - k * pitch, 0.0), width)
  end

  # The two axes of a plate: across the side that the surface faces most.
  defp across({x, y, z}, {nx, ny, nz}) do
    cond do
      abs(nz) >= abs(nx) and abs(nz) >= abs(ny) -> {x, y}
      abs(nx) >= abs(ny) -> {y, z}
      true -> {x, z}
    end
  end

  # The rivets of the seams: two rows on each seam, 1.5 rivets from it;
  # round heads of 6 mm, or their mean in a square larger than a head.
  defp rivets(a, b, k, size) do
    {w, h} = k.plate
    r = 0.006
    off = k.seam / 2 + 1.5 * r
    disc = fn u, v -> min(max((r - :math.sqrt(u * u + v * v)) / max(size, 1.0e-4) + 0.5, 0.0), 1.0) end
    near = fn s, pitch -> s - pitch * round(s / pitch) end
    {da, db} = {near.(a, w), near.(b, h)}
    {ra, rb} = {near.(a, k.rivets), near.(b, k.rivets)}
    one = max(disc.(abs(da) - off, rb), disc.(abs(db) - off, ra))
    mean = 2 * :math.pi() * r * r * (1 / (w * k.rivets) + 1 / (h * k.rivets))
    fade = min(max(size / (2 * r) - 0.5, 0.0), 1.0)
    one + (min(mean, 1.0) - one) * fade
  end

  # The height of a rib at `s` (a rib top at s = 0), and its area from 0 to `s` (less a constant).
  defp rib(%{profile: :round, pitch: p, depth: d}, s), do: d / 2 * (1 + :math.cos(2 * :math.pi() * s / p))

  defp rib(%{profile: :square, pitch: p, depth: d, top: t}, s) do
    x = abs(s - p * round(s / p))
    min(max(d - (x - t / 2), 0.0), d)
  end

  defp rib_area(%{profile: :round, pitch: p, depth: d}, s),
    do: d / 2 * (s + p / (2 * :math.pi()) * :math.sin(2 * :math.pi() * s / p))

  defp rib_area(%{profile: :square, pitch: p, depth: d, top: t}, s) do
    k = round(s / p)
    x = s - k * p

    half = fn x ->
      if x <= t / 2, do: d * x, else: d * t / 2 + (min(x, t / 2 + d) - t / 2) * d - (min(x, t / 2 + d) - t / 2) ** 2 / 2
    end

    k * (d * t + d * d) + if(x >= 0, do: half.(x), else: -half.(-x))
  end

  defp mix3({a, b, c}, {d, e, f}, t), do: {a + (d - a) * t, b + (e - b) * t, c + (f - c) * t}

  @doc """
  The surface of a kind at the place `q` (in the axes of the edit, in
  units of the scale), where the surface faces `n` (in the axes of the
  edit): `{height, tone, rough, metal, to}`.

  - `height`: the relief, in units of the scale (more is out).
  - `tone`: the color times this (1 for no change).
  - `rough`: this more roughness (0 for no change).
  - `metal`: the metal times this (1 for no change).
  - `to`: `{color, part}`, the part of a color of the kind that the
    surface has there (rust), or nil.
  """
  def at(:wood, {x, y, z}, _n) do
    # The middle of the tree is not in the part: the rings are arcs.
    {x, y} = {x + 7.3, y + 2.1}
    wobble = noise(x * 0.35, y * 0.35, z * 0.025)
    ring = frac(:math.sqrt(x * x + y * y) + 2.5 * wobble)
    # The late wood of a ring: a dark thin line.
    late = step(0.72, 0.9, ring) * (1.0 - step(0.93, 1.0, ring))
    streak = noise(x * 5.0, y * 5.0, z * 0.06) - 0.5
    {-0.05 * late + 0.03 * streak, 1.0 - 0.22 * late + 0.12 * streak, 0.06 * late, 1.0, nil}
  end

  def at(:bark, {x, y, z}, _n) do
    v = noise(x, y, z * 0.22) * 2.0 - 1.0
    # A crack is where the noise goes through its middle.
    crack = 1.0 - step(0.0, 0.3, abs(v))
    fine = noise(x * 3.1, y * 3.1, z * 1.3) - 0.5
    {-0.25 * crack + 0.06 * fine, 1.0 - 0.32 * crack + 0.16 * fine, 0.1 * crack, 1.0, nil}
  end

  def at(:brushed, {x, y, z}, _n) do
    v = noise(x, y, z * 0.03) - 0.5
    {0.04 * v, 1.0 + 0.08 * v, 0.12 * v, 1.0, nil}
  end

  def at(:cast, {x, y, z}, _n) do
    v = noise(x, y, z) - 0.5
    fine = noise(x * 2.7, y * 2.7, z * 2.7) - 0.5
    {0.07 * v + 0.035 * fine, 1.0 + 0.12 * v, 0.1 * (fine + 0.5), 1.0, nil}
  end

  def at(:plaster, {x, y, z}, _n) do
    v = noise(x * 0.5, y * 0.5, z * 0.5) - 0.5
    fine = noise(x * 2.0, y * 2.0, z * 2.0) - 0.5
    patch = noise(x * 0.08, y * 0.08, z * 0.08) - 0.5
    {0.1 * v + 0.04 * fine, 1.0 + 0.05 * v + 0.1 * patch, 0.05 * fine, 1.0, nil}
  end

  def at(:concrete, {x, y, z}, _n) do
    patch = noise(x * 0.3, y * 0.3, z * 0.3) - 0.5
    fine = noise(x * 3.0, y * 3.0, z * 3.0) - 0.5
    pit = step(0.8, 0.9, noise(x * 1.7, y * 1.7, z * 1.7))
    {0.03 * fine - 0.12 * pit, 1.0 + 0.16 * patch + 0.06 * fine - 0.25 * pit, 0.1 * pit, 1.0, nil}
  end

  def at(:fabric, {x, y, z}, {nx, ny, nz}) do
    # The two axes of the cloth: across the side that the surface faces most.
    {a, b} =
      cond do
        abs(nz) >= abs(nx) and abs(nz) >= abs(ny) -> {x, y}
        abs(nx) >= abs(ny) -> {y, z}
        true -> {x, z}
      end

    {h, over, thread} = plain(a, b)
    {0.25 * h, 0.9 + 0.12 * h + if(over, do: 0.03, else: -0.03) + 0.05 * thread, 0.05 * (1.0 - h), 1.0, nil}
  end

  def at(:weave, {x, y, _z}, _n) do
    {h, _over, strip} = plain(x, y)
    # (Each strip has its own tone, and the gaps between the strips are dark.)
    {0.18 * h, 0.72 + 0.3 * h + 0.14 * strip, 0.08 * (1.0 - h), 1.0, nil}
  end

  def at(:leather, {x, y, z}, _n) do
    a = 1.0 - step(0.0, 0.1, abs(noise(x, y, z) - 0.5))
    b = 1.0 - step(0.0, 0.08, abs(noise(x * 2.3 + 11.0, y * 2.3, z * 2.3) - 0.5))
    crease = max(a, 0.7 * b)
    {-0.1 * crease, 1.0 - 0.18 * crease, 0.06 * crease, 1.0, nil}
  end

  def at(:rubber, {x, y, z}, _n) do
    v = noise(x, y, z) - 0.5
    {0.06 * v, 1.0 + 0.06 * v, 0.08, 1.0, nil}
  end

  def at(:leaves, {x, y, z}, _n) do
    v = noise(x, y, z)
    fine = noise(x * 2.3, y * 2.3, z * 2.3)
    lump = 0.65 * v + 0.35 * fine
    {0.18 * (lump - 0.5), 0.8 + 0.4 * lump, 0.1 * (0.5 - lump), 1.0, nil}
  end

  def at(:stone, {x, y, z}, _n) do
    v = noise(x, y, z) - 0.5
    mid = noise(x * 2.2, y * 2.2, z * 2.2) - 0.5
    fine = noise(x * 5.0, y * 5.0, z * 5.0) - 0.5
    {0.2 * v + 0.1 * mid + 0.04 * fine, 1.0 + 0.2 * mid + 0.12 * fine, 0.1 * fine, 1.0, nil}
  end

  def at(:rust, {x, y, z}, _n) do
    v = 0.7 * noise(x, y, z) + 0.3 * noise(x * 2.9, y * 2.9, z * 2.9)
    patch = step(0.48, 0.62, v)
    pit = noise(x * 6.0, y * 6.0, z * 6.0) - 0.5
    {0.1 * patch * pit, 1.0 + 0.3 * patch * pit, 0.35 * patch, 1.0 - patch, {@rust, patch}}
  end

  def at(:hair, q, _n) do
    h = strand(q)
    {cx, cy, along} = flow(q)
    # Some strands catch the light.
    light = step(0.8, 0.95, noise(cx * 1.3 + 5.2, cy * 1.3, along * 0.015))
    {0.5 * (h - 0.5), 0.62 + 0.62 * h + 0.35 * light, 0.12 * (0.5 - h), 1.0, nil}
  end

  def at(:palm, {x, y, _z} = q, _n) do
    {cx, cy, along} = flow(q)
    fiber = noise(cx, cy, along * 0.01) - 0.5
    # The blade of a place: 40 round the z, each with its own tone; a dark line at its two edges.
    turn = (:math.atan2(y, x) / (2 * :math.pi()) + 0.5) * 40
    blade = floor(turn)
    edge = abs(turn - blade - 0.5) * 2
    seam = step(0.86, 0.98, edge)
    tone = 0.93 + 0.12 * (:erlang.phash2(blade, 256) / 255) + 0.1 * fiber - 0.22 * seam
    {0.25 * fiber - 0.35 * seam, tone, 0.06 * seam - 0.05 * fiber, 1.0, nil}
  end

  @doc """
  The height of the strand of hair at a place (in the axes of the edit,
  in units of the scale): 0 to 1. The strands go out from the z of the
  edit and down, as hair from the top of a head: a strand is a
  direction round the z, one unit wide at 60 units from it. Three
  strands or so make a lock.
  """
  def strand(q) do
    {cx, cy, along} = flow(q)
    one = noise(cx, cy, along * 0.02)
    lock = noise(cx * 0.3 + 7.1, cy * 0.3, along * 0.008)
    fine = noise(cx * 2.7, cy * 2.7 + 3.3, along * 0.05)
    # (The mean of the three is near the middle: the heights go over all of 0 to 1.)
    min(max((0.5 * one + 0.32 * lock + 0.18 * fine - 0.5) * 2.6 + 0.5, 0.0), 1.0)
  end

  # The place of a strand: its direction round the z (two numbers, with
  # no seam) and how far it is along the strand (out and down).
  defp flow({x, y, z}) do
    r = :math.sqrt(x * x + y * y)
    out = max(r, 1.0e-9)
    {60.0 * x / out, 60.0 * y / out, r - z}
  end

  # A plain weave of two sets of strips, one mark wide: the height of the
  # strip on top (0 at its edges, 1 on its middle line, and lower where
  # it goes under the next strip), if the strip along the first axis is
  # on top, and a number of the strip (0 to 1).
  defp plain(a, b) do
    {i, j} = {floor(a), floor(b)}
    {u, v} = {a - i - 0.5, b - j - 0.5}
    over = rem(i + j, 2) == 0
    # (The strip on top goes along the first axis in one square, along the second in the next.)
    {across, along, id} = if over, do: {v, u, j}, else: {u, v, i}
    h = (1.0 - 4.0 * across * across) * (1.0 - 1.2 * along * along)
    {h, over, :erlang.phash2({id, over}, 256) / 255}
  end

  defp frac(v), do: v - floor(v)

  # 0 below `a`, 1 above `b`, smooth between.
  defp step(a, _b, v) when v <= a, do: 0.0
  defp step(_a, b, v) when v >= b, do: 1.0

  defp step(a, b, v) do
    t = (v - a) / (b - a)
    t * t * (3.0 - 2.0 * t)
  end

  @doc """
  A smooth noise of a place: 0 to 1, the same for the same place, with
  one change for each unit of length (the values at the points of a
  grid, with a smooth mix between them).
  """
  def noise(x, y, z) do
    {i, j, k} = {floor(x), floor(y), floor(z)}
    {u, v, w} = {ease(x - i), ease(y - j), ease(z - k)}

    a = mix(mix(grid(i, j, k), grid(i + 1, j, k), u), mix(grid(i, j + 1, k), grid(i + 1, j + 1, k), u), v)

    b =
      mix(
        mix(grid(i, j, k + 1), grid(i + 1, j, k + 1), u),
        mix(grid(i, j + 1, k + 1), grid(i + 1, j + 1, k + 1), u),
        v
      )

    mix(a, b, w)
  end

  defp ease(t), do: t * t * (3.0 - 2.0 * t)
  defp mix(a, b, t), do: a + (b - a) * t
  defp grid(i, j, k), do: :erlang.phash2({i, j, k}, 1024) / 1023
end
