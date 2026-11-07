defmodule World.Skills.VanBody do
  @moduledoc """
  The skill `van_body` of a sheet metal worker: the body of a van in white
  (`World.Vehicles.Van.BodyShop.body/1`), its panels pressed from steel
  sheet on the hull, with the openings cut at near. No data.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.BodyShop

  @impl true
  def name, do: "van_body"

  @impl true
  def trade, do: :sheet_metal_worker

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, :near), do: 9000
  def estimate(_data, :mid), do: 2000
  def estimate(_data, :far), do: 600

  @impl true
  def make(_data, inputs, _context), do: {BodyShop.body(Van.van(inputs).van), %{}, %{}}
end
