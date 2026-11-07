defmodule World.Skills.Shell do
  @moduledoc """
  The skill `shell` of a caster: the cast of a statue (`World.Cast`) from
  its figure and its robe (the nodes `figure` and `robe`), as one closed
  shell with no gap between the body, the robe, the head, the hair and
  the hands. The cells of the cast are `height / 100` m at near and
  `height / 56` m at mid. With `hollow`, the near level has walls of
  `wall` m (at the least two cells) and openings: the `windows` in the
  front of the robe, a balcony at each shoulder, and the shaft of the
  stair (round the well of `well` m) down into the base. The far level is
  the far form: the silhouette from 3 km in few triangles (R9 of plan
  0008 of Vũng Tàu).

  Its data: `meshes` (the shell, or the far form), `shell` (the mesh of
  the shell, for the grilles of its windows) and `grid` (the cells of the
  cast, for the stair).
  """
  @behaviour World.Skill
  alias World.{Cast, Contact, Mesh, Shape}
  alias World.Skills.Statue

  @names ~w(height hand material hollow wall well windows)

  @impl true
  def name, do: "shell"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # A shell of surface nets: about 2.4 triangles for each cell of its
  # surface, which is about 3.5 times the square of the cells along the
  # height (the statue on Núi Nhỏ).
  @impl true
  def estimate(_data, :far), do: 80
  def estimate(_data, :mid), do: round(2.4 * 3.5 * 56 * 56)
  def estimate(_data, :near), do: round(2.4 * 3.5 * 100 * 100)

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}} = inputs, %{level: level}) do
    o = Statue.o(data, @names)
    {look, matter} = Statue.material(o.material)

    case level do
      :far ->
        {nil, %{"meshes" => far_form(fig, o), "shell" => nil, "grid" => nil}, %{}}

      _ ->
        step = if level == :near, do: o.height / 100, else: o.height / 56
        robe = inputs["robe"]["meshes"]
        grid = Cast.solid(uncovered(fig.surfaces, robe) ++ robe, step)

        grid =
          if o.hollow and level == :near,
            do: Cast.hollow(grid, max(o.wall, 2 * step), openings(fig, o, step)),
            else: grid

        shell = Cast.mesh(grid, look) |> Mesh.matter(matter)
        {nil, %{"meshes" => [shell], "shell" => shell, "grid" => grid}, %{}}
    end
  end

  # The surfaces of the person with no triangle that the robe covers (its
  # three points in the robe): the cast takes the head, the hair out of
  # the robe and the feet, not a chest close under the robe.
  defp uncovered(surfaces, []), do: surfaces

  defp uncovered(surfaces, robe) do
    solids = Enum.map(robe, &Contact.solid/1)

    for {points, tris} <- surfaces do
      covered = points |> Enum.map(&Contact.blocked?(&1, solids)) |> List.to_tuple()
      {points, Enum.reject(tris, fn [a, b, c] -> elem(covered, a) and elem(covered, b) and elem(covered, c) end)}
    end
  end

  # The openings of a hollow statue: the windows in the front of the robe,
  # a balcony in the top of each arm near the shoulder, and the shaft of
  # the stair down to the plinth.
  defp openings(%{marks: m, scale: s}, o, step) do
    xs = abs(elem(m["upperarm_l"], 0))
    za = elem(m["upperarm_l"], 2)
    r = o.well / 2 + 0.8

    windows = for {z, w, h} <- o.windows, do: {{-w / 2, 0.0, z - h / 2}, {w / 2, 50.0, z + h / 2}}

    balconies =
      for side <- [-1.0, 1.0] do
        {x0, x1} = {side * (xs + 1.0), side * (xs + 2.5)}
        {{min(x0, x1), -0.8, za}, {max(x0, x1), 0.8, za + 10.0}}
      end

    yc = 0.01 * s
    shaft = {{-r, yc - r, -2.0 * step}, {r, yc + r, 2.5 * step}}
    windows ++ balconies ++ [shaft]
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
