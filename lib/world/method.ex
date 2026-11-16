defmodule World.Method do
  @moduledoc """
  The method of a site (plan 0006, D6): the option `method` of an order
  (`today` by default, or `1974`) gives the rates of the crews
  (`World.Site`), the most people on the site, and the stages of the
  construction.

  - **today**: one stage that builds each node, at the first lot of the
    place.
  - **1974**: the true history of a statue (`priv/history/NAME.json`,
    the name of the order): its stages, each with its dates. A build
    makes the nodes of its `until` and the nodes they wait for; a pause
    leaves the site to get old; a change gives the order new options and
    a new lot, and takes down what it drops (`World.Construction`). With
    no history, 1974 is one stage as today, at the rates of 1974.

  The days of a stage are the days between its dates: the days of each
  task of the stage are fitted to them (`fit` of the event
  `stage_started`).
  """

  @root Path.expand("../../priv/history", __DIR__)
  @files Path.wildcard(Path.join(@root, "*.json"))
  for f <- @files, do: @external_resource(f)
  @histories Map.new(@files, &{Path.basename(&1, ".json"), &1 |> File.read!() |> JSON.decode!()})

  # The means of a site (`means/0`): how the people of the time build.
  @means %{
    "trucks" => "the trucks of the yard drive to the lot",
    "tower_crane" => "a tower crane lifts the loads (the node crane)",
    "pump" => "a pump gives the concrete to the forms",
    "steel_scaffold" => "a scaffold of steel tubes",
    "plywood_forms" => "forms of plywood",
    "carry_path" => "the people carry the materials up the path of the hill",
    "hand_mix" => "the people mix the concrete by hand on a board on the lot (the node mixing)",
    "pulley" => "a pulley on the scaffold lifts the buckets",
    "bamboo_scaffold" => "a scaffold of bamboo",
    "timber_forms" => "forms of timber boards"
  }
  @today ~w(trucks tower_crane pump steel_scaffold plywood_forms)

  @doc "The means of a site, each with what it is."
  def means, do: @means

  # The most people on a site: the 50 skilled workers of 1974
  # (`people_1974` of the history); the same for today (an estimate).
  @workers %{"today" => 50, "1974" => 50}

  # The path of the carriers goes up the hill to the top: the cape is at
  # the sea.
  defp path(order, st) do
    if "carry_path" in Map.get(st, "means", []) and String.contains?(st["place"] || "", "Núi Nhỏ"),
      do: get_in(history(order["options"]["name"]), ["path", "points"])
  end

  @doc "The history of a model by its name (`priv/history/NAME.json`), or nil."
  def history(name), do: Map.get(@histories, name)

  @doc "The method of an order: its option `method`, or `today`."
  def of(order), do: get_in(order, ["options", "method"]) || "today"

  @doc "The most people on the site of a method."
  def workers(method), do: Map.fetch!(@workers, method)

  @doc """
  The stages of an order: each a map with its `name`, its `work`
  (`build`, `pause`, `change`), its date (`date`, or nil), its first and
  last day from the start of the construction (`from`, `to`: nil with no
  date), the nodes of a
  build (`until`: a list of names or `"all"`), the options and the lot of
  a change or of the first build (`options`, `lot`), `repair` (a build
  that repairs what a pause left), `lost` (the parts that a pause
  takes), `means` (how the people of the time build, `means/0`) and
  `path` (the points of the game of the path of the carriers, with the
  means `carry_path`), `takes` (the parts that a pause takes in its first
  year) and `again` (the parts that a build makes again first).
  """
  def stages(order) do
    case {of(order), history(get_in(order, ["options", "name"]))} do
      {"1974", %{"stages" => [first | _] = stages}} ->
        start = Date.from_iso8601!(first["from"])

        for st <- stages do
          %{
            name: st["name"],
            work: st["work"],
            text: st["text"],
            place: st["place"],
            date: st["from"],
            from: Date.diff(Date.from_iso8601!(st["from"]), start),
            to: Date.diff(Date.from_iso8601!(st["to"]), start),
            until: Map.get(st, "until", "all"),
            options: st["options"],
            lot: st["lot"],
            repair: Map.get(st, "repair", false),
            lost: Map.get(st, "lost", []),
            means: Map.get(st, "means", []),
            takes: Map.get(st, "takes", []),
            again: Map.get(st, "again", []),
            path: path(order, st)
          }
        end

      _ ->
        [
          %{
            name: "build",
            work: "build",
            date: nil,
            text: nil,
            place: nil,
            from: 0,
            to: nil,
            until: "all",
            options: nil,
            lot: nil,
            repair: false,
            lost: [],
            means: if(of(order) == "today", do: @today, else: []),
            takes: [],
            again: [],
            path: nil
          }
        ]
    end
  end
end
