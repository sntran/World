defmodule Mix.Tasks.World.References do
  @shortdoc "Build the references and compare their numbers"
  @moduledoc """
  Build each reference (`World.References`, `priv/references/`) with the
  people of the node, and print each number: the real value, the value
  of the model, the error and the tolerance. It stops with an error when
  a number is out of its tolerance.

      mix world.references          # all the references
      mix world.references NAME ... # some references
  """
  use Mix.Task

  @impl true
  def run(names) do
    Mix.Task.run("app.start")
    report(if names == [], do: World.References.all(), else: Enum.map(names, &fetch!/1))
  end

  @doc "Build the references `refs`, print each number, and stop with an error on a number out of its tolerance."
  def report(refs) do
    bad =
      Enum.flat_map(refs, fn ref ->
        Mix.shell().info("\n#{ref["name"]}: #{ref["title"]}")
        rows = World.References.run(ref)
        for r <- rows, do: Mix.shell().info(line(r))
        for r <- rows, not r["ok"], do: "#{ref["name"]}: #{r["name"]}"
      end)

    if bad != [], do: Mix.raise("Out of the tolerance: " <> Enum.join(bad, ", "))
  end

  defp fetch!(name) do
    case World.References.fetch(name) do
      {:ok, ref} -> ref
      :error -> Mix.raise("No reference #{name} in priv/references")
    end
  end

  defp line(r) do
    mark = if r["ok"], do: "  ", else: "! "

    "#{mark}#{String.pad_trailing(r["name"], 28)} real #{fmt(r["value"])}  model #{fmt(r["model"])}  error #{fmt(r["error"])}  tolerance #{fmt(r["tolerance"])}"
  end

  defp fmt(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp fmt(v), do: to_string(v)
end
