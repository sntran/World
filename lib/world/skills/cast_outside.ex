defmodule World.Skills.CastOutside do
  @moduledoc """
  The skill `cast_outside` of a caster: the marks of all the forms (the
  nodes `from` after the survey) as one, and the cells outside the cast
  (`World.Cast.outside/2`). Its data: `marks` and `outside` (nil with no
  survey).
  """
  @behaviour World.Skill
  alias World.Cast

  @impl true
  def name, do: "cast_outside"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, %{"survey" => %{"survey" => nil}}, _context), do: {nil, %{"marks" => nil, "outside" => nil}, %{}}

  def make(_data, %{"survey" => %{"survey" => s}} = inputs, %{from: from}) do
    marks = for(name <- from, name != "survey", do: inputs[name]["marks"]) |> Enum.reduce(MapSet.new(), &MapSet.union/2)
    {nil, %{"marks" => marks, "outside" => Cast.outside(s, marks)}, %{}}
  end
end
