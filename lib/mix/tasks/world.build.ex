defmodule Mix.Tasks.World.Build do
  @shortdoc "Writes the files of each model in priv/models"
  @moduledoc """
  Writes the files of each model of `World.Catalog` in `priv/models`:

  - `NAME.glb`, `NAME.mid.glb`, `NAME.far.glb`: the three levels of detail;
  - `NAME.parts.json`: the list of the parts;
  - `list.json`: the names of the models, for the review page.

      mix world.build            # all the models
      mix world.build NAME ...   # some models
      mix world.build --check    # build again and compare, with no write

  With `--check`, the task stops with an error when a file is not the
  same as the build.
  """
  use Mix.Task

  @levels [{:near, ""}, {:mid, ".mid"}, {:far, ".far"}]

  @impl true
  def run(args) do
    {opts, names} = OptionParser.parse!(args, strict: [check: :boolean, dir: :string])
    Mix.Task.run("compile")
    dir = Keyword.get(opts, :dir, "priv/models")
    models = World.Catalog.models()
    chosen = if names == [], do: models, else: Enum.map(names, &{&1, fetch!(&1)})

    files =
      Enum.flat_map(chosen, fn {name, fun} ->
        # The model is made again at each level (World.Detail).
        glbs =
          for {level, ext} <- @levels do
            item = World.Detail.with(level, fun)
            {Path.join(dir, name <> ext <> ".glb"), World.Build.glb(item, level: level)}
          end

        parts = %{"name" => name, "parts" => World.Build.parts(fun.())}
        [{Path.join(dir, name <> ".parts.json"), JSON.encode!(parts)} | glbs]
      end)

    files =
      if names == [],
        do: [{Path.join(dir, "list.json"), JSON.encode!(Enum.map(models, &elem(&1, 0)))} | files],
        else: files

    if opts[:check], do: check(files), else: write(files)
  end

  defp fetch!(name) do
    case World.Catalog.fetch(name) do
      {:ok, fun} -> fun
      :error -> Mix.raise("No model #{name} in World.Catalog")
    end
  end

  defp write(files) do
    for {path, bin} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bin)
    end

    Mix.shell().info("Wrote #{length(files)} files.")
  end

  defp check(files) do
    bad = for {path, bin} <- files, File.read(path) != {:ok, bin}, do: path

    if bad == [] do
      Mix.shell().info("The #{length(files)} files are the same as the build.")
    else
      Mix.raise("These files are not the same as the build: #{Enum.join(bad, ", ")}. Run mix world.build.")
    end
  end
end
