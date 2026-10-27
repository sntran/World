defmodule Mix.Tasks.Xuong.Build do
  @shortdoc "Writes the files of each model in priv/models"
  @moduledoc """
  Writes the files of each model of `Xuong.Catalog` in `priv/models`:

  - `NAME.glb`, `NAME.mid.glb`, `NAME.far.glb`: the three levels of detail;
  - `NAME.parts.json`: the list of the parts;
  - `list.json`: the names of the models, for the review page.

      mix xuong.build            # all the models
      mix xuong.build NAME ...   # some models
      mix xuong.build --check    # build again and compare, with no write

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
    models = Xuong.Catalog.models()
    chosen = if names == [], do: models, else: Enum.map(names, &{&1, fetch!(&1)})

    files =
      Enum.flat_map(chosen, fn {name, fun} ->
        item = fun.()

        glbs =
          for {level, ext} <- @levels, do: {Path.join(dir, name <> ext <> ".glb"), Xuong.Build.glb(item, level: level)}

        parts = %{"name" => name, "parts" => Xuong.Build.parts(item)}
        [{Path.join(dir, name <> ".parts.json"), JSON.encode!(parts)} | glbs]
      end)

    files =
      if names == [],
        do: [{Path.join(dir, "list.json"), JSON.encode!(Enum.map(models, &elem(&1, 0)))} | files],
        else: files

    if opts[:check], do: check(files), else: write(files)
  end

  defp fetch!(name) do
    case Xuong.Catalog.fetch(name) do
      {:ok, fun} -> fun
      :error -> Mix.raise("No model #{name} in Xuong.Catalog")
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
      Mix.raise("These files are not the same as the build: #{Enum.join(bad, ", ")}. Run mix xuong.build.")
    end
  end
end
