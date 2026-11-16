defmodule World.Forms do
  @moduledoc """
  The forms of a statue as data (plan 0005, step 4): the planes of a robe,
  a hood of hair, a heart in relief, each a simple solid that a sculptor
  or a form of a cast gives, in metres over the feet of the statue, in the
  axes of World (x right, y front, z up). The skill `robe` makes them
  (`World.Skills.Robe`); their sizes come from the measures of the real
  thing (`priv/measures/`).

  A form is a map with one of these keys:

  - `"rings"`: a list of rings, each a closed loop of points at one
    height or at one x, joined in their order and closed at the two ends
    (`World.Shape.rings/3`). A ring is `{"rect": [w, y0, y1, z]}` (from x
    = -w to w, from y0 to y1, at z), `{"oct": [w, y0, y1, c, z]}` (the
    same rectangle with its corners cut by c), `{"xrect": [x, y0, y1, z0,
    z1]}` (a rectangle at x, for a sleeve), or `{"points": [[x, y, z],
    ...]}`.
  - `"loft"`: sections `[x, y, z, a, b, p]` (a superellipse of half sizes
    a and b, power p, its center at x, y, z), along `"axis"` `"z"` (a and
    b along x and y; the default) or `"y"` (along x and z).
    `"smooth"` (0 to 2): the surface is subdivided that many times.
  - `"lathe"`: a profile `[r, z]` round the z axis, with `"sides"` (3 to
    64) and `"turn"` (degrees, round z).
  - `"box"`: two corners `[[x0, y0, z0], [x1, y1, z1]]`.
  - `"prism"`: a loop `[u, v]` (u along x, v along z) from `"at"` along
    +y for `"length"` m: a relief on the front.
  - `"sweep"`: a line of points `[x, y, z]` with a round section of
    `"radius"` m.

  And these keys, each optional:

  - `"mirror"`: true for a second form, its mirror across x = 0.
  - `"detail"`: true for a form that is seen and not cast (a relief, the
    bars of a window): it is not in the field of the cast.
  - `"material"`: `"dark"` (the dark of an opening) or `"steel"`; else the
    material of the statue.
  """
  alias World.{Frame, Mesh, Mirror, Shape}

  @kinds ~w(rings loft lathe box prism sweep)
  @keys @kinds ++ ~w(mirror detail material axis smooth sides turn at length radius)
  @materials %{"dark" => {:dark, :concrete}, "steel" => {:steel, :steel}}
  @shapes %{
    "rings" => "must be two or more rings",
    "loft" => "must be two or more sections",
    "lathe" => "must be two or more points [r, z]",
    "box" => "must be two corners [x, y, z]",
    "prism" => "must be three or more points [u, v]",
    "sweep" => "must be two or more points [x, y, z]"
  }

  @doc """
  The errors of the data of a list of forms, at `path`: `{:ok, forms}` or
  `{:error, [{path, message}]}`.
  """
  def check(forms, path) when is_list(forms) do
    errors = forms |> Enum.with_index() |> Enum.flat_map(fn {f, i} -> errors(f, "#{path}.#{i}") end)
    if errors == [], do: {:ok, forms}, else: {:error, errors}
  end

  def check(_forms, path), do: {:error, [{path, "must be a list of forms"}]}

  defp errors(f, path) when is_map(f) do
    case Enum.filter(@kinds, &Map.has_key?(f, &1)) do
      [kind] ->
        extra = for k <- Map.keys(f), k not in @keys, do: {"#{path}.#{k}", "is not a key of a form"}
        extra ++ kind_errors(kind, f[kind], f, "#{path}.#{kind}") ++ common_errors(f, path)

      _ ->
        [{path, "must have one of: #{Enum.join(@kinds, ", ")}"}]
    end
  end

  defp errors(_f, path), do: [{path, "must be an object"}]

  defp common_errors(f, path) do
    m =
      if Map.get(f, "material") in [nil | Map.keys(@materials)],
        do: [],
        else: [{path <> ".material", "must be dark or steel"}]

    b =
      for k <- ~w(mirror detail),
          Map.has_key?(f, k),
          not is_boolean(f[k]),
          do: {"#{path}.#{k}", "must be true or false"}

    m ++ b
  end

  defp kind_errors("rings", [_, _ | _] = rings, _f, path) do
    case rings |> Enum.with_index() |> Enum.flat_map(fn {r, i} -> ring_errors(r, "#{path}.#{i}") end) do
      [] ->
        if rings |> Enum.map(&length(ring(&1))) |> Enum.uniq() |> length() == 1,
          do: [],
          else: [{path, "must have the same number of points in each ring"}]

      errors ->
        errors
    end
  end

  defp kind_errors("loft", [_, _ | _] = sections, f, path) do
    bad =
      for {s, i} <- Enum.with_index(sections), not numbers?(s, 6), do: {"#{path}.#{i}", "must be [x, y, z, a, b, p]"}

    axis =
      if Map.get(f, "axis", "z") in ~w(z y),
        do: [],
        else: [{String.replace_suffix(path, "loft", "axis"), "must be z or y"}]

    bad ++ axis ++ int_errors(f, "smooth", 0, 2, path)
  end

  defp kind_errors("lathe", [_, _ | _] = profile, f, path) do
    bad = for {p, i} <- Enum.with_index(profile), not numbers?(p, 2), do: {"#{path}.#{i}", "must be [r, z]"}
    bad ++ int_errors(f, "sides", 3, 64, path)
  end

  defp kind_errors("box", [a, b], _f, path) when is_list(a) and is_list(b),
    do: if(numbers?(a, 3) and numbers?(b, 3), do: [], else: [{path, @shapes["box"]}])

  defp kind_errors("prism", [_, _, _ | _] = loop, f, path) do
    bad = for {p, i} <- Enum.with_index(loop), not numbers?(p, 2), do: {"#{path}.#{i}", "must be [u, v]"}
    at = if numbers?(f["at"], 3), do: [], else: [{String.replace_suffix(path, "prism", "at"), "must be [x, y, z]"}]

    l =
      if is_number(f["length"]) and f["length"] > 0,
        do: [],
        else: [{String.replace_suffix(path, "prism", "length"), "must be a length over 0"}]

    bad ++ at ++ l
  end

  defp kind_errors("sweep", [_, _ | _] = line, f, path) do
    bad = for {p, i} <- Enum.with_index(line), not numbers?(p, 3), do: {"#{path}.#{i}", "must be [x, y, z]"}

    r =
      if is_number(f["radius"]) and f["radius"] > 0,
        do: [],
        else: [{String.replace_suffix(path, "sweep", "radius"), "must be a radius over 0"}]

    bad ++ r
  end

  defp kind_errors(kind, _v, _f, path), do: [{path, @shapes[kind]}]

  defp ring_errors(%{"rect" => v}, path),
    do: if(numbers?(v, 4), do: [], else: [{path <> ".rect", "must be [w, y0, y1, z]"}])

  defp ring_errors(%{"oct" => v}, path),
    do: if(numbers?(v, 5), do: [], else: [{path <> ".oct", "must be [w, y0, y1, c, z]"}])

  defp ring_errors(%{"xrect" => v}, path),
    do: if(numbers?(v, 5), do: [], else: [{path <> ".xrect", "must be [x, y0, y1, z0, z1]"}])

  defp ring_errors(%{"points" => ps}, path) when is_list(ps),
    do:
      if(length(ps) >= 3 and Enum.all?(ps, &numbers?(&1, 3)),
        do: [],
        else: [{path <> ".points", "must be three or more points [x, y, z]"}]
      )

  defp ring_errors(_r, path), do: [{path, "must be a ring: rect, oct, xrect or points"}]

  defp int_errors(f, key, lo, hi, path) do
    case Map.fetch(f, key) do
      :error ->
        []

      {:ok, v} when is_integer(v) and v >= lo and v <= hi ->
        []

      _ ->
        [
          {String.replace_suffix(path, path |> String.split(".") |> List.last(), key),
           "must be an integer from #{lo} to #{hi}"}
        ]
    end
  end

  defp numbers?(v, n), do: is_list(v) and length(v) == n and Enum.all?(v, &is_number/1)

  @doc """
  The meshes of the forms in the material `{look, matter}` of the statue:
  `{cast, detail}`, the forms of the field of the cast and the forms that
  are only seen.
  """
  def meshes(forms, {look, matter}) do
    for f <- forms, mesh <- with_mirror(f, mesh(f, look)), reduce: {[], []} do
      {cast, detail} ->
        {l, m} = Map.get(@materials, f["material"], {look, matter})
        mesh = %{mesh | material: l} |> Mesh.matter(m)
        if f["detail"], do: {cast, [mesh | detail]}, else: {[mesh | cast], detail}
    end
    |> then(fn {c, d} -> {Enum.reverse(c), Enum.reverse(d)} end)
  end

  defp with_mirror(f, mesh), do: if(f["mirror"], do: [mesh, Mirror.mesh(mesh)], else: [mesh])

  defp mesh(%{"rings" => rings}, look), do: Shape.rings(Enum.map(rings, &ring/1), look)

  defp mesh(%{"loft" => sections} = f, look) do
    {u, v} =
      if Map.get(f, "axis", "z") == "y",
        do: {{1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}},
        else: {{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}}

    secs = for [x, y, z, a, b, p] <- sections, do: {{x / 1, y / 1, z / 1}, u, v, a / 1, b / 1, p / 1}
    Shape.loft(secs, look, sides: Map.get(f, "sides", 20), smooth: Map.get(f, "smooth", 0))
  end

  defp mesh(%{"lathe" => profile} = f, look) do
    a = Map.get(f, "turn", 0) * :math.pi() / 180
    frame = Frame.new({0.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, {-:math.sin(a), :math.cos(a), 0.0})
    Shape.lathe(for([r, z] <- profile, do: {r / 1, z / 1}), look, sides: Map.get(f, "sides", 32), frame: frame)
  end

  defp mesh(%{"box" => [a, b]}, look),
    do: Shape.box(List.to_tuple(Enum.map(a, &(&1 / 1))), List.to_tuple(Enum.map(b, &(&1 / 1))), look)

  defp mesh(%{"prism" => loop, "at" => [x, y, z], "length" => l}, look) do
    # Local x is -x of World with these axes; the loop goes in mirrored so
    # that u is along +x.
    frame = Frame.new({x / 1, y / 1, z / 1}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0})
    Shape.prism(for([u, v] <- loop, do: {-u / 1, v / 1}), l / 1, look, frame: frame)
  end

  defp mesh(%{"sweep" => line, "radius" => r}, look),
    do: Shape.sweep(for([x, y, z] <- line, do: {x / 1, y / 1, z / 1}), r / 1, look, sides: 8)

  defp ring(%{"rect" => [w, y0, y1, z]}), do: [{-w, y0, z}, {w, y0, z}, {w, y1, z}, {-w, y1, z}] |> floats()

  defp ring(%{"oct" => [w, y0, y1, c, z]}),
    do:
      [
        {-w + c, y0, z},
        {w - c, y0, z},
        {w, y0 + c, z},
        {w, y1 - c, z},
        {w - c, y1, z},
        {-w + c, y1, z},
        {-w, y1 - c, z},
        {-w, y0 + c, z}
      ]
      |> floats()

  defp ring(%{"xrect" => [x, y0, y1, z0, z1]}), do: [{x, y0, z0}, {x, y1, z0}, {x, y1, z1}, {x, y0, z1}] |> floats()
  defp ring(%{"points" => ps}), do: for([x, y, z] <- ps, do: {x / 1, y / 1, z / 1})

  defp floats(ps), do: for({x, y, z} <- ps, do: {x / 1, y / 1, z / 1})
end
