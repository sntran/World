defmodule World.EngineersTest do
  # The store of the proposals is a program of the application
  # environment: one test changes it, so the tests run one at a time.
  use ExUnit.Case, async: false

  alias World.{Engineers, MCP}

  @dir Path.join(System.tmp_dir!(), "world_engineers_test")

  # A stool of bamboo: a seat of slats on four legs of culms, with a
  # standard bolt in a leg.
  def stool do
    leg = fn x, y ->
      %{"tube" => %{"line" => [[x, y, 0], [x, y, 0.4]], "radius" => 0.02}, "material" => "bamboo", "skin" => 0.005}
    end

    %{
      "name" => "stool_test",
      "kind" => "furniture",
      "sources" => ["A test."],
      "parts" => %{
        "seat" => %{
          "shapes" => [%{"box" => %{"from" => [-0.18, -0.18, 0.4], "to" => [0.18, 0.18, 0.42]}, "material" => "bamboo"}],
          "ports" => %{"legs" => %{"at" => [0, 0, 0]}}
        },
        "legs" => %{
          "shapes" => for(x <- [-0.15, 0.15], y <- [-0.15, 0.15], do: leg.(x, y)),
          "ports" => %{"top" => %{"at" => [0, 0, 0]}}
        },
        "bolt" => %{"standard" => "bolt M6x50"}
      },
      "nodes" => [
        %{"name" => "legs", "part" => "legs"},
        %{"name" => "seat", "part" => "seat", "to" => "legs", "at" => "top", "port" => "legs"},
        %{
          "name" => "bolt",
          "part" => "bolt",
          "to" => "legs",
          "at" => %{"at" => [0.172, 0.15, 0.3], "axis" => [-1, 0, 0]},
          "port" => "head"
        }
      ]
    }
  end

  defp flush do
    receive do
      {:mix_shell, _, _} -> flush()
    after
      0 -> :ok
    end
  end

  setup do
    File.rm_rf!(@dir)
    on_exit(fn -> File.rm_rf!(@dir) end)
  end

  test "the review of a drawing that passes: no errors, no failed check, its mass, its size and its parts" do
    assert {:ok, r} = Engineers.review(stool())
    assert r["errors"] == [] and r["checks"] == [] and r["mass"]["unknown"] == []
    assert r["mass"]["kg"] > 0.5 and r["mass"]["kg"] < 2
    assert r["parts"] == %{"bolt_m6x50" => 1, "legs" => 1, "seat" => 1}
    assert [w, _, h] = r["size"]
    assert_in_delta h, 0.42, 1.0e-6
    assert w > 0.35
  end

  test "the review of a wrong drawing, of a model that tips over, and of a part with no mass" do
    assert {:error, %{"errors" => [%{"path" => "drawing.parts.bolt.standard"} | _]}} =
             Engineers.review(put_in(stool(), ["parts", "bolt"], %{"standard" => "rivet M6"}))

    tips =
      stool()
      |> put_in(["parts", "seat", "shapes"], [
        %{"box" => %{"from" => [0.5, -0.2, 0.4], "to" => [1.5, 0.2, 0.8]}, "material" => "steel"}
      ])

    assert {:error, %{"checks" => [check]}} = Engineers.review(tips)
    assert check =~ "it does not stand"

    painted =
      put_in(stool(), ["parts", "seat", "shapes"], [
        %{"box" => %{"from" => [-0.1, -0.1, 0.4], "to" => [0.1, 0.1, 0.42]}, "material" => "paint"}
      ])

    assert {:error, %{"checks" => [], "mass" => %{"unknown" => ["seat"]}}} = Engineers.review(painted)
  end

  test "a proposal goes into the store with its request; the owner accepts it into a folder of drawings" do
    assert {:ok, %{"hash" => hash, "review" => %{"name" => "stool_test"}}} =
             Engineers.propose(stool(), "A stool of bamboo.")

    assert {:ok, %{"request" => "A stool of bamboo.", "drawing" => drawing}} = Engineers.proposal(hash)
    assert drawing == stool()
    assert Engineers.proposal(String.duplicate("0", 32)) == :none
    assert Engineers.proposal("not a hash") == :none

    assert {:ok, path} = Engineers.accept(%{"drawing" => drawing}, @dir)
    assert JSON.decode!(File.read!(path)) == stool()
    assert Engineers.accept(%{"drawing" => drawing}, @dir) == {:error, :exists}

    assert {:error, %{"errors" => [%{"path" => "request"}]}} = Engineers.propose(stool(), "")

    assert {:error, %{"checks" => [_]}} =
             Engineers.propose(
               put_in(stool(), ["parts", "seat", "shapes"], [
                 %{"box" => %{"from" => [0.5, -0.2, 0.4], "to" => [1.5, 0.2, 0.8]}, "material" => "steel"}
               ]),
               "A stool."
             )
  end

  test "the tools check_drawing and propose_drawing of the MCP server" do
    call = fn name, args ->
      body =
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => name, "arguments" => args}
        })

      {200, %{"result" => r}} = MCP.answer(body, "2025-11-25", "https://world.mkfifo.com")
      r
    end

    assert %{"structuredContent" => %{"checks" => []}} = call.("check_drawing", %{"drawing" => stool()})
    assert %{"isError" => true} = call.("check_drawing", %{"drawing" => %{"name" => "x"}})
    assert %{"isError" => true} = call.("check_drawing", %{})

    assert %{"structuredContent" => %{"hash" => _}} =
             call.("propose_drawing", %{"drawing" => stool(), "request" => "A stool."})

    assert %{"isError" => true} = call.("propose_drawing", %{"drawing" => stool()})
  end

  test "the store of the proposals fails" do
    old = Application.get_env(:world, World.Orders.Store, [])
    Application.put_env(:world, World.Orders.Store, program: "/no/such/program")
    on_exit(fn -> Application.put_env(:world, World.Orders.Store, old) end)

    assert Engineers.propose(stool(), "A stool.") == {:error, :store}
    assert Engineers.proposal(String.duplicate("0", 32)) == :error

    body =
      JSON.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "propose_drawing", "arguments" => %{"drawing" => stool(), "request" => "A stool."}}
      })

    {200, %{"result" => r}} = MCP.answer(body, "2025-11-25", "https://world.mkfifo.com")
    assert r["isError"] and hd(r["structuredContent"]["errors"])["message"] =~ "the store of the proposals failed"
  end

  test "mix world.review: the sheet of a proposal, and the accept into the catalog" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    File.mkdir_p!(@dir)
    file = Path.join(@dir, "p.json")
    File.write!(file, JSON.encode!(%{"request" => "A stool.", "drawing" => stool()}))

    Mix.Tasks.World.Review.run([file])
    assert_received {:mix_shell, :info, [sheet]}
    assert sheet =~ "Request: A stool." and sheet =~ "1 x bolt_m6x50" and sheet =~ "all pass"

    Mix.Tasks.World.Review.run([file, "--accept", "--dir", Path.join(@dir, "drawings")])
    assert File.exists?(Path.join([@dir, "drawings", "stool_test.json"]))

    assert_raise Mix.Error, ~r/is in the catalog/, fn ->
      Mix.Tasks.World.Review.run([file, "--accept", "--dir", Path.join(@dir, "drawings")])
    end

    {:ok, %{"hash" => hash}} = Engineers.propose(stool(), "A stool from the store.")
    Mix.Tasks.World.Review.run([hash])
    assert_received {:mix_shell, :info, [_]}

    bad = Path.join(@dir, "bad.json")

    File.write!(
      bad,
      JSON.encode!(%{
        "request" => "A bad one.",
        "drawing" =>
          put_in(stool(), ["parts", "seat", "shapes"], [
            %{"box" => %{"from" => [-0.1, -0.1, 0.4], "to" => [0.1, 0.1, 0.42]}, "material" => "paint"}
          ])
      })
    )

    flush()
    assert_raise Mix.Error, ~r/does not pass/, fn -> Mix.Tasks.World.Review.run([bad, "--accept", "--dir", @dir]) end
    assert_received {:mix_shell, :info, [unknown]}
    assert unknown =~ "no mass: seat"

    wrong = Path.join(@dir, "wrong.json")
    File.write!(wrong, JSON.encode!(%{"request" => "A wrong one.", "drawing" => %{"name" => "x"}}))
    flush()
    Mix.Tasks.World.Review.run([wrong])
    assert_received {:mix_shell, :info, [errors]}
    assert errors =~ "Errors:"

    assert_raise Mix.Error, ~r/No proposal/, fn -> Mix.Tasks.World.Review.run([String.duplicate("0", 32)]) end
    assert_raise Mix.Error, ~r/Give one proposal/, fn -> Mix.Tasks.World.Review.run([]) end

    old = Application.get_env(:world, World.Orders.Store, [])
    Application.put_env(:world, World.Orders.Store, program: "/no/such/program")
    on_exit(fn -> Application.put_env(:world, World.Orders.Store, old) end)
    assert_raise Mix.Error, ~r/failed/, fn -> Mix.Tasks.World.Review.run([String.duplicate("0", 32)]) end
  end
end

defmodule World.EngineersDrawingTest do
  use ExUnit.Case, async: true

  test "a standard part, a matter and a skin in a drawing, and their errors" do
    d = World.EngineersTest.stool()
    paths = fn d -> with {:error, e} <- World.Drawing.check(d, "d"), do: Enum.map(e, &elem(&1, 0)) end

    assert paths.(put_in(d, ["parts", "bolt"], %{"standard" => "bolt M7x40"})) == ["d.parts.bolt.standard"]
    assert paths.(put_in(d, ["parts", "bolt"], %{"standard" => "bolt"})) == ["d.parts.bolt.standard"]
    assert paths.(put_in(d, ["parts", "bolt"], %{"standard" => 5})) == ["d.parts.bolt.standard"]

    assert paths.(put_in(d, ["parts", "bolt"], %{"standard" => "bolt M6x50", "shapes" => []})) == [
             "d.parts.bolt.shapes"
           ]

    assert paths.(put_in(d, ["nodes", Access.at(2), "port"], "nope")) == ["d.nodes.2.port"]

    seat = ["parts", "seat", "shapes", Access.at(0)]
    assert paths.(put_in(d, seat ++ ["matter"], "gold")) == ["d.parts.seat.shapes.0.matter"]
    assert paths.(put_in(d, seat ++ ["skin"], 1)) == ["d.parts.seat.shapes.0.skin"]

    # A box of paint with a matter of steel has the mass of its steel.
    d =
      put_in(d, seat, %{
        "box" => %{"from" => [-0.1, -0.1, 0.4], "to" => [0.1, 0.1, 0.42]},
        "material" => "paint",
        "matter" => "steel"
      })

    {:ok, raw} = World.Drawing.check(d, "d")
    {_, seat_part, _} = List.keyfind(World.Drawing.build(raw).nodes, "seat", 0)
    assert_in_delta World.Mass.part(seat_part).mass, 0.2 * 0.2 * 0.02 * 7820, 1.0e-6
  end
end
