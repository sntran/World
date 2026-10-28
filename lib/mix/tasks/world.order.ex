defmodule Mix.Tasks.World.Order do
  @shortdoc "Builds the files of an order (docs/factory.md)"
  @moduledoc """
  Builds the files of an order of the factory (`World.Orders`), from a
  JSON file:

      mix world.order ORDER.json              # into out/
      mix world.order ORDER.json --dir DIR

  The files have the hash of the order as their name: `HASH.glb`,
  `HASH.mid.glb`, `HASH.far.glb`, `HASH.parts.json` and
  `HASH.receipt.json` (the receipt of the near level). A wrong order
  stops the task with each error.
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
      Enum.flat_map([{"near", ""}, {"mid", ".mid"}, {"far", ".far"}], fn {level, ext} ->
        out = ok!(World.Orders.build(order, level))
        glb = {hash <> ext <> ".glb", out.glb}

        if level == "near",
          do: [glb, {hash <> ".parts.json", out.parts}, {hash <> ".receipt.json", out.receipt}],
          else: [glb]
      end)

    File.mkdir_p!(dir)
    for {name, bin} <- files, do: File.write!(Path.join(dir, name), bin)
    Mix.shell().info("Wrote the files of #{hash} in #{dir}.")
  end

  defp ok!({:ok, value}), do: value

  defp ok!({:error, errors}),
    do: Mix.raise("The order is not correct:\n" <> Enum.map_join(errors, "\n", &"- #{&1["path"]}: #{&1["message"]}"))
end
