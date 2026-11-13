Application.put_env(:world, World.Skills, extra: [World.ToySkills.Block, World.ToySkills.Note])
# A test can take minutes when a large model builds at the same time on the
# same cores (plan 0013): the limit of a test is 5 minutes, not 1.
ExUnit.start(timeout: 300_000)
