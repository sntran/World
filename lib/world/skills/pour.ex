defmodule World.Skills.Pour do
  @moduledoc """
  The skill `pour` of a caster: the pour of one band of a cast from the
  feet up (`band` of `bands`): the distances of its triangles near the
  outer surface (`World.Cast.distances/4`), with the survey and the
  outside of the cast. The casters pour all the bands at the same time,
  in any order: one field (`World.Cast.merge/1`). Its data: `distances`
  (nil with no survey).
  """
  @behaviour World.Skill
  alias World.Cast
  alias World.Skills.Statue

  @names ~w(band bands)

  @impl true
  def name, do: "pour"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, %{"survey" => %{"survey" => nil}}, _context), do: {nil, %{"distances" => nil}, %{}}

  def make(data, %{"survey" => %{"survey" => s}, "outside" => %{"marks" => marks, "outside" => out}}, _context) do
    o = Statue.o(data, @names)
    band = Enum.at(Cast.bands(s, o.bands), o.band - 1, [])
    {nil, %{"distances" => Cast.distances(s, marks, out, band)}, %{}}
  end
end
