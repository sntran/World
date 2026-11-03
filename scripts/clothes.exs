# Writes the files of the garments of World (World.Sewing) in
# priv/makehuman/clothes/:
#
#     mix run scripts/clothes.exs
#
# test/world/sewing_test.exs checks that the files are the same as the
# module makes them.
dir = Path.join(:code.priv_dir(:world), "makehuman/clothes")
for {name, bin} <- World.Sewing.files(), do: File.write!(Path.join(dir, name), bin)
IO.puts("Wrote #{length(World.Sewing.files())} files.")
