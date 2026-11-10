defmodule World.Skills.Formwork do
  @moduledoc """
  The skill `formwork` of a carpenter: the forms of one band of a cast,
  from the feet up (`band` of `bands`, `World.Cast.bands/2`): the cells
  that the triangles of the band mark (`World.Cast.marks/2`), and the
  panels round the box of the band as a site sees them (plan 0006, D9):
  plywood today, timber boards in 1974 (`method`), the feet of the statue
  `feet` m over the ground. The part is temporary: the stream shows it
  until the strip, and the model leaves it out. Its data: `marks` (nil
  with no survey) and `temporary`.
  """
  @behaviour World.Skill
  alias World.{Cast, Part, Shape}
  alias World.Skills.Statue

  @names ~w(band bands feet method)
  @out 0.15
  @board 0.05

  @impl true
  def name, do: "formwork"

  @impl true
  def trade, do: :carpenter

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, %{"survey" => %{"survey" => nil}}, _context), do: {nil, %{"marks" => nil, "temporary" => true}, %{}}

  def make(data, %{"survey" => %{"survey" => s}}, %{name: name}) do
    o = Statue.o(data, @names)
    marks = Cast.marks(s, Statue.band_tris(s, o.band, o.bands))
    {{x0, y0, z0}, {x1, y1, z1}} = Statue.band_box(s, o.band, o.bands, o.feet)
    {x0, y0, x1, y1} = {x0 - @out, y0 - @out, x1 + @out, y1 + @out}
    material = if o.method == "1974", do: :wood, else: :plywood

    panels = [
      Shape.box({x0, y0 - @board, z0}, {x1, y0, z1}, material),
      Shape.box({x0, y1, z0}, {x1, y1 + @board, z1}, material),
      Shape.box({x0 - @board, y0, z0}, {x0, y1, z1}, material),
      Shape.box({x1, y0, z0}, {x1 + @board, y1, z1}, material)
    ]

    {Part.new(name, :part, panels, [Statue.port()]), %{"marks" => marks, "temporary" => true}, %{}}
  end
end
