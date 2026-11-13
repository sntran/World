defmodule World.Sculpt.RandomTest do
  # Any list of edits builds (plan 0011, D4, R2): random sculptures go
  # through the skill `sculpt`, as the data of a client.
  #
  #   RANDOM_SCULPTURES=200 RANDOM_DIR=/tmp/random mix test test/world/sculpt_random_test.exs
  #
  # builds 200 of them and writes the GLB of each to the directory, for
  # the validator of glTF (`node scripts/validate.mjs /tmp/random`).
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Build, Detail, Drawing, Orders, SDF, Vec}
  alias World.Skills.Sculpt, as: Skill

  @runs String.to_integer(System.get_env("RANDOM_SCULPTURES", "30"))
  @dir System.get_env("RANDOM_DIR")
  @level "mid"
  # (A long run needs more than the minute of a test.)
  @moduletag timeout: 1_200_000

  # A number with three places after the point.
  defp number(min, max), do: map(integer(round(min * 1000)..round(max * 1000)), &(&1 / 1000))

  defp place, do: map({number(-0.2, 0.2), number(-0.2, 0.2), number(-0.2, 0.2)}, &Tuple.to_list/1)

  # A shape with a size that the check takes.
  defp shape do
    size = number(0.04, 0.25)

    one_of([
      map(size, &%{"shape" => "ball", "size" => [&1]}),
      map({size, size, size}, fn {x, y, z} -> %{"shape" => "box", "size" => [x, y, z]} end),
      map({size, size, size, number(0.0, 0.04)}, fn {x, y, z, r} ->
        %{"shape" => "round_box", "size" => [x, y, z, r]}
      end),
      map({size, size}, fn {h, r} -> %{"shape" => "capsule", "size" => [h, r]} end),
      map({size, size}, fn {r, h} -> %{"shape" => "cylinder", "size" => [r, h]} end),
      map({size, number(0.0, 0.2), size}, fn {a, b, h} -> %{"shape" => "cone", "size" => [a, b, h]} end),
      map({size, number(0.02, 0.04)}, fn {big, r} -> %{"shape" => "ring", "size" => [big, r]} end),
      map({size, size, size}, fn {x, y, z} -> %{"shape" => "ellipsoid", "size" => [x, y, z]} end),
      map({size, size, size, integer(2..12)}, fn {x, y, z, e} ->
        %{"shape" => "superellipsoid", "size" => [x, y, z, e]}
      end),
      map({size, size, size}, fn {x, y, z} -> %{"shape" => "wedge", "size" => [x, y, z]} end),
      map({size, size, integer(3..8)}, fn {r, h, n} -> %{"shape" => "prism", "size" => [r, h, n]} end),
      map({size, size, size}, fn {x, y, h} -> %{"shape" => "pyramid", "size" => [x, y, h]} end),
      map({list_of(place(), min_length: 2, max_length: 4), number(0.03, 0.08)}, fn {points, r} ->
        %{"shape" => "tube", "size" => %{"points" => points, "radii" => List.duplicate(r, length(points))}}
      end)
    ])
  end

  defp color,
    do:
      map({integer(0..255), integer(0..120), integer(0..255)}, fn {r, g, b} ->
        "#" <> Base.encode16(<<r, g, b>>, case: :lower)
      end)

  # The words of an edit that each mode can have.
  defp words(mode) do
    blend = one_of([constant(0), number(0.01, 0.08)])

    gen all blend <- blend,
            hard <- boolean(),
            at <- place(),
            axis <- one_of([constant(nil), constant([1, 0, 0]), constant([0, 1, 0]), place()]),
            color <- one_of([constant(nil), color()]),
            material <- member_of(["stone_wash", "gray"]),
            finish <- member_of([nil, "plastic", "shiny", "rough", "metal", "shiny_metal", "rough_metal"]),
            glow <- one_of([constant(nil), number(0.0, 1.0)]),
            opacity <- number(0.0, 1.0),
            lift <- number(-1.0, 1.0),
            surface <- member_of([nil, nil, "wood", "weave", "rust", %{"kind" => "plaster", "scale" => 0.03}]),
            copy <- member_of([nil, nil, :mirror, :ring, :row]) do
      %{"mode" => mode, "at" => at, "blend" => blend, "material" => material}
      |> put(hard and blend > 0, "blend_type", "hard")
      # An axis with no length is not an axis.
      |> put(axis != nil and Vec.len(List.to_tuple(axis || [0, 0, 0])) > 0.01, "axis", axis)
      |> put(color != nil, "color", color)
      |> put(finish != nil, "finish", finish)
      |> put(glow != nil, "glow", glow)
      |> put(surface != nil, "surface", surface)
      |> put(mode == "paint", "opacity", opacity)
      |> put(mode == "paint" and blend > 0, "raise", Float.round(lift * min(blend, 0.1), 4))
      |> put(copy == :mirror, "mirror", "x")
      |> put(copy == :ring, "repeat", %{"count" => 3})
      |> put(copy == :row, "repeat", %{"count" => 2, "move" => [0.1, 0, 0]})
    end
  end

  defp put(map, true, key, value), do: Map.put(map, key, value)
  defp put(map, _, _key, _value), do: map

  defp edit(modes),
    do: bind(member_of(modes), fn mode -> map({shape(), words(mode)}, fn {s, w} -> Map.merge(w, s) end) end)

  # The data of a sculpture: a first edit that adds, some edits of each
  # mode, cells, and often a budget and maps.
  defp sculpture do
    gen all first <- edit(["add"]),
            more <- list_of(edit(~w(add add add subtract paint paint crop)), max_length: 6),
            cells <- number(0.02, 0.05),
            budget <- member_of([nil, 300, 600, 1200]),
            bake <- member_of([nil, 128, 256]) do
      %{"edits" => [first | more], "cells" => %{@level => cells}}
      |> put(budget != nil, "budget", %{@level => budget})
      |> put(budget != nil and bake != nil and bake >= World.Sculpt.Bake.least(budget), "bake", %{@level => bake})
    end
  end

  defp drawing(data, name),
    do: %{"name" => name, "kind" => "item", "nodes" => [%{"name" => "it", "skill" => %{"sculpt" => data}}]}

  # The edges of the triangles of some meshes with a count of faces that
  # is not even (by the places of their points: the meshes of two
  # materials meet at an edge).
  defp open(meshes) do
    for m <- meshes,
        pt = List.to_tuple(m.points),
        [a, b, c] <- m.faces,
        {p, q} <- [{a, b}, {b, c}, {c, a}],
        reduce: %{} do
      acc -> Map.update(acc, Enum.sort([elem(pt, p), elem(pt, q)]), 1, &(&1 + 1))
    end
    |> Enum.count(fn {_, n} -> rem(n, 2) == 1 end)
  end

  property "any list of edits builds: a closed mesh in its budget and in the box of its edits, maps with a place for each triangle, a file of glTF" do
    if @dir, do: File.mkdir_p!(@dir)
    counter = :counters.new(1, [])

    check all data <- sculpture(), max_runs: @runs do
      :counters.add(counter, 1, 1)
      name = "random_#{:counters.get(counter, 1)}"
      d = drawing(data, name)
      # The check of an order takes the data: the generator makes valid data only.
      assert {:ok, _} = Orders.check(%{"blueprint" => "drawing", "options" => %{"drawing" => d}}), inspect(data)
      model = Detail.with(:mid, fn -> Drawing.build(d) end)
      [{"it", part, _}] = model.nodes
      meshes = part.shapes
      edits = Skill.edits(data["edits"], %{})
      step = data["cells"][@level]

      # A closed surface: each edge has an even count of faces.
      assert open(meshes) == 0, inspect(data)
      faces = meshes |> Enum.map(&length(&1.faces)) |> Enum.sum()
      if data["budget"], do: assert(faces <= data["budget"][@level], inspect(data))

      # Each point is in the box of the edits (with their blends and their raises), to a cell.
      if faces > 0 do
        {lo, hi} = SDF.bounds(edits)
        more = step + 2 * SDF.relief(edits)

        for m <- meshes, p <- m.points do
          assert Enum.all?(Enum.zip([Tuple.to_list(p), Tuple.to_list(lo), Tuple.to_list(hi)]), fn {v, a, b} ->
                   v >= a - more and v <= b + more
                 end),
                 inspect({p, lo, hi, data})
        end
      end

      # The maps: each mesh has the UVs of its faces in the image, and a triangle with an area has an area there.
      if data["bake"] && faces > 0 do
        for m <- meshes do
          assert length(m.uvs) == length(m.faces)
          pt = List.to_tuple(m.points)

          for {[a, b, c], [{u0, v0}, {u1, v1}, {u2, v2}] = uv} <- Enum.zip(m.faces, m.uvs) do
            assert Enum.all?(uv, fn {u, v} -> u >= 0 and u <= 1 and v >= 0 and v <= 1 end)
            area = Vec.len(Vec.cross(Vec.sub(elem(pt, b), elem(pt, a)), Vec.sub(elem(pt, c), elem(pt, a))))

            if area > step * step * 1.0e-3,
              do: assert(abs((u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0)) > 0.0, inspect(data))
          end
        end
      end

      # The file of the model.
      glb = Build.glb(model)
      assert <<"glTF", 2::little-32, size::little-32, _::binary>> = glb
      assert size == byte_size(glb)
      if @dir, do: File.write!(Path.join(@dir, name <> ".glb"), glb)
    end
  end
end
