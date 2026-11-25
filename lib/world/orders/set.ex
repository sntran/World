defmodule World.Orders.Set do
  @moduledoc """
  A set of orders: one list gives a set of variants (Vũng Tàu, W19: 30
  tube houses of 4 m, by seed). The game makes a library from the set,
  and picks one variant by the size of its lot.

  A set is a map (from JSON), one of:

  - `"orders"`: a list of orders (`World.Orders`);
  - `"order"` (an order: the base of each variant), `"count"` (1 to
    #{64}), `"seed"` (an integer: the seed of the set) and `"vary"` (an
    option name to a list of its values): each variant `i` has the
    options of the base, a value of each list of `vary` (the set seed
    and `i` pick it), and the option `seed` (when the blueprint has
    one and the base and `vary` do not give it) `seed * 1000 + i`.

  The same set gives the same orders, so the same files.

  Two keys of a set change the images of its files (plan 0020):

  - `"atlas"`: true puts the images of the bakes of all the variants
    into one atlas (D12, `World.Atlas`), at each level. The set is then
    in the store (`sets/SET.json`), and each variant has its files with
    the atlas at `/s/SET/I.glb` (and `.mid.glb`, `.far.glb`): the GLB
    has no image of its own, and refers to the images of the set at
    its level (`/s/SET.color.png`, `/s/SET.far.normal.png`, ...) by
    their URLs. A game loads each image one time, and draws the parts
    of all the variants with one material. The files of the order of
    each variant (`/o/HASH...`) stay as they are.
  - `"images"`: `"png"` (the default) or `"ktx2"` (D14, `World.KTX2`):
    the images of the atlas, or with no atlas the images of the files
    of each variant (its order gets `"images": "ktx2"`).
  """
  alias World.{Atlas, GLB, Orders}
  alias World.Orders.{Blueprints, Store}

  @max 64

  @doc "The most variants in a set."
  def max, do: @max

  @doc """
  The full orders of a set: `{:ok, orders}`, or `{:error, errors}` (each
  with its `"path"` in the set and its `"message"`).
  """
  def check(%{"orders" => orders}) when is_list(orders) and orders != [] and length(orders) <= @max do
    orders
    |> Enum.with_index()
    |> Enum.map(fn {o, i} -> {i, Orders.check(o)} end)
    |> collect("orders")
  end

  def check(%{"orders" => _}), do: error("orders", "must be a list of 1 to #{@max} orders")

  def check(%{"order" => base} = set) when is_map(base) do
    count = Map.get(set, "count", 1)
    seed = Map.get(set, "seed", 1)
    vary = Map.get(set, "vary", %{})

    cond do
      not (is_integer(count) and count in 1..@max) ->
        error("count", "must be an integer from 1 to #{@max}")

      not is_integer(seed) ->
        error("seed", "must be an integer")

      not (is_map(vary) and Enum.all?(vary, fn {_, v} -> is_list(v) and v != [] end)) ->
        error("vary", "must map each option to a list of its values")

      true ->
        0..(count - 1) |> Enum.map(&{&1, Orders.check(variant(base, seed, vary, &1))}) |> collect("variants")
    end
  end

  def check(_set), do: error("", "must have \"orders\", or \"order\" with \"count\", \"seed\" and \"vary\"")

  # The order of the variant `i`: the base, a value of each list of
  # `vary`, and a seed of its own.
  defp variant(base, seed, vary, i) do
    options = Map.get(base, "options", %{})

    picked =
      for {key, values} <- Enum.sort(vary), into: %{} do
        <<n::unsigned-32, _::binary>> = :crypto.hash(:sha256, "#{seed}/#{i}/#{key}")
        {key, Enum.at(values, rem(n, length(values)))}
      end

    options = Map.merge(options, picked)

    options =
      if seeded?(base) and not Map.has_key?(options, "seed"),
        do: Map.put(options, "seed", seed * 1000 + i),
        else: options

    Map.put(base, "options", options)
  end

  defp seeded?(%{"blueprint" => name}) do
    case Blueprints.fetch(name) do
      {:ok, b} -> Enum.any?(b.options, &(&1.name == "seed"))
      :error -> false
    end
  end

  defp seeded?(_), do: false

  defp collect(results, prefix) do
    case for {i, {:error, errors}} <- results, e <- errors, do: %{e | "path" => join("#{prefix}.#{i}", e["path"])} do
      [] -> {:ok, for({_, {:ok, full}} <- results, do: full)}
      errors -> {:error, errors}
    end
  end

  defp join(a, ""), do: a
  defp join(a, b), do: a <> "." <> b

  defp error(path, message), do: {:error, [%{"path" => path, "message" => message}]}

  @doc """
  Place each order of a set (`World.Orders.place/2`). Gives `{:ok,
  %{"set", "variants"}}`: the hash of the set (of the hashes of its
  orders, in their order), and for each variant its hash, its full
  order, the URLs of its files, and `lot` (`width` and `depth`, when its
  options have them: a house on a lot), so that the game picks a variant
  by the size of a lot. Else `{:error, errors}`, or `{:error, :store}`.
  """
  def place(set, origin) do
    with {:ok, atlas, images} <- look(set),
         {:ok, orders} <- check(set),
         orders = if(images == "ktx2" and not atlas, do: Enum.map(orders, &Map.put(&1, "images", "ktx2")), else: orders),
         {:ok, hash} <- keep(orders, atlas, images) do
      placed = orders |> Enum.with_index() |> Enum.map(fn {o, i} -> {i, Orders.place(o, origin)} end)

      cond do
        Enum.any?(placed, &match?({_, {:error, :store}}, &1)) ->
          {:error, :store}

        Enum.any?(placed, &match?({_, {:error, _}}, &1)) ->
          collect(placed, "variants")

        true ->
          variants =
            for {_, {:ok, p}} <- placed, do: Map.merge(Map.take(p, ["hash", "order", "files"]), lot(p["order"]))

          if atlas,
            do:
              {:ok, %{"set" => hash, "atlas" => true, "images" => images, "variants" => urls(variants, hash, origin)}},
            else: {:ok, %{"set" => hash, "variants" => variants}}
      end
    end
  end

  # The keys `atlas` and `images` of a set.
  defp look(set) do
    case {Map.get(set, "atlas", false), Orders.images(Map.get(set, "images", "png"), "images")} do
      {atlas, {:ok, images}} when is_boolean(atlas) -> {:ok, atlas, images}
      {atlas, _} when not is_boolean(atlas) -> error("atlas", "must be true or false")
      {_, {:error, [{path, message}]}} -> error(path, message)
    end
  end

  # The hash of a set (of the hashes of its full orders); a set with an
  # atlas has its keys in it too, and goes into the store.
  defp keep(orders, false, _images), do: {:ok, Orders.hash(%{"set" => Enum.map(orders, &Orders.hash/1)})}

  defp keep(orders, true, images) do
    set = %{"set" => Enum.map(orders, &Orders.hash/1), "atlas" => true, "images" => images}
    hash = Orders.hash(set)
    if Store.put_key(Store.set(hash), Orders.encode(set)) == :ok, do: {:ok, hash}, else: {:error, :store}
  end

  # The URLs of the files of each variant with the atlas of the set.
  defp urls(variants, hash, origin) do
    for {v, i} <- Enum.with_index(variants) do
      Map.put(v, "atlas", %{
        "glb" => "#{origin}/s/#{hash}/#{i}.glb",
        "mid.glb" => "#{origin}/s/#{hash}/#{i}.mid.glb",
        "far.glb" => "#{origin}/s/#{hash}/#{i}.far.glb"
      })
    end
  end

  @doc """
  The hash and the level of a file of a set with an atlas (`/s/NAME`):
  `{:ok, hash, level}` for the GLB of a variant (`SET/I.glb`,
  `SET/I.mid.glb`, `SET/I.far.glb`) or an image of the atlas
  (`SET.color.png`, `SET.far.glow.ktx2`, ...), else `:error`.
  """
  def name(name) do
    glb = Regex.run(~r"\A([0-9a-f]{32})/\d{1,2}(?:\.(mid|far))?\.glb\z", name)
    image = Regex.run(~r"\A([0-9a-f]{32})(?:\.(mid|far))?\.(?:color|normal|finish|glow)\.(?:png|ktx2)\z", name)

    case glb || image do
      [_, hash] -> {:ok, hash, "near"}
      [_, hash, level] -> {:ok, hash, level}
      nil -> :error
    end
  end

  @doc """
  The files of a set with an atlas at a level (`"near"`, `"mid"` or
  `"far"`): the scene of each variant (`World.Orders.scene/2`), with the
  images of all of them in one atlas (`World.Atlas.scenes/2`). Gives
  `{:ok, files}` (each `{name, bytes}`, with the names of `name/1`),
  `:none` when the store has no such set, `{:error, :store}` when the
  store failed, or `{:error, errors}` (also when the build needs more
  memory than the guard of the memory gives, `World.Guard`).
  """
  def files(hash, level) do
    # (In the guard of the memory: a set of many houses at near can need more than the edge has.)
    case World.Guard.run(fn -> files_now(hash, level) end) do
      {:ok, result} -> result
      {:error, :memory} -> {:error, World.Guard.errors()}
    end
  end

  defp files_now(hash, level) do
    suffix = if level == "near", do: "", else: ".#{level}"

    with {:ok, json} <- Store.get_key(Store.set(hash)),
         %{"set" => hashes, "images" => images} = JSON.decode!(json),
         {:ok, scenes} <- scenes(hashes, level) do
      # (A GLB of a variant is at /s/SET/I.LEVEL.glb, an image at /s/SET.LEVEL.MAP.EXT.)
      uri = fn m, ext -> "../#{hash}#{suffix}.#{Atlas.names()[m]}.#{ext}" end
      {scenes, maps} = Atlas.scenes(scenes, images: images, uri: uri)
      glbs = for {scene, i} <- Enum.with_index(scenes), do: {"#{hash}/#{i}#{suffix}.glb", GLB.encode(scene)}

      pictures =
        for {m, {mime, bytes}} <- Enum.sort(maps),
            do: {"#{hash}#{suffix}.#{Atlas.names()[m]}.#{if(mime == "image/ktx2", do: "ktx2", else: "png")}", bytes}

      {:ok, glbs ++ pictures}
    else
      :error -> {:error, :store}
      other -> other
    end
  end

  # The scene of each variant at a level, from its full order in the store.
  defp scenes(hashes, level) do
    Enum.reduce_while(hashes, {:ok, []}, fn h, {:ok, acc} ->
      with {:ok, json} <- Store.get(h),
           {:ok, scene} <- Orders.scene(JSON.decode!(json), level) do
        {:cont, {:ok, acc ++ [scene]}}
      else
        other -> {:halt, other}
      end
    end)
  end

  defp lot(%{"options" => %{"width" => w, "depth" => d}}), do: %{"lot" => %{"width" => w, "depth" => d}}
  defp lot(_order), do: %{}
end
