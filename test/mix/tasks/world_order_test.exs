defmodule Mix.Tasks.World.OrderTest do
  use ExUnit.Case

  @dir Path.join(System.tmp_dir!(), "world_order_test")

  setup do
    File.rm_rf!(@dir)
    File.mkdir_p!(@dir)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  defp order(json) do
    path = Path.join(@dir, "order.json")
    File.write!(path, json)
    path
  end

  test "writes the files of an order, with the hash as the name" do
    path = order(~s({"blueprint": "l_track", "options": {"length": 0.2}}))
    Mix.Tasks.World.Order.run([path, "--dir", Path.join(@dir, "out")])
    {:ok, full} = World.Orders.check(%{"blueprint" => "l_track", "options" => %{"length" => 0.2}})
    hash = World.Orders.hash(full)
    assert_received {:mix_shell, :info, ["Wrote the files of " <> _]}

    for ext <- ~w(.glb .mid.glb .far.glb .parts.json .receipt.json),
        do: assert(File.exists?(Path.join([@dir, "out", hash <> ext])), ext)
  end

  test "a wrong order, and a wrong call, stop the task" do
    assert_raise Mix.Error, ~r/options.length: is required/, fn ->
      Mix.Tasks.World.Order.run([order(~s({"blueprint": "strut"}))])
    end

    assert_raise Mix.Error, ~r/Give one file/, fn -> Mix.Tasks.World.Order.run([]) end
  end
end
