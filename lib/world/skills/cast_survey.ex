defmodule World.Skills.CastSurvey do
  @moduledoc """
  The skill `cast_survey` of a surveyor: the survey of the cast of a
  statue (`World.Cast.survey/2`) from its figure and its robe (the nodes
  `figure` and `robe`): the triangles of the person that the robe does
  not cover, and of the robe, on a grid of cells of `height / 100` m at
  near and `height / 56` m at mid. The far level has no cast (nil). Its
  data: `survey`.
  """
  @behaviour World.Skill
  alias World.{Cast, Contact}
  alias World.Skills.Statue

  @names ~w(height)

  @impl true
  def name, do: "cast_survey"

  @impl true
  def trade, do: :surveyor

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, _inputs, %{level: :far}), do: {nil, %{"survey" => nil}, %{}}

  def make(data, %{"figure" => %{"figure" => fig}, "robe" => %{"meshes" => robe}}, %{level: level}) do
    o = Statue.o(data, @names)
    step = if level == :near, do: o.height / 100, else: o.height / 56
    {nil, %{"survey" => Cast.survey(uncovered(fig.surfaces, robe) ++ robe, step)}, %{}}
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
end
