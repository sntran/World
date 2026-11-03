# Writes the files of the jackets of World (World.Clothes) in
# priv/makehuman/clothes/:
#
#     mix run scripts/clothes.exs
#
# test/world/clothes_test.exs checks that the files are the same as the
# module makes them.
dir = Path.join(:code.priv_dir(:world), "makehuman/clothes")
for {name, bin} <- World.Clothes.files(), do: File.write!(Path.join(dir, name), bin)
IO.puts("Wrote #{length(World.Clothes.files())} files.")
