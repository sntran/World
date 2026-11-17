# Packs the targets of the body (priv/makehuman/targets.bin.gz and
# targets_child.bin.gz, of scripts/makehuman.py) into
# priv/makehuman/targets.pack, and deletes the two files:
#
#     mix run scripts/targets.exs
#
# In the pack each target is compressed alone, after an index of the
# names, so a person reads only its targets (World.People.Data). The two
# tables in memory were 34 MB, and the memory of the edge is 128 MB.
dir = Path.join(:code.priv_dir(:world), "makehuman")
files = for f <- ~w(targets.bin.gz targets_child.bin.gz), do: Path.join(dir, f)
tables = for f <- files, do: f |> File.read!() |> :zlib.gunzip() |> World.People.Data.parse_targets()
pack = tables |> Enum.reduce(&Map.merge(&2, &1)) |> World.People.Data.pack_targets()
File.write!(Path.join(dir, "targets.pack"), pack)
Enum.each(files, &File.rm!/1)
IO.puts("Wrote targets.pack: #{div(byte_size(pack), 1000)} KB.")
