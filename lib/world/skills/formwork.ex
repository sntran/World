defmodule World.Skills.Formwork do
  @moduledoc """
  The skill `formwork` of a carpenter: the forms of one band of a cast,
  from the feet up (`band` of `bands`, `World.Cast.bands/2`): the cells
  that the triangles of the band mark (`World.Cast.marks/2`). The
  carpenters set the forms of all the bands at the same time. Its data:
  `marks` (nil with no survey).
  """
  @behaviour World.Skill
  alias World.Cast
  alias World.Skills.Statue

  @names ~w(band bands)

  @impl true
  def name, do: "formwork"

  @impl true
  def trade, do: :carpenter

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"survey" => %{"survey" => s}}, _context) do
    o = Statue.o(data, @names)
    {nil, %{"marks" => s && Cast.marks(s, Enum.at(Cast.bands(s, o.bands), o.band - 1, []))}, %{}}
  end
end
