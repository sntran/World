defmodule World.Skills.CastOutside do
  @moduledoc """
  The skill `cast_outside` of a caster: the marks of all the bands of
  the cast (`bands`, `World.Cast.marks/2`, the marks of the forms of each
  band) as one, and the cells outside the cast (`World.Cast.outside/2`).
  Its data: `marks`, `outside`, the indices of the triangles of each band
  (`bands`) and the box of each band on a site (`boxes`,
  `World.Skills.Statue.band_boxes/2`), each nil with no survey. It needs the
  survey only, so on the site the form of a band can wait for the pour
  of the band under it (plan 0006, D2).
  """
  @behaviour World.Skill
  alias World.Cast

  @impl true
  def name, do: "cast_outside"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path), do: World.Skills.Statue.check(data, path, ~w(bands))

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, %{"survey" => %{"survey" => nil}}, _context),
    do: {nil, %{"marks" => nil, "outside" => nil, "bands" => nil, "boxes" => nil}, %{}}

  def make(data, %{"survey" => %{"survey" => s}}, _context) do
    bands = Cast.bands(s, World.Skills.Statue.o(data, ~w(bands)).bands)
    marks = for(band <- bands, do: Cast.marks(s, band)) |> Enum.reduce(MapSet.new(), &MapSet.union/2)
    boxes = World.Skills.Statue.band_boxes(s, bands)
    {nil, %{"marks" => marks, "outside" => Cast.outside(s, marks), "bands" => bands, "boxes" => boxes}, %{}}
  end
end
