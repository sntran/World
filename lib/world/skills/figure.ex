defmodule World.Skills.Figure do
  @moduledoc """
  The skill `figure` of a sculptor: the posed person of a statue, as data
  for the cast (`World.Skills.Statue`). The person is the person
  blueprint at the level `:mid`, posed (the pose `arms_out` has the arms
  straight out to the sides, `lift` degrees over the level; any other
  pose is a pose of `World.People.Pose`), scaled so that its top (the top
  of the halo, when it has one) is `height` over its feet. With `span`
  (the hands, tip to tip) and `hand` (a hand, from the wrist to the tip of
  the middle finger), the arms out to the sides become shorter or longer
  along x, from the shoulders: a statue has the proportions of its
  sculptor, not of a person.

  Its data: `figure`, the surfaces (`{points, triangles}`, in m, on its
  feet at z = 0), the hands (the box of the points of each hand of
  `arms_out`), the marks (the shoulders, the elbows, the wrists and the
  head), the scale, the top and the halo (its radius and its center).
  """
  @behaviour World.Skill
  alias World.{Detail, Figure, Frame, Scene, Vec}
  alias World.People.Human
  alias World.Skills.Statue

  @names ~w(name height span hand pose lift gender age hair halo)

  @impl true
  def name, do: "figure"

  @impl true
  def trade, do: :sculptor

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, _inputs, _context), do: {nil, %{"figure" => figure(Statue.o(data, @names))}, %{}}

  defp figure(o) do
    f =
      Detail.with(:mid, fn ->
        Human.person(o.name, gender: o.gender, age: o.age, hair: o.hair, clothes: [], pose: pose(o))
      end)

    f = if o.pose == "arms_out", do: Figure.pose(f, %{}, arm_targets(f, o.lift)), else: f
    frames = Scene.world_frames(%Scene{nodes: f.nodes})
    bone = fn name -> frames[Enum.find_index(f.nodes, &(&1.name == name))].at end
    surfaces = skin(f, frames)
    points = Enum.flat_map(surfaces, &elem(&1, 0))
    {{left, _, _}, {right, _, top}} = Vec.bounds(points)
    neck = bone.("neck_01")
    # The halo: a ring round the head, behind it: its center at 0.45 of
    # the head (from the neck to the top) under the top, its radius 0.68
    # of the head (by eye from the photos).
    hh = top - elem(neck, 2)
    {{_, back, _}, _} = points |> Enum.filter(&(elem(&1, 2) > elem(neck, 2))) |> Vec.bounds()
    {halo_r, halo_c} = {0.68 * hh, {0.0, back, top - 0.45 * hh}}
    s = o.height / if(o.halo, do: elem(halo_c, 2) + halo_r, else: top)

    marks =
      Map.new(~w(upperarm_l lowerarm_l hand_l upperarm_r lowerarm_r hand_r head), &{&1, Vec.scale(bone.(&1), s)})

    # Each side by its own marks: the two arms of the pose are not quite
    # the same.
    side = fn name -> abs(elem(marks[name], 0)) end
    sl = squeeze(o, side.("upperarm_l"), side.("hand_l"), -left * s)
    sr = squeeze(o, side.("upperarm_r"), side.("hand_r"), right * s)
    squeeze = fn {x, _, _} = p -> if x < 0, do: sl.(p), else: sr.(p) end
    move = fn p -> squeeze.(Vec.scale(p, s)) end

    surfaces = for {ps, tris} <- surfaces, do: {Enum.map(ps, move), tris}
    marks = Map.new(marks, fn {k, p} -> {k, squeeze.(p)} end)

    %{
      surfaces: surfaces,
      hands: hands(surfaces, marks, o),
      marks: marks,
      scale: s,
      top: top * s,
      halo: {halo_r * s, Vec.scale(halo_c, s)}
    }
  end

  # The box of the points of each hand of the pose `arms_out`, out from
  # its wrist: the fingers of a person are too thin for a cast, so a mitt
  # (the fingers together, as a sculptor makes them) goes round them.
  defp hands(surfaces, marks, %{pose: "arms_out"}) do
    points = Enum.flat_map(surfaces, &elem(&1, 0))

    for {side, sign} <- [{"l", -1.0}, {"r", 1.0}] do
      xw = elem(marks["hand_" <> side], 0)
      Vec.bounds(Enum.filter(points, fn {x, _, _} -> x * sign > xw * sign end))
    end
  end

  defp hands(_, _, _), do: []

  defp pose(%{pose: "arms_out"}), do: %{}
  defp pose(%{pose: name}), do: name

  # The targets of the hands: straight out from the shoulders, `lift`
  # degrees over the level.
  defp arm_targets(f, lift) do
    frames = Scene.world_frames(%Scene{nodes: f.nodes})
    at = fn name -> frames[Enum.find_index(f.nodes, &(&1.name == name))].at end
    a = lift * :math.pi() / 180

    for {limb, bone, side} <- [{"arm_l", "upperarm_l", -1.0}, {"arm_r", "upperarm_r", 1.0}], into: %{} do
      {limb, Vec.add(at.(bone), {side * 3.0 * :math.cos(a), 0.0, 3.0 * :math.sin(a)})}
    end
  end

  # The triangles of the skin and the hair of the posed person.
  defp skin(%Figure{nodes: nodes, skins: skins}, frames) do
    for n <- nodes, n.skin != nil, skin = Enum.at(skins, n.skin), p <- n.primitives, p.material in [:skin, :hair] do
      bones =
        skin.joints
        |> Enum.zip(skin.inverse_bind)
        |> Enum.map(fn {j, ib} -> Frame.compose(frames[j], ib) end)
        |> List.to_tuple()

      points =
        for {pt, js, ws} <- Enum.zip([p.positions, p.joints, p.weights]) do
          Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
          |> Enum.map(fn {j, w} -> Vec.scale(Frame.point(elem(bones, j), pt), w) end)
          |> Enum.reduce(&Vec.add/2)
        end

      {points, Enum.chunk_every(p.indices, 3)}
    end
  end

  # The change of x of the arms out to the sides: from the shoulder to the
  # wrist by one factor, from the wrist to the tip by another, so that the
  # hand has its length and the span its width.
  defp squeeze(%{span: nil, hand: nil}, _, _, _), do: & &1

  defp squeeze(o, xs, xw, tip) do
    hand = o.hand || tip - xw
    span = o.span || 2 * tip
    ch = hand / (tip - xw)
    ca = (span / 2 - hand - xs) / (xw - xs)

    if ca <= 0,
      do: raise(ArgumentError, "the span #{span} m is too small for the shoulders and the hands of the statue")

    fn {x, y, z} ->
      a = abs(x)

      d =
        cond do
          a <= xs -> a
          a <= xw -> xs + (a - xs) * ca
          true -> xs + (xw - xs) * ca + (a - xw) * ch
        end

      {if(x < 0, do: -d, else: d), y, z}
    end
  end
end
