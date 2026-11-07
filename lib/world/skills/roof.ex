defmodule World.Skills.Roof do
  @moduledoc """
  The skill `roof` of a roofer: the roof of a house over its top floor
  (`World.Skills.House`): a terrace with a parapet of `parapet` m round
  it (a wall of 110 mm with its render), and with the roof `metal` a
  roof of corrugated steel over the terrace, from 2.4 m at the front to
  1.8 m at the back, on four posts of steel (the common roof of a tube
  house; the heights are estimates).
  """
  @behaviour World.Skill
  alias World.Buildings.Panel
  alias World.Skills.House

  @impl true
  def name, do: "roof"

  @impl true
  def trade, do: :roofer

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, _level), do: 200

  @impl true
  def make(_data, %{"plan" => %{"plan" => plan}}, %{name: name, level: level}) do
    {hw, hd, z} = {plan.width / 2, plan.depth / 2, House.top(plan, plan.floors)}
    {p, t} = {plan.parapet, 0.11}

    parapet =
      if p <= 0 do
        []
      else
        [
          House.box({-hw, hd - t, z}, {hw, hd, z + p}, :plaster, :brick),
          House.box({-hw, -hd, z}, {hw, -hd + t, z + p}, :plaster, :brick),
          House.box({-hw, -hd + t, z}, {-hw + t, hd - t, z + p}, :plaster, :brick),
          House.box({hw - t, -hd + t, z}, {hw, hd - t, z + p}, :plaster, :brick)
        ]
      end

    metal =
      if plan.roof == "metal" do
        {front, back} = {z + 2.4, z + 1.8}
        len = :math.sqrt(plan.depth * plan.depth + (front - back) * (front - back))
        v = {0.0, plan.depth / len, (front - back) / len}
        ribs = fn a, _ -> 0.012 * (1 - :math.cos(2 * :math.pi() * a / 0.11)) end
        far = level == :far

        sheet =
          Panel.sheet({-hw - 0.2, -hd, back}, {1.0, 0.0, 0.0}, v, plan.width + 0.4, len, [], :roof_corrugated,
            skin: {0.002, :steel},
            us: if(far, do: [], else: for(k <- 1..round((plan.width + 0.4) / 0.055), do: k * 0.055)),
            relief: if(far, do: nil, else: ribs)
          )

        posts =
          for x <- [-hw + 0.1, hw - 0.1],
              {y, h} <- [{hd - 0.1, front}, {-hd + 0.1, back}],
              do: House.box({x - 0.03, y - 0.03, z}, {x + 0.03, y + 0.03, h}, :iron, :steel)

        if far, do: [sheet], else: [sheet | posts]
      else
        []
      end

    case parapet ++ metal do
      [] -> {nil, %{}, %{}}
      meshes -> {House.part(name, meshes, ["The roof: a parapet of #{p} m, and #{plan.roof} (estimates)."]), %{}, %{}}
    end
  end
end
