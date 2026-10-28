defmodule Xuong.FactoryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Xuong.{Blueprint, Blueprints, Factory}

  defp paths({:error, errors}), do: Enum.map(errors, & &1["path"])

  describe "the options of a blueprint" do
    test "each type, from JSON and from the query of a URL" do
      num = Blueprint.option("n", :number, min: 0.0, max: 2.0, unit: "m")
      int = Blueprint.option("i", :integer, min: 1, max: 3)
      assert Blueprint.value(num, 1, "n") == {:ok, 1.0}
      assert Blueprint.value(num, "1.5", "n") == {:ok, 1.5}
      assert {:error, [{"n", "must be from 0.0 to 2.0 m"}]} = Blueprint.value(num, 3, "n")
      assert {:error, [{"n", "must be a number"}]} = Blueprint.value(num, "x", "n")
      assert {:error, [{"n", "must be a number"}]} = Blueprint.value(num, nil, "n")
      assert Blueprint.value(int, "2", "i") == {:ok, 2}
      assert Blueprint.value(int, 2.0, "i") == {:ok, 2}
      assert {:error, [{"i", "must be an integer"}]} = Blueprint.value(int, 2.5, "i")

      yes = Blueprint.option("b", :boolean)
      assert Blueprint.value(yes, "true", "b") == {:ok, true}
      assert Blueprint.value(yes, "false", "b") == {:ok, false}
      assert Blueprint.value(yes, true, "b") == {:ok, true}
      assert {:error, _} = Blueprint.value(yes, 1, "b")

      color = Blueprint.option("c", :color)
      assert Blueprint.value(color, "#AbCdEf", "c") == {:ok, "#abcdef"}
      assert {:error, _} = Blueprint.value(color, "red", "c")

      list = Blueprint.option("l", :list, item: Blueprint.option("x", :choice, values: ["a", "b"]), max: 2)
      assert Blueprint.value(list, "a,b", "l") == {:ok, ["a", "b"]}
      assert Blueprint.value(list, "", "l") == {:ok, []}
      assert {:error, [{"l.1", _}]} = Blueprint.value(list, ["a", "c"], "l")
      assert {:error, [{"l", "must have at most 2 items"}]} = Blueprint.value(list, ["a", "a", "a"], "l")
      assert {:error, [{"l", "must be a list"}]} = Blueprint.value(list, 3, "l")
    end

    test "an object: its fields, a field that is required, a field that is not known" do
      fields = [Blueprint.option("a", :number), Blueprint.option("b", :number, default: 2.0)]
      assert Blueprint.check_options(fields, %{"a" => 1}, "o") == {:ok, %{"a" => 1.0, "b" => 2.0}}
      assert Blueprint.check_options(fields, %{}, "o") == {:error, [{"o.a", "is required"}]}
      assert {:error, [{"o.z", "is not an option"}, _]} = Blueprint.check_options(fields, %{"z" => 1}, "o")
      assert Blueprint.check_options(fields, [], "o") == {:error, [{"o", "must be an object"}]}
      assert Blueprint.check_options(fields, %{"a" => "x"}, "o") == {:error, [{"o.a", "must be a number"}]}
    end

    test "each blueprint describes its options as JSON" do
      for b <- Blueprints.all() do
        d = Blueprint.describe(b)
        assert d["name"] == b.name and d["options"] != []
        assert Factory.encode(d) |> JSON.decode!() |> is_map()
      end

      [house] = for b <- Blueprints.all(), b.name == "house", do: Blueprint.describe(b)
      openings = Enum.find(house["options"], &(&1["name"] == "openings"))
      assert openings["item"]["fields"] |> Enum.map(& &1["name"]) == ~w(wall kind x width height sill)
      assert Blueprints.fetch("nope") == :error
    end
  end

  describe "an order" do
    test "the full order has each default, and the same order gives the same hash" do
      {:ok, a} = Factory.check(%{"blueprint" => "extrusion", "options" => %{"profile" => "2020", "length" => "0.5"}})
      {:ok, b} = Factory.check(%{"options" => %{"length" => 0.5, "profile" => "2020"}, "blueprint" => "extrusion"})
      assert a == b and Factory.hash(a) == Factory.hash(b)

      assert a == %{
               "blueprint" => "extrusion",
               "options" => %{"length" => 0.5, "profile" => "2020"},
               "colors" => %{},
               "joints" => %{}
             }

      assert Factory.hash(a) =~ ~r/^[0-9a-f]{32}$/
    end

    test "the errors of an order" do
      assert paths(Factory.check([])) == [""]
      assert paths(Factory.check(%{"blueprint" => "nope"})) == ["blueprint"]
      assert paths(Factory.check(%{"blueprint" => "strut", "x" => 1})) == ["x"]
      assert paths(Factory.check(%{"blueprint" => "strut"})) == ["options.length"]

      assert paths(
               Factory.check(%{
                 "blueprint" => "l_track",
                 "options" => %{"length" => 1},
                 "colors" => %{"nope" => "#000000", "aluminum" => "x"}
               })
             ) ==
               ["colors.aluminum", "colors.nope"]

      assert paths(Factory.check(%{"blueprint" => "l_track", "options" => %{"length" => 1}, "colors" => []})) == [
               "colors"
             ]

      assert paths(Factory.check(%{"blueprint" => "l_track", "options" => %{"length" => 1}, "joints" => %{"a" => "x"}})) ==
               ["joints.a"]

      assert paths(Factory.check(%{"blueprint" => "l_track", "options" => %{"length" => 1}, "joints" => 1})) == [
               "joints"
             ]
    end

    test "a house checks its openings" do
      opening = fn x -> %{"wall" => "left", "kind" => "window", "x" => x, "width" => 1.0, "height" => 1.2} end

      assert {:ok, _} =
               Factory.check(%{
                 "blueprint" => "house",
                 "options" => %{"wall" => "studs", "openings" => [opening.(2.0)]}
               })

      assert paths(Factory.check(%{"blueprint" => "house", "options" => %{"openings" => [opening.(3.9)]}})) == [
               "options.openings.0"
             ]

      tall = %{"wall" => "front", "kind" => "door", "x" => 3.0, "width" => 0.9, "height" => 2.4}

      assert paths(Factory.check(%{"blueprint" => "house", "options" => %{"wall_height" => 2.5, "openings" => [tall]}})) ==
               ["options.openings.0"]
    end

    test "a van checks the items on its roof" do
      roof = fn items -> %{"blueprint" => "van", "options" => %{"roof" => items}} end
      solar = fn at -> %{"kind" => "solar", "at" => at} end
      fan = fn at -> %{"kind" => "fan", "at" => at} end

      assert {:ok, _} = Factory.check(roof.([solar.(3.75), fan.(5.15)]))
      assert paths(Factory.check(roof.([solar.(2.5)]))) == ["options.roof.0"]
      assert paths(Factory.check(roof.([fan.(5.5)]))) == ["options.roof.0"]
      assert paths(Factory.check(roof.([solar.(3.75), fan.(4.8)]))) == ["options.roof.1"]
    end

    test "a person needs one origin" do
      none = %{"african" => 0, "asian" => 0, "caucasian" => 0}
      assert paths(Factory.check(%{"blueprint" => "person", "options" => %{"origin" => none}})) == ["options.origin"]
    end
  end

  describe "a build" do
    test "the files of an order, with its colors and its joints" do
      order = %{
        "blueprint" => "catalog",
        "options" => %{"name" => "victron_lynx_distributor"},
        "colors" => %{"blue" => "#FF0000"},
        "joints" => %{"cover" => 30}
      }

      {:ok, out} = Factory.build(order, "far")
      assert <<"glTF", _::binary>> = out.glb
      json = Xuong.GLBHelper.json(out.glb)
      blue = Enum.find(json["materials"], &(&1["name"] == "blue"))
      assert hd(blue["pbrMetallicRoughness"]["baseColorFactor"]) == 1.0

      receipt = JSON.decode!(out.receipt)
      assert receipt["hash"] == Factory.hash(elem(Factory.check(order), 1))
      assert receipt["level"] == "far" and receipt["joints"] == ["cover"]
      assert receipt["order"]["colors"] == %{"blue" => "#ff0000"}
      assert JSON.decode!(out.parts)["parts"] != []
    end

    test "each blueprint builds its default, or a small order" do
      orders = [
        %{
          "blueprint" => "house",
          "options" => %{"wall" => "studs", "roof" => "metal", "length" => 4.0, "depth" => 3.5, "openings" => []}
        },
        %{
          "blueprint" => "house",
          "options" => %{
            "length" => 3.5,
            "depth" => 3.0,
            "openings" => [
              %{"wall" => "front", "kind" => "door", "x" => 1.0, "width" => 0.9, "height" => 2.0},
              %{"wall" => "front", "kind" => "window", "x" => 2.5, "width" => 0.8, "height" => 1.0}
            ]
          }
        },
        %{"blueprint" => "extrusion", "options" => %{"profile" => "1515", "length" => 0.2}},
        %{"blueprint" => "strut", "options" => %{"length" => 0.3}},
        %{"blueprint" => "l_track", "options" => %{"length" => 0.3}},
        %{
          "blueprint" => "van",
          "options" => %{
            "model" => "transit_148_medium",
            "windows" => "crew",
            "engine_bay" => ["dc_charger"],
            "roof" => [%{"kind" => "solar", "at" => 3.8}, %{"kind" => "fan", "at" => 5.2}]
          }
        },
        %{
          "blueprint" => "person",
          "options" => %{"hair" => "none", "pose" => "sit", "origin" => %{"african" => 0.5, "asian" => 0.5}}
        }
      ]

      for order <- orders do
        assert {:ok, %{glb: <<"glTF", _::binary>>}} = Factory.build(order, "far"), inspect(order)
      end
    end

    test "a wrong level, a joint that the model does not have, a wrong order" do
      order = %{"blueprint" => "strut", "options" => %{"length" => 0.3}}
      assert paths(Factory.build(order, "huge")) == ["level"]
      assert paths(Factory.build(Map.put(order, "joints", %{"door" => 1}), "far")) == ["joints.door"]
      assert paths(Factory.build(%{"blueprint" => "strut"}, "far")) == ["options.length"]
    end

    property "the JSON of a value has its keys in order, and JSON gives the value back" do
      check all(
              map <- map_of(string(:alphanumeric, min_length: 1), one_of([integer(), boolean(), string(:printable)])),
              max_runs: 50
            ) do
        bin = Factory.encode(map)
        assert JSON.decode!(bin) == map
        assert Factory.encode(Map.new(Enum.reverse(Map.to_list(map)))) == bin
      end
    end
  end
end
