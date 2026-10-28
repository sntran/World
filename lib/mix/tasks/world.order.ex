defmodule Mix.Tasks.World.Order do
  @shortdoc "Builds the files of an order (docs/factory.md)"
  @moduledoc """
  Builds the files of an order of the factory (`World.Orders`), from a
  JSON file:

      mix world.order ORDER.json              # into out/
      mix world.order ORDER.json --dir DIR

  The files have the hash of the order as their name: `HASH.glb`,
  `HASH.mid.glb`, `HASH.far.glb`, and at the near level
  `HASH.log.json` (the log of the run of the world that built it),
  `HASH.replay.glb` (each part in a node of its own, for the replay),
  `HASH.parts.json` and `HASH.receipt.json`. A wrong order stops the task
  with each error.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, files} = OptionParser.parse!(args, strict: [dir: :string])
    Mix.Task.run("compile")
    dir = Keyword.get(opts, :dir, "out")

    file =
      case files do
        [file] -> file
        _ -> Mix.raise("Give one file: mix world.order ORDER.json")
      end

    order = file |> File.read!() |> JSON.decode!()

    order = ok!(World.Orders.check(order))
    hash = World.Orders.hash(order)

    files =
      for {level, ext} <- [{"near", ""}, {"mid", ".mid"}, {"far", ".far"}],
          file <- if(level == "near", do: World.Orders.files(), else: ["glb"]) do
        name =
          case file do
            "glb" -> "#{hash}#{ext}.glb"
            "replay" -> "#{hash}.replay.glb"
            _ -> "#{hash}.#{file}.json"
          end

        {name, ok!(World.Orders.build(order, level, file))}
      end

    File.mkdir_p!(dir)
    for {name, bin} <- files, do: File.write!(Path.join(dir, name), bin)
    Mix.shell().info("Wrote the files of #{hash} in #{dir}.")
  end

  defp ok!({:ok, value}), do: value

  defp ok!({:error, errors}),
    do: Mix.raise("The order is not correct:\n" <> Enum.map_join(errors, "\n", &"- #{&1["path"]}: #{&1["message"]}"))
end
