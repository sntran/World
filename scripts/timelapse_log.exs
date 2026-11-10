# The log and the files of a construction of the statue on Núi Nhỏ, for
# the time lapse of the world page (plan 0006, D11): the events of the
# construction (events.jsonl), the GLB of each of its elements
# (builds/ID/elements/KEY.glb), a person with the animations of the work
# (worker.glb), and the places with the hill (places.json, ground.glb).
#
#   mix run scripts/timelapse_log.exs DIR [METHOD] [LEVEL] [STEP]
#
# METHOD is today (by default) or 1974, LEVEL mid (by default; the far
# level has no cast, so no bands, forms or scaffold) or near, STEP the
# grid of the ground in m (8 by default). The statue goes
# to its lot of the hill as the yard sends it, with no yard: the event
# place_started is the first event.
[dir | rest] = System.argv()
[method, level, step] = rest ++ Enum.drop(["today", "mid", "8"], length(rest))
File.mkdir_p!(dir)

order = put_in(World.Drawing.raw("tuong_chua_kito_vua"), ["options", "method"], method)
{:ok, job} = World.Orders.job(order, level)
{:ok, hill} = World.Places.fetch("nui_nho")
lot = Map.get(job, :lot) || "top"
geos = Map.new(World.Places.lots(hill), &{&1["name"], World.Places.geo(hill, &1["name"])})
id = "statue-#{method}-#{level}"
job = Map.merge(job, %{id: id, place: "nui_nho", lot: lot, geo: geos[lot], geos: geos})

:ok = World.watch(id)
{:ok, ^id} = World.build(job)

collect = fn collect, acc ->
  receive do
    {:world, %{"kind" => kind} = e} when kind in ~w(done stopped failed) -> Enum.reverse([e | acc])
    {:world, e} -> collect.(collect, [e | acc])
  after
    600_000 -> raise "no end of the construction"
  end
end

events = collect.(collect, [])
first = hd(events)
start = %{first | "id" => 0, "kind" => "place_started", "order" => "yard", "who" => nil, "data" => %{"order" => id, "place" => "nui_nho", "lot" => lot}}
lines = for e <- [start | events], do: JSON.encode!(e)
File.write!(Path.join(dir, "events.jsonl"), Enum.join(lines, "\n") <> "\n")

# The GLB of each element, while the construction keeps them.
keys = for %{"kind" => "element", "data" => %{"glb" => key}} <- events, uniq: true, do: key
elements = Path.join([dir, "builds", id, "elements"])
File.mkdir_p!(elements)
for key <- keys, {:ok, glb} = World.Construction.element(id, key), do: File.write!(Path.join(elements, key <> ".glb"), glb)

# A person of a site: the walk and the work of the trades, a hard hat.
person = %{"blueprint" => "person", "options" => %{"animations" => ["walk" | World.People.Pose.work()], "hat" => "hard_hat"}}
{:ok, worker} = World.Orders.build(person, "far", "glb")
File.write!(Path.join(dir, "worker.glb"), worker)

# The places with the hill, and its ground.
ground = World.Places.ground(put_in(hill, ["terrain", "step"], String.to_integer(step) / 1))
File.write!(Path.join(dir, "ground.glb"), World.Build.glb(ground))
places = for p <- World.Places.view(), do: if(p["terrain"], do: put_in(p, ["terrain", "ground"], Path.join(dir, "ground.glb") |> then(&("/" <> &1))), else: p)
File.write!(Path.join(dir, "places.json"), JSON.encode!(%{"places" => places, "speed_kmh" => 20}))

days = (List.last(events)["at"] - first["at"]) / World.Clock.day()
IO.puts("#{id}: #{length(events)} events, #{length(keys)} elements, #{Float.round(days, 1)} days")
