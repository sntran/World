defmodule Mix.Tasks.World.Review do
  @shortdoc "Reviews a proposal of a new drawing (docs/world.md, step P9)"
  @moduledoc """
  The review of a proposal of an engineer (`World.Engineers`): a drawing
  for a request, from the store (its hash) or from a JSON file.

      mix world.review HASH                  # the proposal in the store
      mix world.review PROPOSAL.json         # a proposal in a file
      mix world.review HASH --accept         # into priv/drawings/NAME.json

  The task shows the request, the name, the parts, the mass, the size and
  the checks of the drawing, from a new review (`World.Engineers.review/1`:
  the code of today, not that of the proposal). With `--accept` the
  drawing goes into `priv/drawings/` (or `--dir DIR`), only when the new
  review passes: the owner then commits it, and the catalog has it. To
  refuse a proposal, do not accept it: nothing changes.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, sources} = OptionParser.parse!(args, strict: [accept: :boolean, dir: :string])
    Mix.Task.run("compile")

    proposal =
      case sources do
        [source] -> load(source)
        _ -> Mix.raise("Give one proposal: mix world.review HASH or mix world.review PROPOSAL.json")
      end

    {status, review} = World.Engineers.review(proposal["drawing"])
    Mix.shell().info(sheet(proposal["request"], review))

    cond do
      not Keyword.get(opts, :accept, false) ->
        :ok

      status != :ok ->
        Mix.raise("The drawing does not pass its review: it stays out of the catalog.")

      true ->
        case World.Engineers.accept(proposal, Keyword.get(opts, :dir, "priv/drawings")) do
          {:ok, path} -> Mix.shell().info("Accepted: #{path}. Commit it to put it into the catalog.")
          {:error, :exists} -> Mix.raise("A drawing of the name #{review["name"]} is in the catalog.")
        end
    end
  end

  defp load(source) do
    if File.regular?(source) do
      source |> File.read!() |> JSON.decode!()
    else
      case World.Engineers.proposal(source) do
        {:ok, proposal} -> proposal
        :none -> Mix.raise("No proposal #{source} in the store.")
        :error -> Mix.raise("The store of the proposals failed.")
      end
    end
  end

  @doc false
  def sheet(request, %{"errors" => [_ | _] = errors}),
    do: Enum.join(["Request: #{request}", "Errors:" | Enum.map(errors, &"  #{&1["path"]}: #{&1["message"]}")], "\n")

  def sheet(request, review) do
    parts = Enum.map(Enum.sort(review["parts"]), fn {name, n} -> "  #{n} x #{name}" end)
    checks = if review["checks"] == [], do: ["  all pass"], else: Enum.map(review["checks"], &"  #{&1}")
    unknown = review["mass"]["unknown"]

    Enum.join(
      [
        "Request: #{request}",
        "Drawing: #{review["name"]}",
        "Size: #{Enum.map_join(review["size"], " by ", &"#{&1}")} m",
        "Mass: #{review["mass"]["kg"]} kg" <>
          if(unknown == [], do: "", else: " (no mass: #{Enum.join(unknown, ", ")})"),
        "Parts:"
      ] ++ parts ++ ["Checks:"] ++ checks,
      "\n"
    )
  end
end
