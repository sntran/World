defmodule World.Skills.Set do
  @moduledoc """
  The skill `set` of a sculptor: the pieces of a statue (the `meshes` of
  each node `from`, in their order: the shell, the grilles, the halo) set
  as one part on its plinth, its feet `feet` m over the ground (the base
  and the plinth). The part has the name `name`, the kind `:statue`, the
  port `o` and the sources of the model.
  """
  @behaviour World.Skill
  alias World.{Frame, Mesh, Part}
  alias World.Skills.Statue

  @names ~w(name feet)

  @impl true
  def name, do: "set"

  @impl true
  def trade, do: :sculptor

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, inputs, %{sources: sources, from: from}) do
    o = Statue.o(data, @names)
    up = Frame.move({0.0, 0.0, o.feet})
    meshes = for name <- from, m <- inputs[name]["meshes"], do: Mesh.transform(m, up)
    {Part.new(o.name, :statue, meshes, [Statue.port()], sources: sources), %{}, %{}}
  end
end
