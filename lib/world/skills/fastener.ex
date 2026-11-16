defmodule World.Skills.Fastener do
  @moduledoc """
  The skill `fastener` of a mechanic (plan 0002, D5): a bolt, a nut or a
  washer of ISO metric sizes (`World.Materials.Fasteners`): `kind`,
  `thread` (`M12`) and the `length` of a bolt. A bolt has the ports
  `head` and `tip`, a nut and a washer `face`.
  """
  @behaviour World.Skill
  import World.Orders.Blueprint, only: [option: 3]
  alias World.Materials.Fasteners
  alias World.Skills.Vehicle

  @impl true
  def name, do: "fastener"

  @impl true
  def trade, do: :mechanic

  defp options,
    do: [
      option("kind", :choice, values: ~w(bolt nut washer)),
      option("thread", :data, check: &thread/2),
      option("length", :number, default: 0.05, min: 0.005, max: 0.5, unit: "m")
    ]

  defp thread(raw, path) do
    _ = Fasteners.nut(raw)
    {:ok, raw}
  rescue
    _ -> {:error, [{path, "must be an ISO metric thread: M6, M8, M12"}]}
  end

  @impl true
  def check(data, path), do: Vehicle.check(data, path, options())

  @impl true
  def estimate(_data, _level), do: 60

  @impl true
  def make(data, _inputs, _context) do
    o = Vehicle.o(data, options())

    part =
      case o["kind"] do
        "bolt" -> Fasteners.bolt(o["thread"], o["length"])
        "nut" -> Fasteners.nut(o["thread"])
        "washer" -> Fasteners.washer(o["thread"])
      end

    {part, %{}, %{}}
  end
end
