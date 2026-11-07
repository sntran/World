defmodule World.Skills.Scooter do
  @moduledoc """
  The data that the skills of a scooter share (`World.Skills.ScooterFrame`,
  `ScooterBody`, `ScooterSeat`, `ScooterFork`, `ScooterEngine`,
  `ScooterStand`; the blueprint `priv/blueprints/scooter_line.json`).

  A scooter is built as on the line of its maker, by the people of each
  trade at the same time: a welder makes the frame, a molder the body of
  plastic with its lights, an upholsterer the seat, mechanics the fork
  with the bars and the front wheel, and the engine with the swing arm,
  the shock and the rear wheel, and a smith the center stand. The
  drawing joins them on the ports of the frame, with their joints. Each
  skill has the data `model`: now only `honda_vision`
  (`World.Vehicles.HondaVision`).
  """
  alias World.Orders.Blueprint
  alias World.Vehicles.HondaVision

  @models %{"honda_vision" => HondaVision}

  @doc "The errors of the data of a skill of a scooter: only the key `model`."
  def check(data, path) do
    option = Blueprint.option("model", :choice, default: "honda_vision", values: Map.keys(@models))

    case Blueprint.check_options([option], data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @doc """
  The part `name` of the model of the data. The frame (the root) moves
  the scooter to its center (the extras `place`), with the sources of
  its sizes.
  """
  def make(data, "frame") do
    mod = model(data)
    extras = %{"place" => [0.0, -mod.length() / 2, 0.0], "sources" => mod.sources()}
    {mod.part("frame"), %{}, extras}
  end

  def make(data, name), do: {model(data).part(name), %{}, %{}}

  defp model(data), do: Map.fetch!(@models, Map.get(data, "model", "honda_vision"))
end
