defmodule World.Skills.TowerSite do
  @moduledoc """
  The skill `tower_site` of a surveyor: the data of a tower for an app,
  into the extras of the model (`World.Skills.Towers`). A tower is built
  on its site (`"site"`: no check of a stand). The `light` for the app
  (its color, flashes, period and range, or nil). The ports: the light in
  the lantern, the door at the foot, and a view on the gallery. The
  collision boxes: the platform, the foot, the body with its pilasters,
  the gallery and the top. The corners of the platform, for the data of
  the surface.
  """
  @behaviour World.Skill
  alias World.Vec
  alias World.Skills.Towers

  @names ~w(height platform_width platform_height body foot across flare gallery gallery_width rail lantern_from lantern_to lantern_width door_width door_height door_angle light)

  @impl true
  def name, do: "tower_site"

  @impl true
  def trade, do: :surveyor

  @impl true
  def check(data, path), do: Towers.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, _inputs, _context) do
    o = Towers.o(data, @names)
    {d, _} = o.platform
    r = d / 2

    extras = %{
      "site" => true,
      "light" => o.light,
      "ports" => ports(o),
      "collision" => collision(o),
      "surface" => %{"corners" => [[-r, -r], [r, -r], [-r, r], [r, r]]}
    }

    {nil, %{}, extras}
  end

  defp port(kind, at, normal, size),
    do: %{"kind" => kind, "at" => Vec.float(at), "normal" => Vec.float(normal), "size" => size}

  defp ports(o) do
    {la, lb, _} = o.lantern
    {_, z0} = o.platform
    {dw, dh} = o.door
    a = o.door_angle * :math.pi() / 180
    out = {:math.cos(a), :math.sin(a), 0.0}

    [
      port("light", {0.0, 0.0, (la + lb) / 2}, {0.0, 0.0, 1.0}, [0.9, 0.9, 1.0]),
      port("door", Vec.add(Vec.scale(out, o.body / 2), {0.0, 0.0, z0}), out, [dw, 0.3, dh]),
      port("view", {0.0, o.gallery_width / 2 - 0.5, o.gallery}, {0.0, 0.0, 1.0}, [1.5, 0.8, 2.0])
    ]
  end

  defp collision(o) do
    {d, ph} = o.platform
    {_, lb, ld} = o.lantern

    box = fn name, {x0, y0, z0}, {x1, y1, z1} ->
      %{"name" => name, "at" => {(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2}, "size" => {x1 - x0, y1 - y0, z1 - z0}}
    end

    {f, a, g} = {o.foot / 2, o.across / 2, o.gallery_width / 2}

    [
      box.("nen", {-d / 2, -d / 2, 0.0}, {d / 2, d / 2, ph}),
      box.("chan", {-f, -f, ph}, {f, f, ph + o.flare}),
      box.("than", {-a, -a, ph + o.flare}, {a, a, o.gallery}),
      box.("ban_cong", {-g, -g, o.gallery - 0.3}, {g, g, o.gallery + o.rail}),
      box.("den", {-ld / 2, -ld / 2, o.gallery}, {ld / 2, ld / 2, max(lb, o.height)})
    ]
  end
end
