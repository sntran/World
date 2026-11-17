# Makes each asset of MakeHuman in priv/makehuman/ with more triangles
# than World.People.Thin.budget/0 thin (World.People.Thin): its OBJ and
# its MHCLO are written again. Run it after scripts/makehuman.py:
#
#     mix run scripts/thin.exs
alias World.People.{Data, Thin}

for {kind, entries} <- Data.assets(), {name, %{"obj" => obj, "fit" => fit}} <- entries do
  dir = Path.join(Data.dir(), kind)
  read = &:zlib.gunzip(File.read!(Path.join(dir, &1)))
  text = read.(obj)
  n = Thin.triangles(text)

  if n > Thin.budget() do
    {thin, fit_text} = Thin.thin(text, read.(fit), Thin.budget())
    File.write!(Path.join(dir, obj), :zlib.gzip(thin))
    File.write!(Path.join(dir, fit), :zlib.gzip(fit_text))
    IO.puts("#{kind}/#{name}: #{n} -> #{Thin.triangles(thin)} triangles")
  end
end
