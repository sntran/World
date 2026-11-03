# The data of MakeHuman

The data in this folder is from [MakeHuman](http://www.makehumancommunity.org/).
Its license is **CC0** (public domain): you can use it, change it and
share it with no conditions. The exception is some clothes of the
community with the license **CC BY**: an app that shows them names
their authors (`CREDITS.md` of World has the list; `assets.json` has
the `author` and the `license` of each item). `World.People.Human`
makes people from it.

`scripts/makehuman.py` makes this folder from these sources:

| Source | Version | SHA-256 |
|---|---|---|
| [makehumancommunity/mpfb2](https://github.com/makehumancommunity/mpfb2), `src/mpfb/data`: the base mesh, the targets of the body (`macrodetails`), the units of the expressions of the face (`expression/units`: the mouth, the eyes, the brows, the nose), the skeleton `game_engine` and its weights | commit `6ff1eb358f6c1959ced77e79e6dd2406d9a71f49` | |
| The release `people-packs-1` of `sntran/Vung_Tau`: `makehuman_system_assets.zip` (skins, eyes, eyebrows, eyelashes, hair, clothes, low-poly bodies, the teeth `teeth_base` and the tongue `tongue01`) | | `b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107` |
| The same release: `pants01.zip` (`cortu_cargo_pants`) | | `e4e0ec60db34f279be291a83cfd7b342a7c5cf09bb7676682a5f39f4f6ac4ad9` |
| The same release: `shirts01.zip` (`elvs_crude_t-shirt_male`, `joepal_crude_t-shirt_female`) | | `a5a723b0e84a109bb190fcfeac7f1de4138d875da3e30fe5b3340eac9f38bcd3` |
| The asset packs of the community site ([static.makehumancommunity.org/assets/assetpacks.html](https://static.makehumancommunity.org/assets/assetpacks.html)), with only the chosen clothes for travelers: `shoes01`, `shirts01`, `pants01`, `hats01`, `gloves01` (CC0) and `shoes02`, `shoes03`, `shirts02`, `pants02`, `pants03` (CC BY) | downloaded 2026-11-03 | |

The packs of the release are copies of the asset packs of MakeHuman,
each with the license CC0. The clothes of the community came later, with
no change to the other files:
`python3 -I scripts/makehuman.py MPFB_DATA PACKS_DIR NAME...` (the names
of the items; the script takes their author and license from its table
`CREDITS`, from the pack pages).

The files `clothes/world_*` are not from MakeHuman: they are the
clothes that World makes from the base mesh (`World.Clothes`,
the license of World). `scripts/makehuman.py` with no names deletes the
folder first: after it, `mix run scripts/clothes.exs` writes them
again.

## The changes

- The base mesh, the skeleton, the weights, the meshes and the fit files
  of the assets are the same, in gzip.
- The targets are in a small binary format (`World.People.Data`), in
  steps of 0.25 mm: `targets.bin.gz` (the body) and `expressions.bin.gz`
  (33 units of the face, 13 of them of the mouth, for each of the three
  origins:
  `python3 scripts/makehuman.py MPFB_DATA --expressions`).
- The teeth and the tongue came later, with no change to the other
  files: `python3 scripts/makehuman.py MPFB_DATA PACKS_DIR teeth tongue`.
- The eye color `darkbrown` is not in MakeHuman: the script makes it
  from `brown` (its iris is red-brown) with a dark brown iris
  (`python3 scripts/makehuman.py MPFB_DATA PACKS_DIR eye_materials`).
- The textures are smaller (1024, 512 or 256 pixels), with no color
  profile.
- The textures of the hair are gray, made bright, so a hair can have
  any color (`docs/format.md`, "A person").
- `assets.json` lists the assets, with the mean color of each texture.
