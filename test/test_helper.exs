Application.put_env(:world, World.Skills, extra: [World.ToySkills.Block, World.ToySkills.Note])
# The files that the service builds in the tests go into a new folder (World.Files).
files = Path.join(System.tmp_dir!(), "world-files-test")
File.rm_rf!(files)
Application.put_env(:world, :files, files)
# A test can take minutes when a large model builds at the same time on the
# same cores (plan 0013). A test that builds a sculpture also waits for its
# turn at the gate of the node, behind the large models of the catalog
# (plan 0018: a row of houses, a hotel): the limit of a test is 15 minutes.
ExUnit.start(timeout: 900_000)
