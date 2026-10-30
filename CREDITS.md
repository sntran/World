# Credits

The assets from outside, each with its license. The code and the models
of World are under the AGPL-3.0 (`LICENSE`).

| Folder | What | Source | License |
|---|---|---|---|
| `wings/` | The mesh core of Wings 3D | [dgud/wings](https://github.com/dgud/wings) | The terms of Wings 3D (`wings/LICENSE`) |
| `priv/makehuman/` | The base mesh, the targets, the skeleton, the skins, the hair and the clothes of people | [MakeHuman](http://www.makehumancommunity.org/) (`priv/makehuman/README.md`) | CC0 |
| `priv/animals/meshes/shiba_inu.json`, `wolf.json`, `fox.json`, `deer.json`, `horse.json`, `donkey.json`, `cow.json`, `bull.json`, `alpaca.json`, `husky.json`, `stag.json` | The base meshes, the bones, the weights and the colors of the materials of the templates of the four-legged animals (from the glTF files, by `scripts/gltf_figure.exs`) | Quaternius, [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html), the glTF files from [PixelTriks](https://pixeltriks.com/browse?pack=quaternius-ultimate-animated-animals) | CC0 |
| `priv/animals/meshes/pig.json`, `sheep.json` | The base meshes, the bones, the weights and the colors of the materials of the templates pig and sheep (from the FBX files, by `scripts/fbx_gltf.exs` and `scripts/gltf_figure.exs`) | Quaternius, [Farm Animals Pack](https://opengameart.org/content/lowpoly-animated-farm-animal-pack) | CC0 |
| `priv/animals/clips/*.json` (not `primate.json`) | The clips of the templates of the four-legged animals (from the animations Walk, Gallop, Idle, Eating, Idle_HeadLow, Attack, Attack_Kick, Gallop_Jump, Jump_ToIdle, Idle_HitReact1, Idle_HitReact2 and Death of the same glTF files, by `scripts/gltf_clips.exs`) | Quaternius, [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html), the glTF files from [PixelTriks](https://pixeltriks.com/browse?pack=quaternius-ultimate-animated-animals) | CC0 |
| `priv/animals/clips/primate.json` | The walk, the run and the sit of the template of primates (by `scripts/bigmaq_clips.exs`: on the bones of World, the loops closed, the fingers and the toes level) | BigMaQ (L. Martini and others), [pose reconstructions](https://zenodo.org/records/20663410): action 458, individual G (walk); action 203, individual L (run); action 415, individual G (sit) | CC BY 4.0 |
| `priv/animals/spaces/wolf.json` | The shape space of the template wolf: the shape changes of the eleven templates of the four-legged animals on the Ultimate rig that the numbers do not give, and their principal components (by `scripts/shape_space.exs`) | Quaternius, [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html), the glTF files from [PixelTriks](https://pixeltriks.com/browse?pack=quaternius-ultimate-animated-animals) | CC0 |
| `priv/animals/meshes/primate.json`, `priv/animals/meshes/primate_upright.json` | The base mesh, the bones and the weights of the templates of primates (`primate_upright`: the arms up at rest, no tail): the low-poly template mesh of a rhesus macaque, its 115 bones and its weights (by `scripts/primate_template.exs`, in the pose at rest of the body plan; the eyes are of World) | [BigMaQ](https://github.com/martinivis/BigMaQ) (L. Martini and others, "BigMaQ: A Big Macaque Motion and Animation Dataset Bridging Image and 3D Pose Representations", ICLR 2026); the template mesh came from the Max Planck Institute for Intelligent Systems and M. J. Black (see below) | MIT |

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
