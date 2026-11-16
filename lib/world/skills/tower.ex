defmodule World.Skills.Tower do
  @moduledoc """
  The skill `tower` of a mason: the part of a tower, of the kind
  `:tower`, from the `meshes` of its nodes `from` in their order (the
  body, then the lantern), with the name `name`, the port `o` and the
  sources of the model.
  """
  @behaviour World.Skill
  alias World.Part
  alias World.Skills.Towers

  @names ~w(name)

  @impl true
  def name, do: "tower"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: Towers.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, inputs, %{sources: sources, from: from}) do
    o = Towers.o(data, @names)
    meshes = for name <- from, m <- inputs[name]["meshes"], do: m
    {Part.new(o.name, :tower, meshes, [Towers.port()], sources: sources), %{}, %{}}
  end
end
