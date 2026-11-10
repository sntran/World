defmodule World.Skills.Scaffold do
  @moduledoc """
  The skill `scaffold` of a scaffolder (plan 0006, D9): the scaffold of
  one band of a cast (`band` of `bands`, from the feet up), round the box
  of the triangles of the band (`World.Cast.bands/2`), 1.2 m out: a pole
  each 1.8 m or less on each side, and a ledger each 2 m up. Steel tubes
  with the method of today, bamboo with 1974 (`method`). The feet of the
  statue are `feet` m over the ground. The part is temporary: the stream
  shows it, the model leaves it out. Its data: `temporary`. The far level
  has no cast, so no scaffold. With 1974 a pulley on the top of the
  scaffold lifts the buckets (no source: an estimate).
  """
  @behaviour World.Skill
  alias World.{Part, Shape}
  alias World.Skills.Statue

  @names ~w(band bands feet method)
  @out 1.2
  @pole 0.05

  @impl true
  def name, do: "scaffold"

  @impl true
  def trade, do: :scaffolder

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, :far), do: 0
  def estimate(_data, _level), do: 600

  @impl true
  def make(_data, %{"survey" => %{"survey" => nil}}, _context), do: {nil, %{"temporary" => true}, %{}}

  def make(data, %{"survey" => %{"survey" => s}}, %{name: name}) do
    o = Statue.o(data, @names)
    {{x0, y0, z0}, {x1, y1, z1}} = Statue.band_box(s, o.band, o.bands, o.feet)
    {x0, y0, x1, y1} = {x0 - @out, y0 - @out, x1 + @out, y1 + @out}
    material = if o.method == "1974", do: :bamboo, else: :steel
    corners = [{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}]
    sides = Enum.zip(corners, tl(corners) ++ [hd(corners)])

    poles =
      for {{ax, ay}, {bx, by}} <- sides,
          n = max(1, ceil(:math.sqrt((bx - ax) ** 2 + (by - ay) ** 2) / 1.8)),
          k <- 0..(n - 1) do
        {x, y} = {ax + (bx - ax) * k / n, ay + (by - ay) * k / n}
        Shape.box({x - @pole, y - @pole, z0}, {x + @pole, y + @pole, z1}, material)
      end

    ledgers =
      for z <- levels(z0, z1), {{ax, ay}, {bx, by}} <- sides do
        Shape.box(
          {min(ax, bx) - @pole, min(ay, by) - @pole, z - @pole},
          {max(ax, bx) + @pole, max(ay, by) + @pole, z + @pole},
          material
        )
      end

    {Part.new(name, :part, poles ++ ledgers ++ pulley(o.method, {x0, y0, x1, y1}, z0, z1), [Statue.port()]),
     %{"temporary" => true}, %{}}
  end

  # The pulley of a site with no crane (1974, an estimate): a timber beam
  # out of the back of the top of the scaffold, its rope down the band
  # (the rope of the band under it goes on) and a bucket on it. The
  # machines of today need none.
  defp pulley("1974", {x0, _y0, x1, y1}, z0, z1) do
    x = (x0 + x1) / 2
    beam = Shape.box({x - 0.06, y1 - 0.3, z1 - 0.06}, {x + 0.06, y1 + 1.5, z1 + 0.06}, :wood)
    wheel = Shape.box({x - 0.04, y1 + 1.3, z1 - 0.25}, {x + 0.04, y1 + 1.5, z1 - 0.06}, :iron)
    rope = Shape.box({x - 0.01, y1 + 1.39, z0}, {x + 0.01, y1 + 1.41, z1 - 0.25}, :rope)
    mid = (z0 + z1) / 2
    bucket = Shape.box({x - 0.15, y1 + 1.25, mid}, {x + 0.15, y1 + 1.55, mid + 0.3}, :black)
    [beam, wheel, rope, bucket]
  end

  defp pulley(_method, _box, _z0, _z1), do: []

  # A ledger each 2 m over the foot of the band, and one at its top: the
  # ledger at its foot is the top of the band under it.
  defp levels(z0, z1), do: Enum.take_while(Stream.iterate(z0 + 2.0, &(&1 + 2.0)), &(&1 < z1 - 0.5)) ++ [z1]
end
