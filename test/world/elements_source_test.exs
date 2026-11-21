defmodule World.Elements.SourceTest do
  use ExUnit.Case, async: true

  alias World.Elements.{Source, Sources}

  # A small project: the forms that the read of the source knows.
  @files %{
    "lib/a.ex" => ~S'''
    defmodule Demo.A do
      alias Demo.{B, C}
      alias Demo.D, as: Dee
      alias Demo.Base
      alias Base.Sub
      alias :lists, as: L
      alias __MODULE__.Inner, as: In
      require Demo.Macros
      import Demo.Imp
      @moduledoc "A module."
      @root Path.expand("../priv/things", __DIR__)
      @files Path.wildcard(Path.join(@root, "*.json"))
      for f <- @files, do: @external_resource(f)
      @external_resource path = Path.join([__DIR__, "..", "priv", "one.json"])
      @script Path.expand("../scripts/x.mjs", __DIR__)
      @lost Path.join(@unknown, "y")
      @loop_a Path.join(@loop_b, "a")
      @loop_b Path.join(@loop_a, "b")
      @five p = Path.join([__DIR__, "..", "priv", "five.json"])
      @grow Path.expand("../priv", __DIR__)
      @grow Path.join(@grow, "six")
      @table Demo.E.table()
      @list [Demo.Value]
      defstruct [:x]

      defmodule Inner do
        def f, do: %Demo.F{}
      end

      defmodule __MODULE__.Deep do
      end

      @doc "A doc."
      @spec g() :: Demo.Type.t()
      def g, do: B.run() |> C.run() |> Dee.run() |> Sub.run()
      def h, do: Inner.f() ++ __MODULE__.Inner.f() ++ L.reverse([])
      def i(x), do: File.read!(Path.join([:code.priv_dir(:demo), "two", x <> ".json"]))
      def j(x), do: File.read!(Path.join(__DIR__, "../priv/four/#{x}"))
      def k, do: :erl_mod.call() && Path.join(["a", "b"]) && Path.join(@loop_a, "c")
      def m(x), do: unquote(x).Foo.bar()
      def o, do: In.f() && Path.join(@grow, "x.json")

      def n do
        alias Demo.G, as: Gee
        Gee.run()
      end
    end
    ''',
    "lib/b.ex" => ~S'''
    defmodule Demo.B, do: def(run, do: :ok)
    defmodule Demo.C, do: def(run, do: :ok)
    defmodule Demo.D, do: def(run, do: :ok)
    defmodule Demo.Base.Sub, do: def(run, do: :ok)
    defmodule Demo.E, do: def(table, do: :ok)
    defmodule Demo.F, do: defstruct([])
    defmodule Demo.Macros, do: defmacro(m, do: :ok)
    defmodule Demo.Imp, do: def(i, do: :ok)
    defmodule Demo.Value, do: def(v, do: :ok)
    defmodule Demo.Type, do: @type(t :: term())
    defmodule Demo.G, do: def(run, do: :ok)
    defmodule :demo_atom, do: def(a, do: :ok)
    Demo.Lone.run()

    if true do
      defmodule Demo.InIf, do: def(x, do: Demo.Lone.run())
    end
    ''',
    "lib/lone.ex" => "defmodule Demo.Lone, do: def(run, do: :ok)\n",
    "lib/other.ex" => "defmodule Demo.Other, do: def(o, do: :ok)\n",
    "wings/src/x.erl" => "-module(erl_mod).\n-include(\"x.hrl\").\ncall() -> y_mod:go().\n",
    "wings/src/x.hrl" => "-define(X, 1).\n",
    "wings/src/y_mod.erl" => "go() -> ok.\n",
    "priv/things/a.json" => "{}",
    "priv/things/b.json" => "[]",
    "priv/one.json" => "1",
    "priv/five.json" => "5",
    "priv/six/x.json" => "6",
    "priv/two/c.json" => "2",
    "priv/four/d.txt" => "4",
    "priv/other.json" => "3"
  }

  defp project(root) do
    for {path, text} <- @files do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.write!(Path.join(root, path), text)
    end

    Source.analyze(root, @files |> Map.keys() |> Enum.sort())
  end

  defp root(name), do: Path.join(System.tmp_dir!(), "source-#{name}-#{System.unique_integer([:positive])}")

  test "the read of a file: its modules, the modules that it calls or takes, and the data files that it reads" do
    m = project(root("read"))

    assert m.modules[Demo.A] == "lib/a.ex" and m.modules[Demo.A.Inner] == "lib/a.ex" and
             m.modules[Demo.A.Deep] == "lib/a.ex"

    assert m.modules[:demo_atom] == "lib/b.ex" and m.modules[Demo.InIf] == "lib/b.ex" and
             m.modules[:erl_mod] == "wings/src/x.erl" and
             m.modules[:y_mod] == "wings/src/y_mod.erl"

    # (A call, a struct, require, import, a call at the compile, an alias of each kind; not a value, a type or a doc.)
    assert m.refs["lib/a.ex"] ==
             Enum.sort([Demo.B, Demo.C, Demo.D, Demo.Base.Sub, Demo.E, Demo.F, Demo.G, Demo.Macros, Demo.Imp, :erl_mod])

    assert m.refs["lib/b.ex"] == [Demo.Lone] and m.refs["wings/src/x.erl"] == [:y_mod]

    assert m.data["lib/a.ex"] ==
             ~w(priv/five.json priv/four/d.txt priv/one.json priv/six/x.json priv/things/a.json priv/things/b.json priv/two/c.json)

    assert m.data["wings/src/x.erl"] == ["wings/src/x.hrl"] and m.data["lib/b.ex"] == []
  end

  test "the files of a version: the files that the rule takes, again and again, and their data; a change of another file does not change it" do
    m = project(root("files"))
    files = Source.files(m, Demo.A)

    assert files ==
             Enum.sort(
               ~w(lib/a.ex lib/b.ex lib/lone.ex wings/src/x.erl wings/src/x.hrl wings/src/y_mod.erl) ++
                 m.data["lib/a.ex"]
             )

    refute "lib/other.ex" in files or "priv/other.json" in files
    assert Source.files(m, :lists) == [] and Source.files(m, Demo.Other) == ["lib/other.ex"]

    version = Source.version(m, Demo.A)
    assert version =~ ~r/^[0-9a-f]{12}$/ and Source.version(m, Demo.A) == version
    changed = fn path -> Source.version(put_in(m, [:digests, path], :erlang.md5("new")), Demo.A) end

    assert changed.("priv/one.json") != version and changed.("wings/src/x.hrl") != version and
             changed.("lib/lone.ex") != version

    assert changed.("priv/other.json") == version and changed.("lib/other.ex") == version
  end

  test "two folders of the same files give the same read" do
    assert project(root("one")) == project(root("two-#{System.unique_integer([:positive])}/deeper"))
  end

  test "the modules of the service, and the module World with no module in it, are not a part of a rule" do
    assert Enum.all?([World, World.Orders.Store, World.Sculpt.Gate], &Source.service?/1)
    refute Enum.any?([World.Skills.Sculpt, World.Sculpt], &Source.service?/1)
  end

  test "the read of World: each module of lib, the macros of the SDF in the version of a sculpture, and not the catalog of drawings" do
    m = Sources.get()
    {:ok, modules} = :application.get_key(:world, :modules)

    for module <- modules, source = module.module_info(:compile)[:source], List.to_string(source) =~ "/lib/world" do
      assert Map.has_key?(m.modules, module), "#{inspect(module)} is not in the read of the source"
    end

    sculpt = Source.files(m, World.Skills.Sculpt)
    assert "lib/world/sdf/inline.ex" in sculpt and "priv/palette.json" in sculpt and "wings/e3d/e3d_mesh.erl" in sculpt
    refute "lib/world.ex" in sculpt or Enum.any?(sculpt, &String.starts_with?(&1, "priv/drawings/"))

    assert Enum.all?(
             Source.files(m, World.Drawing.Catalog) |> Enum.filter(&(&1 =~ "priv/drawings")),
             &String.ends_with?(&1, ".json")
           )

    assert "priv/plants/species.json" in m.data["lib/world/plants.ex"]
    assert "priv/data/vans.json" in m.data["lib/world/vehicles/van.ex"]
    assert Enum.any?(m.data["lib/world/references.ex"], &String.starts_with?(&1, "priv/references/"))
    refute Enum.any?(Map.values(m.data), &("priv" in &1))
    assert World.Elements.version(World.Skills.Sculpt) == Source.version(m, World.Skills.Sculpt)
    refute Sources.__mix_recompile__?()
  end
end
