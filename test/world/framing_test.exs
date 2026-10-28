defmodule World.FramingTest do
  use ExUnit.Case, async: true

  alias World.Build

  alias World.Detail

  alias World.Part

  alias World.Scene

  alias World.{Framing, Vec}
  alias World.Materials.Fasteners
  defp size(%Part{} = p), do: p |> Part.bounds() |> then(fn {lo, hi} -> Vec.sub(hi, lo) end)
  defp counts(model), do: Map.new(Build.parts(model), &{&1["name"], &1["count"]})
  defp ports(p, prefix), do: for({name, _} <- p.ports, String.starts_with?(name, prefix), do: name)

  describe "T-slot extrusions" do
    test "each profile: its size, its slots, and the ports of its slots" do
      for name <- Framing.profiles() do
        p = Framing.profile(name)
        part = Framing.extrusion(name, 0.3)
        {w, d, l} = size(part)
        assert_in_delta w, p.nx * p.a, 1.0e-9
        assert_in_delta d, p.ny * p.a, 1.0e-9
        assert_in_delta l, 0.3, 1.0e-9
        assert length(ports(part, "slot_")) == 2 * (p.nx + p.ny)

        # A port of a slot is on a face, its axis into the profile.
        for slot <- ports(part, "slot_") do
          %{at: {x, y, _}, axis: {ax, ay, _}} = Part.port!(part, slot)
          assert ax * x + ay * y < 0
        end
      end

      assert World.Materials.Stock.extrusion("2020", 0.3).name == "extrusion_2020x300"
    end

    test "the T-nuts, the brackets and the screws of each series" do
      assert Framing.t_nut("1010").name == "t_nut_10_1_4_20"
      assert Framing.t_nut("1530").name == "t_nut_15_5_16_18"
      assert Framing.t_nut("4040").name == "t_nut_40_m8"
      assert Framing.corner_bracket("2040").name == "corner_bracket_20"
      assert Framing.bracket_screw("1010").name =~ "button_screw_1_4_20x"
      assert Framing.bracket_screw("3030").name =~ "button_screw_m6x"
      assert_raise KeyError, fn -> Framing.profile("9090") end
    end
  end

  describe "strut channel" do
    test "a solid channel and a slotted channel" do
      solid = Framing.strut(:solid, 0.6)
      slotted = Framing.strut(:slotted, 0.6)
      assert solid.name == "strut_p1000_600" and slotted.name == "strut_p1000t_600"

      for p <- [solid, slotted] do
        {w, h, _} = size(p)
        assert_in_delta w, 0.04128, 1.0e-6
        assert_in_delta h, 0.04128, 1.0e-6
      end

      assert ports(solid, "slot_") == []
      # Slots on 2 in centers: 11 in 600 mm.
      assert length(ports(slotted, "slot_")) == 11
    end

    test "a spring nut, a fitting and a threaded rod" do
      assert Framing.spring_nut().name == "spring_nut_1_2_13"
      assert Framing.strut_angle().name == "strut_angle_90"
      rod = Framing.threaded_rod("3/8-16", 0.5)
      assert rod.name == "threaded_rod_3_8_16x500"
      {d, _, _} = size(rod)
      assert_in_delta d, 0.375 * 0.0254, 1.0e-4
    end
  end

  describe "L-track" do
    test "pockets every inch, holes every 5 in, and a part of a pitch at the end" do
      even = Framing.l_track(24 * 0.0254)
      assert length(ports(even, "pocket_")) == 24
      assert length(ports(even, "screw_")) == 5

      odd = Framing.l_track(0.3)
      assert length(ports(odd, "pocket_")) == 11
      assert length(odd.shapes) > length(Framing.l_track(11 * 0.0254).shapes)
    end

    test "the fittings" do
      ring = Framing.l_track_fitting(:ring)
      stud = Framing.l_track_fitting(:stud)
      assert ring.name == "l_track_fitting_ring" and stud.name == "l_track_fitting_stud_1_4_20"
      assert %{axis: {1.0, +0.0, +0.0}} = Part.port!(ring, "slide")
    end
  end

  describe "inch threads" do
    test "the sizes and the names of the fasteners" do
      assert Fasteners.inch_threads() == ["1/4-20", "5/16-18", "3/8-16", "1/2-13"]
      assert_in_delta Fasteners.diameter("1/2-13"), 0.0127, 1.0e-9
      assert Fasteners.bolt("1/2-13", 0.0318).name == "bolt_1_2_13x32"
      assert Fasteners.nut("1/4-20").name == "nut_1_4_20"
      assert Fasteners.washer("5/16-18").name == "washer_5_16_18"
      assert [source] = Fasteners.bolt("3/8-16", 0.05).sources
      assert source =~ "ASME B18.2.1"
      assert Fasteners.button_screw("M5", 0.01).sources |> hd() =~ "ISO 7380"
      assert Fasteners.button_screw("1/4-20", 0.0127).sources |> hd() =~ "ASME B18.3"
      assert_raise KeyError, fn -> Fasteners.table(:hex_head, "7/8-9") end
    end
  end

  describe "the builds" do
    for {name, fun} <- World.Framing.Builds.all() do
      @fun fun
      @name name

      test "#{name}: the levels and the ground" do
        for level <- [:near, :mid, :far] do
          scene = Build.scene(Detail.with(level, @fun), level: level)
          tris = Scene.triangles(scene)
          assert tris > 0 and tris <= %{near: 50_000, mid: 12_000, far: 5_000}[level], "#{@name}: #{tris} at #{level}"
          {{_, _, z}, _} = Scene.bounds(scene)
          assert abs(z) < 0.002, "#{@name} starts at z = #{z}"
        end
      end
    end

    test "the shelf of 80/20: its profiles, brackets, screws and T-nuts" do
      parts = counts(World.Framing.Builds.shelf())
      assert parts["corner_bracket_10"] == 16
      assert parts["button_screw_1_4_20x10"] == 32
      assert parts["t_nut_10_1_4_20"] == 32
      assert parts["extrusion_1010x438"] == 4
    end

    test "the rack and the trapeze of strut channel" do
      rack = counts(World.Framing.Builds.strut_wall_rack())
      assert rack["spring_nut_1_2_13"] == 4 and rack["bolt_1_2_13x32"] == 4
      assert rack["strut_p1000t_914"] == 2 and rack["strut_p1000t_762"] == 2

      trapeze = counts(World.Framing.Builds.strut_trapeze())
      assert trapeze["nut_1_2_13"] == 4 and trapeze["washer_1_2_13"] == 4
    end

    test "the fittings slide along the L-track" do
      floor = World.Framing.Builds.l_track_floor()
      slides = for {_, _, %{kind: :slide, role: :slide, limits: [lo, hi]}} <- floor.nodes, do: {lo, hi}
      assert length(slides) == 3
      assert Enum.all?(slides, fn {lo, hi} -> lo < 0 and hi > 0 end)
      assert counts(floor)["wood_screw_12x16"] == 20
    end
  end
end
