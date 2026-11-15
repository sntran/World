defmodule World.Fixtures do
  @moduledoc false
  # Small models for the tests of the rules, with the functions of a
  # catalog (`World.Catalog`): a model in parts from edits (a building of
  # one storey, with the cells of the far level), an assembly with joints
  # (a seat), and a part (a wheel). The tests do not build the models of
  # the catalog.

  def models do
    [
      {"fixture_building",
       fn ->
         request = %{"name" => "fixture_building", "size" => [4, 4], "storeys" => 1}
         World.Detail.with(:far, fn -> World.Drawing.build(World.Town.Building.drawing(request)) end)
       end},
      {"fixture_seat",
       fn ->
         World.Furniture.Seats.seat("fixture_seat",
           place_width: 0.52,
           height: 0.5,
           track: 0.2,
           recline: [0, 40],
           sources: ["A seat for the tests."]
         )
       end},
      {"fixture_wheel", fn -> World.Vehicles.Wheels.spoked_wheel("37-622") end}
    ]
  end

  def kit, do: [{"kit.json", "{}"}]

  def fetch(name) do
    case List.keyfind(models(), name, 0) do
      {_, fun} -> {:ok, fun}
      nil -> :error
    end
  end
end
