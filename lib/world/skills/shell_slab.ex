defmodule World.Skills.ShellSlab do
  @moduledoc """
  The skill `shell_slab` of a finisher: the surface of one slab of the
  shell of a cast (`band` of `bands`, `World.Cast.slabs/2` and
  `World.Cast.quads/2`), from its field (the node `field`). The finishers
  make all the slabs at the same time. Its data: `quads` (nil with no
  field).
  """
  @behaviour World.Skill
  alias World.Cast
  alias World.Skills.Statue

  @names ~w(band bands)

  @impl true
  def name, do: "shell_slab"

  @impl true
  def trade, do: :finisher

  # The shell of surface nets: about 2.4 triangles for each cell of its
  # surface, which is about 3.5 times the square of the cells along the
  # height (the statue on Núi Nhỏ), in `bands` slabs.
  @impl true
  def estimate(_data, :far), do: 0
  def estimate(data, :mid), do: round(2.4 * 3.5 * 56 * 56 / Map.get(data, "bands", 1))
  def estimate(data, :near), do: round(2.4 * 3.5 * 100 * 100 / Map.get(data, "bands", 1))

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def make(_data, %{"field" => %{"surface" => nil}}, _context), do: {nil, %{"quads" => nil}, %{}}

  def make(data, %{"field" => %{"surface" => grid}}, _context) do
    o = Statue.o(data, @names)

    # A band past the slabs of a small grid has no quads (an empty range).
    slab = Enum.at(Cast.slabs(grid, o.bands), o.band - 1, {1, 0})
    {nil, %{"quads" => Cast.quads(grid, slab)}, %{}}
  end
end
