defmodule World.Skills.Pour do
  @moduledoc """
  The skill `pour` of a caster: the pour of one band of a cast from the
  feet up (`band` of `bands`): the distances of its triangles near the
  outer surface (`World.Cast.distances/4`), with the survey and the
  outside of the cast. The casters pour all the bands at the same time,
  in any order: one field (`World.Cast.merge/1`). Its data: `distances`
  (nil with no survey). Its part is the band as a site sees it after the
  pour (plan 0006, D9): the rough grey concrete of the triangles of the
  band, the feet of the statue `feet` m over the ground; it is temporary,
  and the render of washed stone covers it at the end (`down`).
  """
  @behaviour World.Skill
  alias World.{Cast, Mesh, Part}
  alias World.Skills.Statue

  @names ~w(band bands feet)

  @impl true
  def name, do: "pour"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, %{"survey" => %{"survey" => nil}}, _context),
    do: {nil, %{"distances" => nil, "temporary" => true}, %{}}

  def make(data, %{"survey" => %{"survey" => s}, "outside" => %{"marks" => marks, "outside" => out}}, %{name: name}) do
    o = Statue.o(data, @names)
    band = Statue.band_tris(s, o.band, o.bands)
    # The concrete of the band: each triangle of the cast cut to the
    # heights of the band (`World.Skills.Statue.band_box/4`).
    {{_, _, z0}, {_, _, z1}} = Statue.band_box(s, o.band, o.bands, 0.0)
    tris = for t <- Tuple.to_list(s.tris), piece <- clip(Tuple.to_list(t), z0, z1), do: piece
    points = for {a, b, c} <- tris, {x, y, z} <- [a, b, c], do: {x, y, z + o.feet}
    faces = for i <- 0..(length(tris) - 1)//1, do: [3 * i, 3 * i + 1, 3 * i + 2]

    part =
      if tris == [],
        do: nil,
        else: Part.new(name, :part, [Mesh.new(points, faces, :concrete, angle: 60.0)], [Statue.port()])

    {part, %{"distances" => Cast.distances(s, marks, out, band), "temporary" => true}, %{}}
  end

  # A triangle cut to the heights z0 to z1: the triangles of the polygon
  # that is left (none when it is all out).
  defp clip(tri, z0, z1) do
    poly = tri |> cut(fn {_, _, z} -> z - z0 end) |> cut(fn {_, _, z} -> z1 - z end)

    case poly do
      [a | rest] when length(rest) >= 2 -> for [b, c] <- Enum.chunk_every(rest, 2, 1, :discard), do: {a, b, c}
      _ -> []
    end
  end

  # The part of a polygon where `side` is 0 or more (Sutherland-Hodgman).
  defp cut([], _side), do: []

  defp cut(poly, side) do
    poly
    |> Enum.zip(tl(poly) ++ [hd(poly)])
    |> Enum.flat_map(fn {p, q} ->
      {a, b} = {side.(p), side.(q)}

      cond do
        a >= 0 and b >= 0 -> [q]
        a >= 0 -> [World.Vec.lerp(p, q, a / (a - b))]
        b >= 0 -> [World.Vec.lerp(p, q, a / (a - b)), q]
        true -> []
      end
    end)
  end
end
