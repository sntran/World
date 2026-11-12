defmodule Mix.Tasks.World.Bench do
  @shortdoc "Measures the build of each model through the people"
  @moduledoc """
  Builds each model of the catalog (with the drawings) and each
  blueprint in data through the people (`World.build/1`), one at a time, and prints
  for each one its result, its wall time, the most memory, the use of
  the schedulers, its tasks and its triangles (`World.Bench`;
  `docs/plans/0007-actors-build-faster.md`, R1).

      mix world.bench                    # each model
      mix world.bench NAME ...           # some models
      mix world.bench --level near       # far, mid (by default) or near
      mix world.bench --workers 8        # the people of each build (4)
      mix world.bench --scale 86400      # the world clock (one day in 1 ms)
      mix world.bench --clock fast       # the fast clock (world by default)
      mix world.bench --timeout 120      # the seconds of each build (600)
      mix world.bench --out bench.json   # the results as JSON too
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, names} =
      OptionParser.parse!(args,
        strict: [level: :string, workers: :integer, scale: :integer, timeout: :integer, out: :string, clock: :string]
      )

    Mix.Task.run("app.start")

    orders =
      case World.Bench.select(names) do
        {:ok, orders} -> orders
        {:error, unknown} -> Mix.raise("Not a model or a blueprint: #{Enum.join(unknown, ", ")}")
      end

    results =
      World.Bench.run(orders,
        level: Keyword.get(opts, :level, "mid"),
        workers: Keyword.get(opts, :workers, 4),
        budget: %{"clock" => Keyword.get(opts, :clock, "world")},
        scale: Keyword.get(opts, :scale, 86_400_000),
        timeout: Keyword.get(opts, :timeout, 600) * 1000,
        each: &Mix.shell().info("#{&1["name"]}: #{&1["result"]} in #{&1["ms"]} ms")
      )

    shell = Mix.shell()
    Enum.each(World.Bench.table(results), &shell.info/1)
    if opts[:out], do: File.write!(opts[:out], JSON.encode!(results))
  end
end
