defmodule Mix.Tasks.World.Build do
  @shortdoc "Writes the files of each model in priv/models"
  @moduledoc """
  Writes the files of each model of `World.Catalog` in `priv/models`:

  - `NAME.glb`, `NAME.mid.glb`, `NAME.far.glb`: the three levels of detail;
  - `NAME.parts.json`: the list of the parts;
  - `list.json`: the names of the models, for the review page.

  With no names, it also writes the kit of a person in `priv/kit`
  (`World.People.Kit`).

      mix world.build                 # all the models
      mix world.build NAME ...        # some models
      mix world.build --check         # build again and compare, with no write
      mix world.build --check --part 2/8

  With `--check`, the task stops with an error when a file is not the
  same as the build. With no names it also stops when the directory has
  a file of a model that is not in the catalog. CI runs the check of the
  catalog on request (`.github/workflows/catalog.yml`: a pull request
  with the label `catalog`, a pull request that changes `priv/models`,
  or a run by hand), in parts at the same time (`--part I/N`: the
  models with the indices I, I + N, I + 2N... of the catalog; the list
  and the kit are in part 1). A commit that changes a model builds its
  files again (`mix world.build NAME`).

  A drawing of the catalog (`World.Drawing.Catalog`) is also the order
  `{"blueprint": "catalog", "options": {"name": NAME}}`, and the edge gives
  the files of `priv/models` for that order with no build (`handler.js`).
  So the task also builds that order at each level, as a clone builds it
  (`mix world.order`), and it stops with an error when the order does not
  give the bytes of the file.

  The models build at the same time, one on each core (`--jobs` sets
  the count).
  """
  use Mix.Task

  @levels [{:near, ""}, {:mid, ".mid"}, {:far, ".far"}]

  @impl true
  def run(args) do
    {opts, names} =
      OptionParser.parse!(args, strict: [check: :boolean, dir: :string, kit: :string, part: :string, jobs: :integer])

    Mix.Task.run("app.start")
    dir = Keyword.get(opts, :dir, "priv/models")
    # (The catalog: World.Catalog, or the module of the application environment `:catalog`.)
    catalog = Application.get_env(:world, :catalog, World.Catalog)
    models = catalog.models()
    {part, parts} = part!(opts[:part])
    all? = names == []
    chosen = if all?, do: models, else: Enum.map(names, &{&1, fetch!(catalog, &1)})
    chosen = for {model, i} <- Enum.with_index(chosen), rem(i, parts) == part - 1, do: model

    # Each model is written (or compared) as soon as it is built: the files of all the models do not
    # wait in memory.
    put = if opts[:check], do: &compare/1, else: &write/1

    # (Each result: the count of the files, the files not the same as the build, and the files that
    # the order of a drawing of the catalog does not give.)
    results =
      chosen
      |> Task.async_stream(
        fn model ->
          {files, wrong} = files(dir, model)
          {n, bad} = put.(files)
          {n, bad, wrong}
        end,
        max_concurrency: Keyword.get(opts, :jobs, System.schedulers_online()),
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, result} -> result end)

    rest =
      if all? and part == 1,
        do: [put.([{Path.join(dir, "list.json"), JSON.encode!(Enum.map(models, &elem(&1, 0)))} | kit(catalog, opts)])],
        else: []

    {count, bad} =
      Enum.reduce(results ++ rest, {0, []}, fn result, {count, bad} ->
        {count + elem(result, 0), bad ++ elem(result, 1)}
      end)

    wrong = Enum.flat_map(results, &elem(&1, 2))

    if wrong != [] do
      Mix.raise(
        "The order catalog of a drawing does not give the bytes of its file (a clone and the edge give other files): " <>
          Enum.join(wrong, ", ")
      )
    end

    cond do
      !opts[:check] -> Mix.shell().info("Wrote #{count} files.")
      all? -> report(count, bad, extra(dir, models, part, parts))
      true -> report(count, bad, [])
    end
  end

  # The files of a model: it is made again at each level (World.Detail). The
  # list of the parts is from the near level (the level by default).
  defp files(dir, {name, fun}) do
    built =
      for {level, ext} <- @levels do
        item = World.Detail.with(level, fun)
        {level, item, {Path.join(dir, name <> ext <> ".glb"), World.Build.glb(item, level: level)}}
      end

    [{:near, near, _} | _] = built
    parts = World.Build.parts_file(name, near)
    {[{Path.join(dir, name <> ".parts.json"), JSON.encode!(parts)} | Enum.map(built, &elem(&1, 2))], order(name, built)}
  end

  # The files of a drawing of the catalog that its order does not give at their level (none for a
  # model that is not a drawing of the catalog).
  defp order(name, built) do
    if name in World.Drawing.Catalog.names() do
      order = %{"blueprint" => "catalog", "options" => %{"name" => name}}

      for {level, _item, {path, glb}} <- built,
          World.Orders.build(order, Atom.to_string(level), "glb") != {:ok, glb},
          do: path
    else
      []
    end
  end

  defp part!(nil), do: {1, 1}

  defp part!(text) do
    with [i, n] <- String.split(text, "/"),
         {i, ""} <- Integer.parse(i),
         {n, ""} <- Integer.parse(n),
         true <- n >= 1 and i >= 1 and i <= n do
      {i, n}
    else
      _ -> Mix.raise("The part is I/N, with 1 <= I <= N: not #{text}")
    end
  end

  # The files of the directory that no model of the catalog makes (a model that is not in the catalog
  # now). Part 1 of a check in parts looks for them.
  defp extra(_dir, _models, part, _parts) when part != 1, do: []

  defp extra(dir, models, _part, _parts) do
    names = MapSet.new(models, &elem(&1, 0))
    model = fn file -> file |> String.replace(~r/(\.mid|\.far)?\.glb$|\.parts\.json$/, "") end

    for file <- File.ls!(dir),
        file != "list.json",
        File.regular?(Path.join(dir, file)),
        not MapSet.member?(names, model.(file)),
        do: Path.join(dir, file)
  end

  defp kit(catalog, opts) do
    dir = Keyword.get(opts, :kit, "priv/kit")
    for {path, bin} <- catalog.kit(), do: {Path.join(dir, path), bin}
  end

  defp fetch!(catalog, name) do
    case catalog.fetch(name) do
      {:ok, fun} -> fun
      :error -> Mix.raise("No model #{name} in #{inspect(catalog)}")
    end
  end

  # The count of the files, and the files that are not the same as the build.
  defp write(files) do
    for {path, bin} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bin)
    end

    {length(files), []}
  end

  defp compare(files), do: {length(files), for({path, bin} <- files, File.read(path) != {:ok, bin}, do: path)}

  defp report(count, bad, extra) do
    cond do
      bad != [] ->
        Mix.raise("These files are not the same as the build: #{Enum.join(bad, ", ")}. Run mix world.build.")

      extra != [] ->
        Mix.raise("These files are of no model of the catalog: #{Enum.join(extra, ", ")}. Delete them.")

      true ->
        Mix.shell().info("The #{count} files are the same as the build.")
    end
  end
end
