Application.put_env(:world, World.Skills, extra: [World.ToySkills.Block, World.ToySkills.Note])
# The temporary files of the tests (System.tmp_dir!/0) go into tmp/ of this checkout, as
# the folders of `@tag :tmp_dir`: the tests of two checkouts at one time do not share a
# folder. (A file of one run made a test of the other give 200 in place of 202.)
tmp = Path.expand("tmp/system")
File.mkdir_p!(tmp)
System.put_env("TMPDIR", tmp)
# The files that the service builds in the tests go into a new folder (World.Files).
files = Path.join(System.tmp_dir!(), "world-files-test")
File.rm_rf!(files)
Application.put_env(:world, :files, files)
# A test can take minutes when a large model builds at the same time on the
# same cores (plan 0013). A test that builds a sculpture also waits for its
# turn at the gate of the node, behind the large models of the catalog
# (plan 0018: a row of houses, a hotel): the limit of a test is 15 minutes.
ExUnit.start(timeout: 900_000)
