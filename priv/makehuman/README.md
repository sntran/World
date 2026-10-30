# The data of MakeHuman

The data in this folder is from [MakeHuman](http://www.makehumancommunity.org/).
Its license is **CC0** (public domain): you can use it, change it and
share it with no conditions. `World.People.Human` makes people from it.

`scripts/makehuman.py` makes this folder from these sources:

| Source | Version | SHA-256 |
|---|---|---|
| [makehumancommunity/mpfb2](https://github.com/makehumancommunity/mpfb2), `src/mpfb/data`: the base mesh, the targets of the body (`macrodetails`), the units of the expressions of the mouth (`expression/units`), the skeleton `game_engine` and its weights | commit `6ff1eb358f6c1959ced77e79e6dd2406d9a71f49` | |
| The release `people-packs-1` of `sntran/Vung_Tau`: `makehuman_system_assets.zip` (skins, eyes, eyebrows, eyelashes, hair, clothes, low-poly bodies) | | `b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107` |
| The same release: `pants01.zip` (`cortu_cargo_pants`) | | `e4e0ec60db34f279be291a83cfd7b342a7c5cf09bb7676682a5f39f4f6ac4ad9` |
| The same release: `shirts01.zip` (`elvs_crude_t-shirt_male`, `joepal_crude_t-shirt_female`) | | `a5a723b0e84a109bb190fcfeac7f1de4138d875da3e30fe5b3340eac9f38bcd3` |

The packs of the release are copies of the asset packs of MakeHuman,
each with the license CC0.

## The changes

- The base mesh, the skeleton, the weights, the meshes and the fit files
  of the assets are the same, in gzip.
- The targets are in a small binary format (`World.People.Data`), in
  steps of 0.25 mm: `targets.bin.gz` (the body) and `expressions.bin.gz`
  (the 13 units of the mouth for each of the three origins:
  `python3 scripts/makehuman.py MPFB_DATA --expressions`).
- The textures are smaller (1024, 512 or 256 pixels), with no color
  profile.
- The textures of the hair are gray, made bright, so a hair can have
  any color (`docs/format.md`, "A person").
- `assets.json` lists the assets, with the mean color of each texture.
