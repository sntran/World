defmodule World.Skills do
  @moduledoc """
  The skills of the trades (`World.Skill`), by their names. A name in a
  drawing is a text: it finds a skill here, and it makes no atom. The
  application environment can add skills (`:world, World.Skills, extra:
  [module]`); a skill there takes the place of a skill of the same name.
  """

  alias World.Skills.{Base, Carve, Figure, Grille, Halo, Rail, Robe, Scaffold, Set, Shell, Site, SiteStep, Stair}
  alias World.Skills.{Lantern, SpiralStair, Tower, TowerBody, TowerSite}
  alias World.Skills.{CastField, CastOutside, CastSurvey, Formwork, Pour, ShellSlab}
  alias World.Skills.{Column, Course, Flight, Footing, HousePlan, Iron, Opening, Paint, Plaster, Roof, Slab}
  alias World.Skills.{VanBody, VanChassis, VanClosure, VanGlass, VanInside, VanOrder, VanSeats, VanTrim, VanUpfit}
  alias World.Skills.{BicycleFork, BicycleFrame, Crankset, Knuckle, Stand, Wheel}
  alias World.Skills.{Body, Engine, Fastener, Fork, Frame, Glass, Lamp, Panel, Seat, Spring, Swingarm}

  @skills [Base, Carve, Figure, Grille, Halo, Rail, Robe, Scaffold, Set, Shell, Site, SiteStep, Stair] ++
            [Lantern, SpiralStair, Tower, TowerBody, TowerSite] ++
            [CastField, CastOutside, CastSurvey, Formwork, Pour, ShellSlab] ++
            [Column, Course, Flight, Footing, HousePlan, Iron, Opening, Paint, Plaster, Roof, Slab] ++
            [VanBody, VanChassis, VanClosure, VanGlass, VanInside, VanOrder, VanSeats, VanTrim, VanUpfit] ++
            [BicycleFork, BicycleFrame, Crankset, Knuckle, Stand, Wheel] ++
            [Body, Engine, Fastener, Fork, Frame, Glass, Lamp, Panel, Seat, Spring, Swingarm]

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
