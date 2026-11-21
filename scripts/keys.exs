# The keys of the parts of a set of orders (docs/factory.md, "One key in
# each folder"):
#
#   WORLD_ORDER_DIR=STORE mix.com run scripts/keys.exs ORDERS.json OUT.json
#
# ORDERS.json has "orders": [{"name", "level", "order"}] (as
# test/fixtures/keys/orders.json). For each order, OUT.json gets the key
# of each part of its parts list at the level, in the order of the list,
# and the version of each rule that made a part. STORE is a folder of its
# own: the parts lists put their parts and their recipes there.
#
# Two builds of one commit in two folders give the same OUT.json. A change
# to a data file of a rule changes only the keys of the parts of that rule.
[orders_path, out] = System.argv()

result =
  for %{"name" => name, "level" => level, "order" => order} <- JSON.decode!(File.read!(orders_path))["orders"],
      into: %{} do
    {:ok, json} = World.Orders.build(order, level, "elements")
    keys = for p <- JSON.decode!(json)["parts"], do: p["key"]
    IO.puts("#{name} #{level}: #{length(keys)} parts")
    {name, keys}
  end

rules = [World.Build, World.Skills.Sculpt, World.Orders.Blueprints]
versions = Map.new(rules, &{inspect(&1), World.Elements.version(&1)})
File.write!(out, JSON.encode!(%{"keys" => result, "versions" => versions}))
