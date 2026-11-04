# Credits

The assets from outside, each with its license. The code and the models
of World are under the AGPL-3.0 (`LICENSE`).

| Folder | What | Source | License |
|---|---|---|---|
| `priv/osm/ba_cu.json` | The buildings, the roads and the trees of one block of the street Ba Cu, Vũng Tàu (2026-11-03), and the street of World made from them (`street_ba_cu`) | © OpenStreetMap contributors, [openstreetmap.org](https://www.openstreetmap.org/copyright), from the Overpass API | ODbL 1.0: the file is a derived database under the same license |
| `wings/` | The mesh core of Wings 3D | [dgud/wings](https://github.com/dgud/wings) | The terms of Wings 3D (`wings/LICENSE`) |
| `priv/makehuman/` | The base mesh, the targets, the units of the expressions of the mouth, the skeleton, the skins, the hair and the clothes of people | [MakeHuman](http://www.makehumancommunity.org/) (`priv/makehuman/README.md`) | CC0, except some clothes of the community (below): CC BY |
| `priv/animals/meshes/shiba_inu.json`, `wolf.json`, `fox.json`, `deer.json`, `horse.json`, `donkey.json`, `cow.json`, `bull.json`, `alpaca.json`, `husky.json`, `stag.json` | The base meshes, the bones, the weights and the colors of the materials of the templates of the four-legged animals (from the glTF files, by `scripts/gltf_figure.exs`) | Quaternius, [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html), the glTF files from [PixelTriks](https://pixeltriks.com/browse?pack=quaternius-ultimate-animated-animals) | CC0 |
| `priv/animals/meshes/pig.json`, `sheep.json` | The base meshes, the bones, the weights and the colors of the materials of the templates pig and sheep (from the FBX files, by `scripts/fbx_gltf.exs` and `scripts/gltf_figure.exs`) | Quaternius, [Farm Animals Pack](https://opengameart.org/content/lowpoly-animated-farm-animal-pack) | CC0 |
| `priv/animals/clips/*.json` (not `primate.json`) | The clips of the templates of the four-legged animals (from the animations Walk, Gallop, Idle, Eating, Idle_HeadLow, Attack, Attack_Kick, Gallop_Jump, Jump_ToIdle, Idle_HitReact1, Idle_HitReact2 and Death of the same glTF files, by `scripts/gltf_clips.exs`) | Quaternius, [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html), the glTF files from [PixelTriks](https://pixeltriks.com/browse?pack=quaternius-ultimate-animated-animals) | CC0 |
| `priv/animals/clips/primate.json` | The walk, the run and the sit of the template of primates (by `scripts/bigmaq_clips.exs`: on the bones of World, the loops closed, the fingers and the toes level) | BigMaQ (L. Martini and others), [pose reconstructions](https://zenodo.org/records/20663410): action 458, individual G (walk); action 203, individual L (run); action 415, individual G (sit) | CC BY 4.0 |
| `priv/animals/spaces/wolf.json` | The shape space of the template wolf: the shape changes of the eleven templates of the four-legged animals on the Ultimate rig that the numbers do not give, and their principal components (by `scripts/shape_space.exs`) | Quaternius, [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html), the glTF files from [PixelTriks](https://pixeltriks.com/browse?pack=quaternius-ultimate-animated-animals) | CC0 |
| `priv/animals/meshes/primate.json`, `priv/animals/meshes/primate_upright.json` | The base mesh, the bones and the weights of the templates of primates (`primate_upright`: the arms up at rest, no tail): the low-poly template mesh of a rhesus macaque, its 115 bones and its weights (by `scripts/primate_template.exs`, in the pose at rest of the body plan; the eyes are of World) | [BigMaQ](https://github.com/martinivis/BigMaQ) (L. Martini and others, "BigMaQ: A Big Macaque Motion and Animation Dataset Bridging Image and 3D Pose Representations", ICLR 2026); the template mesh came from the Max Planck Institute for Intelligent Systems and M. J. Black (see below) | MIT |

## The clothes of the MakeHuman community

These clothes in `priv/makehuman/clothes/` come from the asset packs of
the MakeHuman community
([static.makehumancommunity.org/assets/assetpacks.html](https://static.makehumancommunity.org/assets/assetpacks.html)).
The author and the license of each item are from the table of its pack
page. World changes them as the other assets of MakeHuman
(`priv/makehuman/README.md`: the mesh and its fit in gzip, a smaller
texture). An item with the license CC BY needs its author named where
World or an app shows it.

| Item | Author | Pack | License |
|---|---|---|---|
| `cortu_jeans_shorts` | Cortu | pants01 | CC0 |
| `culturalibre_male_boots` | culturalibre | shoes01 | CC0 |
| `culturalibre_sneakers` | culturalibre | shoes02 | CC BY |
| `elvs_caesar_sandals1` | Elvaerwyn | shoes02 | CC BY |
| `elvs_hooded_sweat_jacket1` | Elvaerwyn | shirts02 | CC BY |
| `elvs_jeans_straight_leg` | Elvaerwyn | pants02 | CC BY |
| `elvs_male_flip_flop_sandals1` | Elvaerwyn | shoes02 | CC BY |
| `elvs_male_shirt_untucked_bd1` | Elvaerwyn | shirts02 | CC BY |
| `elvs_male_trouser_short_1` | Elvaerwyn | pants03 | CC BY |
| `jujube_newsboy_cap` | jujube | hats01 | CC0 |
| `maciekg_leather_boots` | MaciekG | shoes03 | CC BY |
| `mindfront_female_trousers_1` | Mindfront | pants02 | CC BY |
| `mindfront_knitted_sweater_01` | Mindfront | shirts02 | CC BY |
| `mindfront_male_trousers_1` | Mindfront | pants02 | CC BY |
| `mindfront_shoes_biker_boots_female` | Mindfront | shoes03 | CC BY |
| `mindfront_shoes_biker_boots_male` | Mindfront | shoes03 | CC BY |
| `namuhekam_male_polo_shirt` | namuhekam | shirts01 | CC0 |
| `punkduck_comfortable_sneakers` | punkduck | shoes02 | CC BY |
| `punkduck_cycling_shoes` | punkduck | shoes02 | CC BY |
| `punkduck_female_short_jeans` | punkduck | pants03 | CC BY |
| `punkduck_female_tight_jeans` | punkduck | pants02 | CC BY |
| `punkduck_running_shoes_01` | punkduck | shoes02 | CC BY |
| `punkduck_winter_boots` | punkduck | shoes03 | CC BY |
| `scailman_semitransparent_water_boots` | scailman | shoes01 | CC0 |
| `toigo_ankle_boots_female` | MargaretToigo | shoes01 | CC0 |
| `toigo_ankle_boots_male` | MargaretToigo | shoes01 | CC0 |
| `toigo_basic_tucked_t-shirt` | MargaretToigo | shirts01 | CC0 |
| `toigo_fisherman_sweater` | MargaretToigo | shirts01 | CC0 |
| `toigo_gloves_short` | MargaretToigo | gloves01 | CC0 |
| `toigo_wool_pants` | MargaretToigo | pants01 | CC0 |

The garments `world_*` in the same folder (the bra, the áo dài, the
quần, the T-shirt, the pants and the jackets) are not from MakeHuman:
World sews them from the base mesh (`World.Sewing`), under the license
of World.

## BigMaQ

`priv/animals/meshes/primate.json` comes from the low-poly template mesh
of BigMaQ (`pose_reconstruction/data/Mesh/macaque_LOWPOLY.json` of
https://github.com/martinivis/BigMaQ, commit a92d2d0), under the MIT
license of that repository (below). The paper of BigMaQ says that the
template mesh came from the Max Planck Institute for Intelligent Systems
and M. J. Black. The repository gives no other license for the mesh. If
its owner asks, World removes it.

    MIT License

    Copyright (c) 2026 Lucas Martini

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
