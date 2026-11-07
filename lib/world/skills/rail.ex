defmodule World.Skills.Rail do
  @moduledoc """
  The skill `rail` of a mason: the rail of `rail` m round the top of the
  base of a statue (by eye from the photos): a low wall and a top rail on
  each side, and at near the balusters between them, 0.3 m apart. The
  part `lan_can` (nil with no rail, no base, or at far).
  """
  @behaviour World.Skill
  alias World.{Detail, Frame, Mesh, Part, Shape}
  alias World.Skills.Statue

  @names ~w(material rail base_width base_depth base_height)

  @impl true
  def name, do: "rail"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # The balusters of 6 sides, 0.3 m apart round the base, at near.
  @impl true
  def estimate(data, :near),
    do: round(24 * 2 * (Map.get(data, "base_width", 12.0) + Map.get(data, "base_depth", 12.0)) / 0.3) + 100

  def estimate(_data, :mid), do: 48
  def estimate(_data, :far), do: 0

  @impl true
  def make(data, _inputs, %{level: level}) do
    o = Statue.o(data, @names)
    {if(o.rail > 0 and o.base_height > 0 and level != :far, do: rail_part(o)), %{}, %{}}
  end

  defp rail_part(o) do
    level = Detail.level()
    {hw, hd, h, z} = {o.base_width / 2 - 0.3, o.base_depth / 2 - 0.3, o.rail, o.base_height}
    {look, matter} = Statue.material(o.material)

    # The four lines of the rail (their middles, 0.15 m thick).
    lines = [
      {{-hw, hd - 0.15}, {hw, hd}},
      {{-hw, -hd}, {hw, -hd + 0.15}},
      {{-hw, -hd + 0.15}, {-hw + 0.15, hd - 0.15}},
      {{hw - 0.15, -hd + 0.15}, {hw, hd - 0.15}}
    ]

    walls =
      for {{x0, y0}, {x1, y1}} <- lines do
        if level == :near,
          do: [
            Shape.box({x0, y0, z}, {x1, y1, z + 0.15}, look),
            Shape.box({x0, y0, z + h - 0.12}, {x1, y1, z + h}, look)
          ],
          else: [Shape.box({x0, y0, z}, {x1, y1, z + h}, look)]
      end

    balusters =
      for {{x0, y0}, {x1, y1}} <- lines, level == :near, n = round(max(x1 - x0, y1 - y0) / 0.3), k <- 1..(n - 1)//1 do
        {cx, cy} = {(x0 + x1) / 2, (y0 + y1) / 2}
        {x, y} = if x1 - x0 > y1 - y0, do: {x0 + (x1 - x0) * k / n, cy}, else: {cx, y0 + (y1 - y0) * k / n}
        Shape.cylinder(0.05, h - 0.27, look, sides: 6, frame: Frame.move({x, y, z + 0.15}))
      end

    shapes = Enum.map(List.flatten(walls) ++ balusters, &Mesh.matter(&1, matter))

    Part.new("lan_can", :statue, shapes, [Statue.port()],
      sources: ["The rail: #{h} m high (an estimate), by eye from the photos."]
    )
  end
end
