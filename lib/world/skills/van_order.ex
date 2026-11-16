defmodule World.Skills.VanOrder do
  @moduledoc """
  The skill `van_order` of an engineer: the order of a van for the line
  (`World.Skills.Van`): its model, its sizes, its doors, its windows,
  its rows of seats, and the items of DIY in the engine bay and on the
  roof (the options of the blueprint `van`). A node of data only; each
  station takes it in `from`. Its data: `line`. The model moves to the
  center of the van (the extras `place`), with the sources of its make.
  """
  @behaviour World.Skill
  alias World.Skills.Van

  @impl true
  def name, do: "van_order"

  @impl true
  def trade, do: :engineer

  @impl true
  def check(data, path), do: Van.check(data, path)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, _inputs, _context) do
    %{van: van} = line = Van.line(data)
    extras = %{"place" => [0.0, -van.l / 2, 0.0], "sources" => van.m["sources"] ++ van.make["sources"]}
    {nil, %{"line" => line}, extras}
  end
end
