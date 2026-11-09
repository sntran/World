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

  With the forms of the robe (plan 0005, the node `robe` with `faces`),
  at near the outside of the statue is its forms, with their sharp edges:
  the shell keeps only its inner walls (each triangle with its middle a
  cell or more inside the solid before the hollow), for a person inside.
  """
  @behaviour World.Skill
  alias World.{Cast, Mesh, Shape, Vec}
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
    faces = get_in(inputs, ["robe", "faces"]) || []
    o = Statue.o(data, @names)
    {look, matter} = Statue.material(o.material)

    case field["surface"] do
      nil ->
        {nil, %{"meshes" => far_form(fig, o), "shell" => nil, "grid" => nil}, %{}}

      grid ->
        pieces = for name <- ctx.from, q = inputs[name]["quads"], do: q
        # The cells of the cast leave steps on a slope: the shell is relaxed.
        shell = Cast.join(grid, pieces, look, relax: 2) |> Mesh.matter(matter)

        meshes =
          if faces != [] and ctx.level == :near and field["solid"],
            do: faces ++ inner(shell, field["solid"]),
            else: [shell]

        {nil, %{"meshes" => meshes, "shell" => shell, "grid" => field["grid"]}, %{}}
    end
  end

  # The inner walls of a shell: its triangles with their middle a cell or
  # more inside the solid.
  defp inner(%Mesh{points: points, faces: faces} = shell, solid) do
    deep = Cast.erode(solid, 1)
    pts = List.to_tuple(points)

    kept =
      Enum.filter(faces, fn f ->
        mid = f |> Enum.map(&elem(pts, &1)) |> Vec.mean()
        Cast.inside?(deep, mid)
      end)

    Enum.reject([%{shell | faces: kept}], &(&1.faces == []))
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
