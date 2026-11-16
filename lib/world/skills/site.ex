defmodule World.Skills.Site do
  @moduledoc """
  The skill `site` of a surveyor: the data of a statue for an app, from
  the marks of its figure (the node `figure`), into the extras of the
  model. A statue is cast fixed to its site (`"site"`: no check of a
  stand). The ports: a light at each corner of the top of the base (the
  lamps that light the statue at night), the door of the base at its
  back, and with `hollow` the foot of the stair and a view at each
  balcony. The collision boxes: the base, the plinth, the robe, the arms
  and the head (the halo and the rays have none: a player does not reach
  them). With `base_room`, the base is a room that a player walks into:
  the foot of the stair is on its floor, and the base has a box for each
  wall (the back in two, at the two sides of the door) and its roof. The
  corners of the base, for the data of the surface.
  """
  @behaviour World.Skill
  alias World.Vec
  alias World.Skills.Statue

  @names ~w(hand hollow well base_width base_depth base_height plinth_radius feet base_room)

  @impl true
  def name, do: "site"

  @impl true
  def trade, do: :surveyor

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}}, _context) do
    o = Statue.o(data, @names)
    {hw, hd} = {o.base_width / 2, o.base_depth / 2}

    extras = %{
      "site" => true,
      "ports" => ports(fig, o),
      "collision" => collision(fig, o),
      "surface" => %{"corners" => [[-hw, -hd], [hw, -hd], [-hw, hd], [hw, hd]]}
    }

    {nil, %{}, extras}
  end

  defp port(kind, at, normal, size),
    do: %{"kind" => kind, "at" => Vec.float(at), "normal" => Vec.float(normal), "size" => size}

  defp ports(%{marks: m}, o) do
    {hw, hd, h} = {o.base_width / 2 - 0.5, o.base_depth / 2 - 0.5, o.base_height}

    lights =
      for x <- [-hw, hw], y <- [-hd, hd], do: port("light", {x, y, h}, {-x, -y, 3 * hw} |> Vec.norm(), [0.3, 0.3, 0.3])

    door = port("door", {0.0, -o.base_depth / 2, 0.0}, {0.0, -1.0, 0.0}, [1.2, 0.2, 2.4])

    inside =
      if o.hollow do
        xs = abs(elem(m["upperarm_l"], 0))
        za = elem(m["upperarm_l"], 2) + o.feet

        foot = if o.base_room, do: 0.6, else: o.feet

        [port("stair", {0.0, 0.0, foot}, {0.0, 0.0, 1.0}, [o.well + 1.6, o.well + 1.6, 2.0])] ++
          for side <- [-1.0, 1.0], do: port("view", {side * (xs + 1.75), 0.0, za}, {0.0, 0.0, 1.0}, [1.5, 1.6, 2.0])
      else
        []
      end

    lights ++ [door | inside]
  end

  defp collision(%{marks: m, scale: s, top: top}, o) do
    lift = o.feet

    box = fn name, {x0, y0, z0}, {x1, y1, z1} ->
      %{"name" => name, "at" => {(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2}, "size" => {x1 - x0, y1 - y0, z1 - z0}}
    end

    {hw, hd, r} = {o.base_width / 2, o.base_depth / 2, o.plinth_radius}
    sh = elem(m["upperarm_l"], 2) + lift
    tip = abs(elem(m["hand_l"], 0)) + (o.hand || 0.18 * s)
    neck = elem(m["head"], 2) + lift
    za = (elem(m["hand_l"], 2) + elem(m["upperarm_l"], 2)) / 2 + lift

    base =
      if o.base_room do
        {h, t} = {o.base_height, 0.3}

        [
          box.("be_truoc", {-hw, hd - t, 0.0}, {hw, hd, h}),
          box.("be_sau_trai", {-hw, -hd, 0.0}, {-0.7, -hd + t, h}),
          box.("be_sau_phai", {0.7, -hd, 0.0}, {hw, -hd + t, h}),
          box.("be_trai", {-hw, -hd, 0.0}, {-hw + t, hd, h}),
          box.("be_phai", {hw - t, -hd, 0.0}, {hw, hd, h}),
          box.("be_mai", {-hw, -hd, h - 0.5}, {hw, hd, h})
        ]
      else
        [box.("be", {-hw, -hd, 0.0}, {hw, hd, o.base_height})]
      end

    (base ++
       [
         box.("de", {-r, -r, o.base_height}, {r, r, lift}),
         box.("ao", {-0.215 * s, -0.125 * s, lift}, {0.215 * s, 0.145 * s, sh}),
         box.("tay", {-tip, -0.1 * s, za - 0.1 * s}, {tip, 0.1 * s, za + 0.1 * s}),
         box.("dau", {-0.09 * s, -0.1 * s, neck}, {0.09 * s, 0.12 * s, top + lift})
       ])
    |> Enum.filter(fn %{"size" => {_, _, h}} -> h > 0 end)
    |> Enum.map(fn b ->
      Map.new(b, fn {k, v} ->
        {k, if(is_tuple(v), do: Tuple.to_list(v) |> Enum.map(&Float.round(&1 / 1, 4)) |> List.to_tuple(), else: v)}
      end)
    end)
  end
end
