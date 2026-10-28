defmodule World.Vehicles.Van.Kit do
  @moduledoc """
  The tools of the stations of the line of a van (`World.Vehicles.Van`):
  ports, the parts of a station, and the regions of the hull at each
  side.
  """
  alias World.{Assembly, Part}
  alias World.Vehicles.Hull

  @doc "A port, as `World.Part.port/4`."
  def port(name, at, axis, up), do: Part.port(name, at, axis, up)

  @doc "The port `origin` of a part that has the axes of the van."
  def origin, do: port("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc """
  A part that a station of the line makes: its station is in its
  `params`, so the list of the parts tells where each part comes from.
  `opts` are those of `World.Part.new/5`.
  """
  def part(station, name, kind, shapes, ports, opts \\ []) do
    {params, opts} = Keyword.pop(opts, :params, %{})
    Part.new(name, kind, shapes, ports, [params: Map.put(params, "station", station)] ++ opts)
  end

  @doc "Each part of an item (a part or an assembly) at the station."
  def station(%Part{} = p, station), do: %{p | params: Map.put(p.params, "station", station)}

  def station(%Assembly{nodes: nodes} = a, station),
    do: %{a | nodes: for({name, item, c} <- nodes, do: {name, station(item, station), c})}

  @doc """
  A skin (`World.Vehicles.Hull.skin/5`) on a region of the hull at the
  right side (x > 0) and at the left side: `planes` is a function of `d`
  to the lines of the region at the right side.
  """
  def sides(h, d0, d1, material, planes, opts) do
    for s <- [1, -1], do: Hull.skin(h, d0, d1, material, [clip: fn d -> mirror(planes.(d), s) end] ++ opts)
  end

  @doc "The lines of a region at the right side (1), or in the mirror at the left side (-1)."
  def mirror(planes, 1), do: planes

  def mirror(planes, -1) do
    for p <- planes do
      case p do
        {:x_min, v} -> {:x_max, -v}
        {:x_max, v} -> {:x_min, -v}
        other -> other
      end
    end
  end
end
