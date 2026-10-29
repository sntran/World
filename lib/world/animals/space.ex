defmodule World.Animals.Space do
  @moduledoc """
  The shape space of a template (`priv/animals/spaces/MESH.json`, from
  `scripts/shape_space.exs`): the shape changes of other templates that
  the numbers of a shape do not give, as a mean and principal
  components (as SMAL for animals).

  A move of each point of the template is in the axes of the bone that
  moves the point most, in the units of the template; `World.Animals.Shape`
  scales it as that bone. The coefficients of a shape give the moves:
  the mean, and for each component its coefficient × its standard
  deviation (`sigma`) × the component. The file has the numbers and the
  coefficients of each template that the space comes from.
  """

  @root Path.join([:code.priv_dir(:world), "animals", "spaces"])
  @files Path.wildcard(Path.join(@root, "*.json"))
  for f <- @files, do: @external_resource(f)
  @spaces Map.new(@files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)

  @doc false
  def __mix_recompile__?, do: Path.wildcard(Path.join(@root, "*.json")) != @files

  @doc "The shape space of a mesh, or nil."
  def get(mesh), do: @spaces[mesh]

  @doc """
  The move of each point (`{x, y, z}`) of the space for the coefficients
  `cs` (fewer than the components: the others are 0).
  """
  def moves(%{"mean" => mean, "components" => components}, cs) do
    for {c, %{"sigma" => sigma, "vectors" => vectors}} <- Enum.zip(cs, components), reduce: mean do
      acc ->
        Enum.zip_with(acc, vectors, fn [a, b, d], [x, y, z] ->
          [a + c * sigma * x, b + c * sigma * y, d + c * sigma * z]
        end)
    end
    |> Enum.map(&List.to_tuple/1)
  end
end
