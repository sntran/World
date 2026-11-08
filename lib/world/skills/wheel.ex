defmodule World.Skills.Wheel do
  @moduledoc """
  The skill `wheel` of a wheelwright (plan 0002, D5): a wheel from its
  spec sheet (`World.Vehicles.Wheels`), with its port `hub`. Its data:
  `tire` (the code of the tire: ISO `215/50R17`, `90/90-14`, or ETRTO
  `37-622`), `build` (`spoked`: wire spokes, a bicycle or a classic
  motorcycle; `cast`: a cast wheel of a scooter or a motorbike; `car`: a
  wheel of a car or a van), `spokes`, `rim_width`, `rim_depth`, `rim`
  (the material of the rim), `hub_width`, `cross`, `disc` (the diameter
  of a brake disc; a cast wheel has its own disc), `face` (`spokes` or
  `disc`: the pressed steel face of a van), `holes`, `pcd`, `lugs`,
  `sides`, and the `contents` of the wheel (the things that its shapes do
  not show: the inner tube, the sprocket, the bearings; their mass goes
  on the rim, `World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  import World.Orders.Blueprint, only: [option: 3]
  alias World.Skills.Vehicle
  alias World.Vehicles.Wheels

  @impl true
  def name, do: "wheel"

  @impl true
  def trade, do: :wheelwright

  defp options do
    n = fn name, min, max -> option(name, :number, default: nil, min: min, max: max, unit: "m") end
    i = fn name, min, max -> option(name, :integer, default: nil, min: min, max: max) end

    [
      option("tire", :data, check: &tire/2),
      option("build", :choice, values: ~w(spoked cast car)),
      i.("spokes", 1, 72),
      n.("rim_width", 0.01, 0.5),
      n.("rim_depth", 0.005, 0.1),
      option("rim", :choice, default: nil, values: ~w(aluminum steel black chrome)),
      n.("hub_width", 0.02, 0.3),
      i.("cross", 0, 4),
      n.("disc", 0.05, 0.5),
      option("face", :choice, default: "spokes", values: ~w(spokes disc)),
      i.("holes", 1, 24),
      n.("pcd", 0.05, 0.3),
      i.("lugs", 3, 10),
      i.("sides", 8, 96),
      option("contents", :data, default: nil, check: &check_contents/2)
    ]
  end

  defp tire(raw, path) do
    _ = Wheels.tire_size(raw)
    {:ok, raw}
  rescue
    _ -> {:error, [{path, "must be the code of a tire: 215/50R17, 90/90-14 or 37-622"}]}
  end

  defp check_contents(raw, path) do
    case Vehicle.check_contents(raw, path) do
      [] -> {:ok, raw}
      errors -> {:error, errors}
    end
  end

  @impl true
  def check(data, path), do: Vehicle.check(data, path, options())

  @impl true
  def estimate(_data, :near), do: 3000
  def estimate(_data, :mid), do: 800
  def estimate(_data, :far), do: 200

  @impl true
  def make(data, _inputs, _context) do
    o = Vehicle.o(data, options())
    {put_contents(build(o["build"], o["tire"], opts(o)), o["contents"]), %{}, %{}}
  end

  # The contents of the wheel go in the params of its rim (its root).
  defp put_contents(wheel, nil), do: wheel

  defp put_contents(%World.Assembly{nodes: [{name, rim, c} | rest]} = wheel, list),
    do: %{wheel | nodes: [{name, %{rim | params: Map.put(rim.params, "contents", list)}, c} | rest]}

  defp build("spoked", tire, opts), do: Wheels.spoked_wheel(tire, opts)
  defp build("cast", tire, opts), do: Wheels.cast_wheel(tire, Keyword.update(opts, :disc, false, &(&1 != nil)))
  defp build("car", tire, opts), do: Wheels.car_wheel(tire, opts)

  defp opts(o) do
    keys = [
      {"spokes", :spokes},
      {"rim_width", :rim_width},
      {"rim_depth", :rim_depth},
      {"hub_width", :hub_width},
      {"cross", :cross},
      {"disc", :disc},
      {"holes", :holes},
      {"pcd", :pcd},
      {"lugs", :lugs},
      {"sides", :sides}
    ]

    for({k, key} <- keys, o[k] != nil, do: {key, o[k]}) ++
      if(o["rim"], do: [rim_material: String.to_existing_atom(o["rim"])], else: []) ++
      if(o["face"] == "disc", do: [face: :disc], else: [])
  end
end
