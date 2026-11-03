defmodule World.Materials.Laminate do
  @moduledoc """
  A laminate of glass fiber and polyester resin, laid up by hand in a
  mold (`docs/world.md`, step P6): a gel coat on the face of the mold,
  then the plies, each a fabric of glass wet with resin
  (`priv/standards/laminate.json`). The plies: `csm_300`, `csm_450`,
  `csm_600` (chopped strand mat) and `wr_600`, `wr_800` (woven roving),
  each with its mass of glass (g/m2) and its glass fraction by mass.

  The thickness of a ply of a glass mass `w` at a glass fraction `psi`:

      t = w (1 / rho_glass + (1 - psi) / (psi rho_resin))

  The mass of a ply is `w / psi`. The density of the laminate is its mass
  over its thickness: a mold shell of a laminate is a mesh with this
  density as its matter (`World.Mesh.matter/2`).
  """
  alias World.Standards

  defstruct plies: [], gel: 0.0

  @gel 0.0005

  @doc """
  A laminate: a list of plies (by their names), and the option `gel`
  (true by default: a gel coat of 0.5 mm on the face of the mold).

      iex> l = World.Materials.Laminate.new(["csm_450"], gel: false)
      iex> Float.round(World.Materials.Laminate.thickness(l) * 1000, 2)
      1.05
  """
  def new(plies, opts \\ []) when is_list(plies) and plies != [] do
    Enum.each(plies, &ply/1)
    %__MODULE__{plies: plies, gel: if(Keyword.get(opts, :gel, true), do: @gel, else: 0.0)}
  end

  @doc "The mass of glass of a ply (kg/m2) and its glass fraction. A name of no ply raises."
  def ply(name) do
    [w, psi] = Standards.size({"laminate", "plies"}, name)
    {w / 1000, psi}
  end

  @doc "The thickness of the laminate (m)."
  def thickness(%__MODULE__{} = l) do
    {g, r} = {matrix("glass"), matrix("resin")}

    l.plies
    |> Enum.map(fn name ->
      {w, psi} = ply(name)
      w * (1 / g + (1 - psi) / (psi * r))
    end)
    |> Enum.sum()
    |> Kernel./(1000)
    |> Kernel.+(l.gel)
  end

  @doc """
  The mass of a square meter of the laminate (kg/m2).

      iex> l = World.Materials.Laminate.new(["csm_450", "csm_450", "csm_450"])
      iex> Float.round(World.Materials.Laminate.areal(l), 2)
      5.11
  """
  def areal(%__MODULE__{} = l) do
    glass =
      l.plies
      |> Enum.map(fn name ->
        {w, psi} = ply(name)
        w / psi
      end)
      |> Enum.sum()

    glass + l.gel * matrix("gel_coat") * 1000
  end

  @doc "The density of the laminate (kg/m3): its mass over its thickness."
  def density(%__MODULE__{} = l), do: areal(l) / thickness(l)

  defp matrix(name), do: Standards.size({"laminate", "matrix"}, name)
end
