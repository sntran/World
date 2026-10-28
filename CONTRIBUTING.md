# Contributing to World

## Build and test

Use [`beam.com`](https://github.com/sntran/BEAM.com) 0.1.0-rc.6 for all
the work: it is Erlang/OTP 29.1.1 and Elixir 1.20.4 in one file. Make
the tools `mix.com` and `iex.com` from it:

```sh
mkdir -p ~/bin && cd ~/bin
curl -fLO https://github.com/sntran/BEAM.com/releases/download/v0.1.0-rc.6/beam.com
echo "ac841b72180467773d95d0eec1c7a757b67e003e576a6ba34d8debb40fe6b903  beam.com" | sha256sum -c -
chmod +x beam.com
ln -s beam.com mix.com
ln -s beam.com iex.com
export PATH=~/bin:$PATH LANG=C.UTF-8
mix.com local.hex --force
mix.com local.rebar --force
```

From step 1, in the directory of the project:

```sh
mix.com deps.get
mix.com test --cover            # the coverage must be 100%; it checks specs/ too
mix.com accord.check --extra specs/MCOrder.tla   # the model check alone
mix.com world.build             # the files of priv/models
mix.com world.build --check     # build again and compare, as CI does
npm install && npm test         # the Khronos validator on each GLB
sh scripts/wings.sh COMMIT      # copy the core of Wings 3D again
```

The review page shows each model of `priv/models`:

```sh
python3 -m http.server -d . 8000   # then open http://localhost:8000/review/
```

## Add a part

1. Find the source of each size: the standard, the data sheet, or a
   measurement with its tool.
2. Write the function of the part in the context of its family
   (`AGENTS.md`, "The contexts"), with its ports
   (`docs/format.md`, "A port") and its `sources`.
3. Write its tests: a property test that each size agrees with the table
   of its standard, and a test of each port.
4. Look at it on the review page. Add a picture to the pull request.

A shaped part is a `.wings` file in `parts/`, and a module next to it
with its name, its sources and its ports. Make the shape in Wings 3D,
and give each material the name of its role (`docs/format.md`, "The
materials").

## Add a model

A model is an assembly in the context of its family. Connect each part to its
parent at two ports, with the kind of the connection. Give each joint
its role. Then run `mix.com world.build` and commit the files of
`priv/models` with the code.

## Rules for a change

- Each change has tests of its behavior, also for errors and limits, not
  only for the normal case. Write property tests (StreamData) where you
  can.
- The coverage of the tests is 100%: each line runs in a test. Do not
  keep code that no feature uses.
- Keep each change small, and give it one purpose.
- Make a branch from `main` for each change, with the type of the change
  as a prefix: `feat/`, `fix/`, `docs/`, `test/`, `refactor/`, `build/`.
- Write the commit message in the format of
  [Conventional Commits](https://www.conventionalcommits.org/), in
  Simplified Technical English: `feat(parts): add the ISO 4032 nut`.
- A model from another person comes in only under the AGPL-3.0. Write
  in the pull request that you agree to give it under this license.
- An asset from outside (a texture, a mesh) keeps its own license. Put
  it in its own folder, with a line in `CREDITS.md`. Use only a license
  that agrees with the AGPL-3.0 (for example CC0 or CC-BY).

## The language of the docs

The docs, the code comments, the log text and the commit messages use
[ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/):

- Write short sentences: 20 words or fewer for an instruction, 25 words
  or fewer for a description.
- Use the active voice and the present tense.
- Use one word for one meaning, and the same word in all the files.
- Give one instruction in each sentence, and start it with the verb.
- Do not use the "-ing" form of a verb, except in a technical name.
