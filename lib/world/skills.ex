defmodule World.Skills do
  @moduledoc """
  The skills of the trades (`World.Skill`), by their names. A name in a
  drawing is a text: it finds a skill here, and it makes no atom. The
  application environment can add skills (`:world, World.Skills, extra:
  [module]`); a skill there takes the place of a skill of the same name.
  """

  alias World.Skills.{Base, Figure, Grille, Halo, Rail, Robe, Set, Shell, Site, Stair}
  alias World.Skills.{Lantern, SpiralStair, Tower, TowerBody, TowerSite}

  @skills [Base, Figure, Grille, Halo, Rail, Robe, Set, Shell, Site, Stair] ++
            [Lantern, SpiralStair, Tower, TowerBody, TowerSite]

  @doc "The skill of a name: `{:ok, module}` or `:error`."
  def fetch(name), do: Map.fetch(all(), name)

  @doc "The names of the skills, in order."
  def names, do: all() |> Map.keys() |> Enum.sort()

  @doc "The trades of the skills."
  def trades, do: all() |> Map.values() |> Enum.map(& &1.trade()) |> Enum.uniq()

  defp all do
    extra = Keyword.get(Application.get_env(:world, __MODULE__, []), :extra, [])
    Map.new(@skills ++ extra, &{&1.name(), &1})
  end
end
