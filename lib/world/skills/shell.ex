defmodule World.Skills.Shell do
  @moduledoc """
  The skill `shell` of a caster: the shell of a statue, one closed mesh,
  from the slabs of its surface (the nodes `from` with `quads`, in their
  order; `World.Cast.join/3`) and the field of its cast (the node
  `field`). The far level is the far form of the figure (the node
  `figure`): the silhouette from 3 km in few triangles (R9 of plan 0008
  of Vũng Tàu). Its data: `meshes` (the shell, or the far form), `shell`
  (the mesh of the shell, for the grilles of its windows) and `grid` (the
  cells of the cast, for the stair).
  """
  @behaviour World.Skill
  alias World.{Cast, Mesh, Shape}
  alias World.Skills.Statue

  @names ~w(hand material)

  @impl true
  def name, do: "shell"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, :far), do: 80
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}, "field" => field} = inputs, ctx) do
    o = Statue.o(data, @names)
    {look, matter} = Statue.material(o.material)

    case field["surface"] do
      nil ->
        {nil, %{"meshes" => far_form(fig, o), "shell" => nil, "grid" => nil}, %{}}

      grid ->
        pieces = for name <- ctx.from, q = inputs[name]["quads"], do: q
        shell = Cast.join(grid, pieces, look) |> Mesh.matter(matter)
        {nil, %{"meshes" => [shell], "shell" => shell, "grid" => field["grid"]}, %{}}
    end
  end

  # The far form: the robe, the arms from hand to hand, the head.
  defp far_form(%{marks: m, scale: s, top: top}, o) do
    {look, matter} = Statue.material(o.material)
    sh = elem(m["upperarm_l"], 2)
    neck = elem(m["head"], 2)
    tip = abs(elem(m["hand_l"], 0)) + (o.hand || 0.18 * s)

    column =
      Shape.loft(
        for(
          {z, hx, hy} <- [{0.0, 0.215, 0.135}, {sh / s, 0.215, 0.13}, {neck / s, 0.07, 0.07}],
          do: {{0.0, 0.01 * s, z * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hx * s, hy * s, 3.5}
        ),
        look,
        sides: 8
      )

    za = (elem(m["hand_l"], 2) + sh) / 2

    arms =
      Shape.box({-tip, -0.07 * s, za - 0.07 * s}, {tip, 0.07 * s, za + 0.07 * s}, look)

    head = Shape.box({-0.08 * s, -0.09 * s, neck}, {0.08 * s, 0.11 * s, top}, look)
    Enum.map([column, arms, head], &Mesh.matter(&1, matter))
  end
end
