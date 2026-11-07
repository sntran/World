defmodule World.Skill do
  @moduledoc """
  A skill: the work of a trade on its data, as a person of the trade does
  it on a site (`docs/plans/0001-people-build-on-demand.md`, D8, R9). A
  node of a drawing names a skill and gives its data (`World.Drawing`);
  the person that does the task of the node runs it.

  A skill is pure: no clock, no random number, so a job gives the same
  bytes each time. Others can write a skill, or a better skill of the
  same name (`World.Skills`).
  """

  @typedoc "An error of the data: its path and its message."
  @type error :: {String.t(), String.t()}

  @typedoc """
  The context of a make: the level of detail, the sources of the model,
  the names of the nodes `from`, in their order, and the name of the node.
  """
  @type context :: %{level: :near | :mid | :far, sources: [String.t()], from: [String.t()], name: String.t()}

  @doc "The name of the skill in a drawing."
  @callback name() :: String.t()

  @doc "The trade of the people that have the skill."
  @callback trade() :: atom()

  @doc "The errors of the data of a node, each with its path."
  @callback check(data :: term(), path :: String.t()) :: [error()]

  @doc """
  Make the element: the data of the node, the data of its nodes `from`
  by their names, and the context. Gives the part (or an assembly, or nil
  for data only), the data for the nodes that take it, and the extras of
  the model.
  """
  @callback make(data :: map(), inputs :: %{String.t() => map()}, context()) ::
              {World.Part.t() | World.Assembly.t() | nil, map(), map()}

  @doc "The triangles of the element at a level: an estimate, before the make."
  @callback estimate(data :: map(), level :: atom()) :: non_neg_integer()

  @doc """
  The takeoff of the task: the materials of the stock of the warehouse
  that it needs (a name of `priv/places.json` to a count of its units),
  from its data and the data of its nodes `from`. The trucks bring them
  to the place of the construction before the task starts (plan 0002,
  D6). A skill with no takeoff needs nothing of the stock.
  """
  @callback materials(data :: map(), inputs :: %{String.t() => map()}) :: %{String.t() => non_neg_integer()}

  @optional_callbacks materials: 2

  @doc """
  The errors of the data of a skill: an object with only the keys
  `known`, and each key of `required`.
  """
  def keys(data, path, known, required \\ [])

  def keys(data, path, known, required) when is_map(data) do
    for(k <- Enum.sort(Map.keys(data)), k not in known, do: {"#{path}.#{k}", "is not a key"}) ++
      for k <- required, not Map.has_key?(data, k), do: {"#{path}.#{k}", "is required"}
  end

  def keys(_data, path, _known, _required), do: [{path, "must be an object"}]
end
