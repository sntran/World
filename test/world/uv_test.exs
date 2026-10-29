defmodule World.Animals.UVTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.Animals
  alias World.Animals.UV
  alias World.Vec

  # A box around a bone along y (from y = 0 to y = 1): 8 points, 12
  # triangles (each to the outside).
  @box for x <- [-0.2, 0.2], y <- [0.0, 1.0], z <- [-0.2, 0.2], do: {x, y, z}
  @quads [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
  @tris Enum.flat_map(@quads, fn [a, b, c, d] -> [[a, b, c], [a, c, d]] end)

  defp bone(name), do: [%{name: name, head: {0.0, 0.0, 0.0}, tail: {0.0, 1.0, 0.0}}]
  defp weights(name), do: %{name => Map.new(0..7, &{&1, 1.0})}

  # The area of a face in UV, with its sign: more than 0 when the face
  # keeps its turn.
  defp signed([{u1, v1}, {u2, v2}, {u3, v3}]), do: ((u2 - u1) * (v3 - v1) - (u3 - u1) * (v2 - v1)) / 2
  defp area([a, b, c]), do: Vec.len(Vec.cross(Vec.sub(b, a), Vec.sub(c, a))) / 2

  test "a box: a chart for each side, in the square, apart, and +v along the fur" do
    for name <- ["leg_l", "spine_01"] do
      uvs = UV.charts(bone(name), @box, weights(name), @tris)
      assert length(uvs) == 12
      assert Enum.all?(List.flatten(uvs), fn {u, v} -> u >= 0 and u <= 1 and v >= 0 and v <= 1 end)
      assert Enum.all?(uvs, &(signed(&1) > 0))

      # The two triangles of a side are one chart; the 6 boxes of the
      # charts do not overlap.
      boxes =
        uvs
        |> Enum.chunk_every(2)
        |> Enum.map(fn two ->
          {us, vs} = two |> Enum.concat() |> Enum.unzip()
          {Enum.min(us), Enum.max(us), Enum.min(vs), Enum.max(vs)}
        end)

      for {a, i} <- Enum.with_index(boxes), {b, j} <- Enum.with_index(boxes), i < j do
        {u0, u1, v0, v1} = a
        {w0, w1, x0, x1} = b
        assert u1 <= w0 or w1 <= u0 or v1 <= x0 or x1 <= v0
      end

      # On the side with its normal to +z (the face [1, 5, 7, 3]), v goes
      # with y on a leg (away from the body), against y on a bone of the
      # body (to the back).
      [[a, _, c], _] = Enum.slice(uvs, 10, 2)
      {_, va} = a
      {_, vc} = c
      ya = elem(Enum.at(@box, 1), 1)
      yc = elem(Enum.at(@box, 7), 1)
      assert ya != yc
      if name == "leg_l", do: assert((vc - va) * (yc - ya) > 0), else: assert((vc - va) * (yc - ya) < 0)
    end

    # The length of one unit of UV on the skin.
    uvs = UV.charts(bone("leg_l"), @box, weights("leg_l"), @tris)
    flat = uvs |> Enum.map(&signed/1) |> Enum.sum()
    skin = @tris |> Enum.map(fn t -> area(Enum.map(t, &Enum.at(@box, &1))) end) |> Enum.sum()
    assert_in_delta UV.size(@box, @tris, uvs), :math.sqrt(skin / flat), 1.0e-9

    # A bone along the side, and a face with no weight (it goes to the
    # first bone).
    side = [%{name: "ear_l", head: {0.0, 0.0, 0.0}, tail: {1.0, 0.0, 0.0}}]
    uvs = UV.charts(side, @box, %{}, @tris)
    assert Enum.all?(uvs, &(signed(&1) > 0))
  end

  property "random triangles on two bones: each corner in the square, no face turns over" do
    point =
      StreamData.tuple(
        {StreamData.float(min: -1.0, max: 1.0), StreamData.float(min: -1.0, max: 1.0),
         StreamData.float(min: -1.0, max: 1.0)}
      )

    check all(tris <- StreamData.list_of(StreamData.list_of(point, length: 3), min_length: 1, max_length: 20)) do
      tris = Enum.filter(tris, &(area(&1) > 1.0e-4))
      points = Enum.concat(tris)
      faces = tris |> Enum.with_index() |> Enum.map(fn {_, i} -> [3 * i, 3 * i + 1, 3 * i + 2] end)

      bones = [
        %{name: "spine_01", head: {0.0, -1.0, 0.0}, tail: {0.0, 1.0, 0.0}},
        %{name: "tail_01", head: {0.0, 0.0, 0.0}, tail: {0.3, -0.2, -1.0}}
      ]

      weights = %{
        "spine_01" => Map.new(0..max(length(points) - 1, 0), &{&1, 0.5 + rem(&1, 2) * 0.1}),
        "tail_01" => Map.new(0..max(length(points) - 1, 0), &{&1, 0.55})
      }

      uvs = UV.charts(bones, points, weights, faces)
      assert length(uvs) == length(faces)

      assert Enum.all?(List.flatten(uvs), fn {u, v} ->
               u >= -1.0e-9 and u <= 1 + 1.0e-9 and v >= -1.0e-9 and v <= 1 + 1.0e-9
             end)

      assert Enum.all?(uvs, &(signed(&1) > 0))
    end
  end

  test "the templates: each corner in the square, no face turns over, the scale in a range of √3" do
    for name <- ~w(shiba_inu wolf fox deer horse donkey cow bull primate) do
      %{bones: bones, points: points, weights: weights, template: t} = Animals.template(name)

      faces =
        Path.join([:code.priv_dir(:world), "animals", "meshes", t["mesh"] <> ".json"])
        |> File.read!()
        |> JSON.decode!()
        |> Map.fetch!("faces")

      uvs = UV.charts(bones, points, weights, faces)
      pts = List.to_tuple(points)

      ratios =
        for {f, u} <- Enum.zip(faces, uvs), a = area(Enum.map(f, &elem(pts, &1))), a > 1.0e-6 do
          assert signed(u) > 0, name
          signed(u) / a
        end

      assert Enum.all?(List.flatten(uvs), fn {u, v} -> u >= 0 and u <= 1 and v >= 0 and v <= 1 end), name
      assert Enum.max(ratios) / Enum.min(ratios) <= :math.sqrt(3) + 1.0e-6, name
    end
  end
end
