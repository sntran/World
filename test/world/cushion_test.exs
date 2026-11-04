defmodule World.Sewing.CushionTest do
  use ExUnit.Case, async: true

  alias World.{Contact, Detail, Frame, Mesh}
  alias World.Sewing.Cushion

  test "a box cushion: its cut list, its mass from the cover and the foam, the piping only near" do
    opts = [size: {0.5, 0.4}, thick: 0.1, at: Frame.move({0.0, 0.0, 0.5})]
    part = Detail.with(:near, fn -> Cushion.box("c", opts) end)
    assert part.kind == :cushion
    pieces = Map.new(part.params["pieces"], &{&1["name"], &1["area"]})
    # The top and the bottom are the outline (a rectangle with round
    # corners) and the seam allowance; the boxing strip goes round it.
    assert_in_delta pieces["top"], 0.5 * 0.4, 0.03
    assert_in_delta pieces["boxing"], 1.8 * 0.1 + 2 * 1.8 * 0.0127, 0.03
    # 0.02 m3 of foam (28.8 kg/m3) and about 0.6 m2 of cover (271 g/m2).
    assert_in_delta part.params["mass"], 0.02 * 28.8 + 0.6 * 0.271, 0.1
    assert part.params["squash"] == Cushion.squash(:foam)
    # The cushion, and a cord of piping in each seam.
    assert length(part.shapes) == 3
    assert {{_, _, z0}, {_, _, z1}} = Mesh.bounds(hd(part.shapes))
    assert_in_delta z0, 0.5, 1.0e-6
    assert_in_delta z1, 0.6, 1.0e-6
    assert length(Detail.with(:far, fn -> Cushion.box("c", opts) end).shapes) == 1
  end

  test "a cushion in a bowl takes its shape, and ties go round the bars" do
    bowl = fn z -> {0.1 + z, 0.1 + z} end
    tie = {{0.0, 0.0, 0.2}, {1.0, 0.0, 0.0}, 0.02}
    part = Cushion.box("c", size: {0.6, 0.6}, thick: 0.1, power: 2.0, fill: :fiber, bowl: bowl, ties: [tie])
    {{x0, _, _}, {x1, _, _}} = Mesh.bounds(hd(part.shapes))
    assert x1 - x0 < 0.41
    assert Enum.any?(part.params["pieces"], &(&1["name"] == "tie_1"))
    assert part.params["squash"] == Cushion.squash(:fiber)
    assert Enum.any?(part.sources, &(&1 =~ "fiber"))
  end

  test "a pad on a curved face: thick at the middle, thin at the seam, tufts; under a person it is thinner" do
    # A quarter of a cylinder of radius 0.5 round the z axis, the pad on
    # its inside.
    face = fn {u, v} -> {0.5 * :math.cos(u * :math.pi() / 2), 0.5 * :math.sin(u * :math.pi() / 2), v * 0.6} end
    opts = [face: face, toward: {0.0, 0.0, 0.3}, thick: 0.1, fill: :fiber, tufts: {2, 2}]
    part = Cushion.pad("p", opts)
    [pad | rest] = part.shapes
    # The pad, the piping and four buttons; with no tufts, no buttons.
    assert length(rest) == 5
    assert length(Cushion.pad("q", Keyword.delete(opts, :tufts)).shapes) == 2
    pieces = Map.new(part.params["pieces"], &{&1["name"], &1["area"]})
    assert_in_delta pieces["back"], :math.pi() / 4 * 0.6, 0.05
    # The pad is on the inside of the face: no point is out of the
    # cylinder, and the middle is 1 dm in.
    assert Enum.all?(pad.points, fn {x, y, _} -> :math.sqrt(x * x + y * y) < 0.5 + 1.0e-6 end)
    middle = Enum.min_by(pad.points, fn {x, y, z} -> :math.sqrt(x * x + y * y) + abs(z - 0.3) * 0.01 end)
    {mx, my, _} = middle
    assert_in_delta :math.sqrt(mx * mx + my * my), 0.4, 0.03

    # Under a person: the squashed pad is thinner, so a point 7 cm in is
    # out of it.
    solid = Cushion.solid(:pad, opts)
    p = {0.43 * :math.cos(:math.pi() / 4), 0.43 * :math.sin(:math.pi() / 4), 0.3}
    assert Contact.blocked?(p, [Contact.solid(pad)])
    refute Contact.blocked?(p, [solid])

    # A box cushion under a person: 1 m of foam squashed by a quarter.
    box = Cushion.solid(:box, size: {2.0, 2.0}, thick: 1.0)
    assert Contact.blocked?({0.0, 0.0, 0.7}, [box])
    refute Contact.blocked?({0.0, 0.0, 0.8}, [box])
  end

  test "a mattress: layers on a core, a cover of ticking, tapes on the seams; its mass from each layer" do
    part = Detail.with(:near, fn -> Cushion.mattress("m", size: {1.6, 2.0}, layers: [{:latex, 0.1}]) end)
    assert part.kind == :mattress
    assert Enum.any?(part.params["pieces"], &(&1["name"] == "tape"))
    assert [%{"fill" => "latex", "thick" => 0.1}] = part.params["layers"]
    # 0.32 m3 of latex (75 kg/m3) and about 7.6 m2 of ticking (200 g/m2).
    assert_in_delta part.params["mass"], 0.32 * 75 + 7.6 * 0.2, 1.5
    assert Enum.any?(part.sources, &(&1 =~ "ticking")) and Enum.any?(part.sources, &(&1 =~ "latex"))

    # A soft layer on a hard core: the squash is the mean of the layers by
    # their thickness.
    layers = [{:coir, 0.08}, {:hr_foam, 0.02}]
    assert_in_delta Cushion.squash(layers: layers), (0.08 * 0.05 + 0.02 * 0.2) / 0.1, 1.0e-9
    assert Cushion.thick(layers: layers) == 0.1
  end

  test "a hard cushion: a board of plywood under hard foam does not squash" do
    opts = [size: {0.4, 0.4}, thick: 0.03, fill: :molded, board: 0.012]
    assert [{:board, 0.012}, {:molded, 0.03}] = Cushion.layers(opts)
    assert_in_delta Cushion.thick(opts), 0.042, 1.0e-9
    assert Cushion.squash(opts) < Cushion.squash(:molded)
    part = Cushion.box("c", opts)
    # The board is heavy: 540 kg/m3.
    assert part.params["mass"] > 0.4 * 0.4 * 0.012 * 540
  end

  test "the sewing shop of the run makes the mattresses" do
    yard = World.Run.yard()
    assert yard.places["sewing_shop"].family == :sewing
    assert :sewing in World.Places.families()
  end

  test "the mattresses of the sewing shop are true models" do
    for {name, fun} <- Cushion.models() do
      item = fun.()
      assert item.kind == :mattress and World.Places.family_of(item) == :sewing, name
      assert World.Check.model(item) == :ok, name
    end
  end
end
