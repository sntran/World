defmodule World.Skills.SiteStep do
  @moduledoc """
  The skill `site_step` (plan 0006, D9): a step of a site with no part,
  as the strip of the forms of a band or the fall of a scaffold. Its work
  and its trade are in its node (`work`, `trade`); a node that it takes
  down names it in its `down`.
  """
  @behaviour World.Skill

  @impl true
  def name, do: "site_step"

  @impl true
  def trade, do: :builder

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, _inputs, _context), do: {nil, %{}, %{}}
end
