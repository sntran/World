// The check of the shape of the catalog: how far the mid and the far
// level of each model are from its near level.
//
//   node scripts/shape.mjs [NAME ...]               # the measures of the models (all by default)
//   node scripts/shape.mjs --base REV [NAME ...]    # each model whose files changed since REV, before and after
//
// For a level, two numbers: the 95th percentile of the distances from
// points on the level to the surface of the near level, and from points
// on the near level to the surface of the level (m). The points are
// spread over each surface by area, the same points at each run. A large
// first number is a part that the level has and the model has not (a
// spike, a dent); a large second number is a part of the model that the
// level lost (a chimney, a step).
//
// With --base, a level fails when one of its two numbers grows by more
// than 20 % and by more than 2 cm from the files at REV to the files of
// the work tree; the script then stops with an error. The near level is
// measured too: the near level of the work tree against the near level at
// REV, in both directions, with the same rule (from 0: it fails when one
// of the two numbers is more than 2 cm). The files at REV come from git
// (git show).
//
// Options: --dir (priv/models by default), --samples (the points on each
// surface, 20,000 by default).
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

// --- The triangles of a GLB, in the axes of its scene ----------------------

const SIZES = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };

// The JSON and the binary chunk of a GLB.
export function chunks(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(0, true) !== 0x46546c67) throw new Error('not a GLB');
  let at = 12;
  let json = null;
  let bin = null;
  while (at < bytes.byteLength) {
    const length = view.getUint32(at, true);
    const type = view.getUint32(at + 4, true);
    const data = bytes.subarray(at + 8, at + 8 + length);
    if (type === 0x4e4f534a) json = JSON.parse(new TextDecoder().decode(data));
    if (type === 0x004e4942) bin = data;
    at += 8 + length;
  }
  return { json, bin };
}

// The values of an accessor as numbers, each element an array.
function accessor(json, bin, index) {
  const a = json.accessors[index];
  const size = SIZES[a.type];
  const out = [];
  if (a.bufferView === undefined) {
    for (let i = 0; i < a.count; i += 1) out.push(new Array(size).fill(0));
    return out;
  }
  const view = json.bufferViews[a.bufferView];
  const data = new DataView(bin.buffer, bin.byteOffset + (view.byteOffset ?? 0) + (a.byteOffset ?? 0));
  const [bytes, read, max] = {
    5120: [1, (o) => data.getInt8(o), 127],
    5121: [1, (o) => data.getUint8(o), 255],
    5122: [2, (o) => data.getInt16(o, true), 32767],
    5123: [2, (o) => data.getUint16(o, true), 65535],
    5125: [4, (o) => data.getUint32(o, true), 0],
    5126: [4, (o) => data.getFloat32(o, true), 0],
  }[a.componentType];
  const stride = view.byteStride ?? bytes * size;
  for (let i = 0; i < a.count; i += 1) {
    const element = [];
    for (let c = 0; c < size; c += 1) {
      const v = read(i * stride + c * bytes);
      element.push(a.normalized && max ? Math.max(v / max, -1) : v);
    }
    out.push(element);
  }
  return out;
}

// 4 × 4 matrices by columns, as glTF has them.
const IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

function multiply(a, b) {
  const m = new Array(16).fill(0);
  for (let c = 0; c < 4; c += 1)
    for (let r = 0; r < 4; r += 1) for (let k = 0; k < 4; k += 1) m[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return m;
}

function trs(t = [0, 0, 0], q = [0, 0, 0, 1], s = [1, 1, 1]) {
  const [x, y, z, w] = q;
  return [
    (1 - 2 * (y * y + z * z)) * s[0], 2 * (x * y + z * w) * s[0], 2 * (x * z - y * w) * s[0], 0,
    2 * (x * y - z * w) * s[1], (1 - 2 * (x * x + z * z)) * s[1], 2 * (y * z + x * w) * s[1], 0,
    2 * (x * z + y * w) * s[2], 2 * (y * z - x * w) * s[2], (1 - 2 * (x * x + y * y)) * s[2], 0,
    t[0], t[1], t[2], 1,
  ];
}

function apply(m, [x, y, z]) {
  return [
    m[0] * x + m[4] * y + m[8] * z + m[12],
    m[1] * x + m[5] * y + m[9] * z + m[13],
    m[2] * x + m[6] * y + m[10] * z + m[14],
  ];
}

// The triangles of the scene of a GLB at rest, in the axes of the scene:
// each node at its place, each instance of a node, and a skin at the
// places of its joints. A node of a collision box (NAME-colonly) is not a
// surface of the model. Gives a Float64Array, nine numbers for each triangle.
export function triangles(bytes) {
  const { json, bin } = chunks(bytes);
  const nodes = json.nodes ?? [];
  const world = new Array(nodes.length);
  const walk = (i, parent) => {
    const n = nodes[i];
    world[i] = multiply(parent, n.matrix ?? trs(n.translation, n.rotation, n.scale));
    for (const c of n.children ?? []) walk(c, world[i]);
  };
  const scene = json.scenes?.[json.scene ?? 0];
  for (const root of scene?.nodes ?? nodes.map((_, i) => i)) walk(root, IDENTITY);

  const out = [];
  nodes.forEach((n, i) => {
    if (n.mesh === undefined || world[i] === undefined || (n.name ?? '').endsWith('-colonly')) return;
    const instancing = n.extensions?.EXT_mesh_gpu_instancing?.attributes;
    let places = [world[i]];
    if (instancing) {
      const count = json.accessors[Object.values(instancing)[0]].count;
      const t = instancing.TRANSLATION !== undefined ? accessor(json, bin, instancing.TRANSLATION) : [];
      const r = instancing.ROTATION !== undefined ? accessor(json, bin, instancing.ROTATION) : [];
      const s = instancing.SCALE !== undefined ? accessor(json, bin, instancing.SCALE) : [];
      places = Array.from({ length: count }, (_, k) => multiply(world[i], trs(t[k], r[k], s[k])));
    }
    const skin = n.skin !== undefined ? json.skins[n.skin] : null;
    const joints = skin
      ? (() => {
          const inverse = skin.inverseBindMatrices !== undefined ? accessor(json, bin, skin.inverseBindMatrices) : [];
          return skin.joints.map((j, k) => multiply(world[j], inverse[k] ?? IDENTITY));
        })()
      : null;

    for (const p of json.meshes[n.mesh].primitives) {
      if ((p.mode ?? 4) !== 4) continue;
      let points = accessor(json, bin, p.attributes.POSITION);
      if (joints && p.attributes.JOINTS_0 !== undefined) {
        const js = accessor(json, bin, p.attributes.JOINTS_0);
        const ws = accessor(json, bin, p.attributes.WEIGHTS_0);
        points = points.map((v, k) => {
          const sum = [0, 0, 0];
          ws[k].forEach((w, c) => {
            if (w === 0) return;
            const q = apply(joints[js[k][c]], v);
            for (let a = 0; a < 3; a += 1) sum[a] += w * q[a];
          });
          return sum;
        });
        places = [IDENTITY];
      }
      const index = p.indices !== undefined ? accessor(json, bin, p.indices).map((e) => e[0]) : points.map((_, k) => k);
      for (const m of places) {
        const at = points.map((v) => apply(m, v));
        for (let k = 0; k + 2 < index.length; k += 3) for (const c of [0, 1, 2]) out.push(...at[index[k + c]]);
      }
    }
  });
  return Float64Array.from(out);
}

// --- Points on a surface, and the distance of a point to a surface ----------

// A random number from 0 to 1 that is the same at each run (mulberry32).
function random(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// `count` points on the triangles, each triangle by its area.
export function samples(tris, count, seed = 1) {
  const n = tris.length / 9;
  const sums = new Float64Array(n);
  let total = 0;
  for (let i = 0; i < n; i += 1) {
    const t = tris.subarray(9 * i, 9 * i + 9);
    const [ux, uy, uz] = [t[3] - t[0], t[4] - t[1], t[5] - t[2]];
    const [vx, vy, vz] = [t[6] - t[0], t[7] - t[1], t[8] - t[2]];
    total += Math.hypot(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx) / 2;
    sums[i] = total;
  }
  const next = random(seed);
  const out = new Float64Array(3 * count);
  if (n === 0 || total === 0) return new Float64Array(0);
  for (let s = 0; s < count; s += 1) {
    const target = ((s + next()) / count) * total;
    let lo = 0;
    let hi = n - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (sums[mid] < target) lo = mid + 1;
      else hi = mid;
    }
    let [a, b] = [next(), next()];
    if (a + b > 1) [a, b] = [1 - a, 1 - b];
    const t = tris.subarray(9 * lo, 9 * lo + 9);
    for (let c = 0; c < 3; c += 1) out[3 * s + c] = t[c] + a * (t[3 + c] - t[c]) + b * (t[6 + c] - t[c]);
  }
  return out;
}

// The square of the distance of a point to a triangle (Ericson, Real-Time
// Collision Detection, 5.1.5).
function squared(px, py, pz, t, o) {
  const [ax, ay, az, bx, by, bz, cx, cy, cz] = [t[o], t[o + 1], t[o + 2], t[o + 3], t[o + 4], t[o + 5], t[o + 6], t[o + 7], t[o + 8]];
  const [abx, aby, abz, acx, acy, acz] = [bx - ax, by - ay, bz - az, cx - ax, cy - ay, cz - az];
  const [apx, apy, apz] = [px - ax, py - ay, pz - az];
  const d1 = abx * apx + aby * apy + abz * apz;
  const d2 = acx * apx + acy * apy + acz * apz;
  const near = (x, y, z) => (px - x) ** 2 + (py - y) ** 2 + (pz - z) ** 2;
  if (d1 <= 0 && d2 <= 0) return near(ax, ay, az);
  const [bpx, bpy, bpz] = [px - bx, py - by, pz - bz];
  const d3 = abx * bpx + aby * bpy + abz * bpz;
  const d4 = acx * bpx + acy * bpy + acz * bpz;
  if (d3 >= 0 && d4 <= d3) return near(bx, by, bz);
  const vc = d1 * d4 - d3 * d2;
  if (vc <= 0 && d1 >= 0 && d3 <= 0) {
    const v = d1 / (d1 - d3);
    return near(ax + v * abx, ay + v * aby, az + v * abz);
  }
  const [cpx, cpy, cpz] = [px - cx, py - cy, pz - cz];
  const d5 = abx * cpx + aby * cpy + abz * cpz;
  const d6 = acx * cpx + acy * cpy + acz * cpz;
  if (d6 >= 0 && d5 <= d6) return near(cx, cy, cz);
  const vb = d5 * d2 - d1 * d6;
  if (vb <= 0 && d2 >= 0 && d6 <= 0) {
    const w = d2 / (d2 - d6);
    return near(ax + w * acx, ay + w * acy, az + w * acz);
  }
  const va = d3 * d6 - d5 * d4;
  if (va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0) {
    const w = (d4 - d3) / (d4 - d3 + (d5 - d6));
    return near(bx + w * (cx - bx), by + w * (cy - by), bz + w * (cz - bz));
  }
  const denom = 1 / (va + vb + vc);
  const [v, w] = [vb * denom, vc * denom];
  return near(ax + abx * v + acx * w, ay + aby * v + acy * w, az + abz * v + acz * w);
}

// A grid of the triangles of a surface, for the nearest triangle of a
// point. A triangle with no area is not in it (a side of another triangle
// is at its place). The cells are two arrays: the first triangle of each
// cell, and the triangles of the cells one after another.
export function grid(tris) {
  const all = tris.length / 9;
  const kept = [];
  for (let t = 0; t < all; t += 1) {
    const o = 9 * t;
    const [ux, uy, uz] = [tris[o + 3] - tris[o], tris[o + 4] - tris[o + 1], tris[o + 5] - tris[o + 2]];
    const [vx, vy, vz] = [tris[o + 6] - tris[o], tris[o + 7] - tris[o + 1], tris[o + 8] - tris[o + 2]];
    if (Math.hypot(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx) > 1e-12) kept.push(t);
  }
  const lo = [Infinity, Infinity, Infinity];
  const hi = [-Infinity, -Infinity, -Infinity];
  for (const t of kept)
    for (let v = 0; v < 3; v += 1)
      for (let c = 0; c < 3; c += 1) {
        lo[c] = Math.min(lo[c], tris[9 * t + 3 * v + c]);
        hi[c] = Math.max(hi[c], tris[9 * t + 3 * v + c]);
      }
  const diagonal = Math.hypot(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]) || 1;
  // (About two cells along the side of a cube of the triangles, and 4,000,000 cells at the most.)
  let cell = diagonal / Math.max(8, 2 * Math.cbrt(kept.length));
  const count = (s) => lo.reduce((n, l, c) => n * Math.max(1, Math.ceil((hi[c] - l) / s)), 1);
  while (count(cell) > 4e6) cell *= 1.25;
  const dims = lo.map((l, c) => Math.max(1, Math.ceil((hi[c] - l) / cell)));
  const range = (t, c) => {
    const vs = [tris[9 * t + c], tris[9 * t + 3 + c], tris[9 * t + 6 + c]];
    return [0, 1].map((e) => Math.min(dims[c] - 1, Math.max(0, Math.floor(((e ? Math.max : Math.min)(...vs) - lo[c]) / cell))));
  };
  const each = (t, f) => {
    const [[i0, i1], [j0, j1], [k0, k1]] = [range(t, 0), range(t, 1), range(t, 2)];
    for (let i = i0; i <= i1; i += 1)
      for (let j = j0; j <= j1; j += 1) for (let k = k0; k <= k1; k += 1) f((i * dims[1] + j) * dims[2] + k);
  };
  const starts = new Int32Array(dims[0] * dims[1] * dims[2] + 1);
  for (const t of kept) each(t, (key) => (starts[key + 1] += 1));
  for (let k = 1; k < starts.length; k += 1) starts[k] += starts[k - 1];
  const fill = starts.slice(0, -1);
  const items = new Int32Array(starts[starts.length - 1]);
  for (const t of kept) each(t, (key) => (items[fill[key]++] = t));
  return { tris, lo, cell, dims, starts, items, seen: new Int32Array(all).fill(-1), stamp: 0 };
}

// The distance of a point to the surface of a grid: the cells round the
// point, ring by ring (the shell of a cube of cells), to the ring past the
// nearest triangle.
export function distance(g, px, py, pz) {
  const { tris, lo, cell, dims, starts, items } = g;
  if (items.length === 0) return Infinity;
  const at = [px, py, pz].map((v, c) => Math.floor((v - lo[c]) / cell));
  const last = Math.max(...at.map((a, c) => Math.max(Math.abs(a), Math.abs(a - (dims[c] - 1)))));
  g.stamp += 1;
  let best = Infinity;
  const visit = (i, j, k) => {
    if (i < 0 || j < 0 || k < 0 || i >= dims[0] || j >= dims[1] || k >= dims[2]) return;
    const key = (i * dims[1] + j) * dims[2] + k;
    for (let s = starts[key]; s < starts[key + 1]; s += 1) {
      const t = items[s];
      if (g.seen[t] === g.stamp) continue;
      g.seen[t] = g.stamp;
      const d = squared(px, py, pz, tris, 9 * t);
      if (d < best) best = d;
    }
  };
  for (let r = 0; r <= last; r += 1) {
    for (let i = at[0] - r; i <= at[0] + r; i += 1)
      for (let j = at[1] - r; j <= at[1] + r; j += 1) {
        if (Math.abs(i - at[0]) === r || Math.abs(j - at[1]) === r) {
          for (let k = at[2] - r; k <= at[2] + r; k += 1) visit(i, j, k);
        } else {
          visit(i, j, at[2] - r);
          if (r > 0) visit(i, j, at[2] + r);
        }
      }
    // (A triangle in a ring past this one is at least r cells from the point.)
    if (best <= (r * cell) ** 2) break;
  }
  return Math.sqrt(best);
}

// The 95th percentile of the distances from the points to the surface of a grid.
export function p95(points, g) {
  const n = points.length / 3;
  if (n === 0) return 0;
  const d = new Float64Array(n);
  for (let s = 0; s < n; s += 1) d[s] = distance(g, points[3 * s], points[3 * s + 1], points[3 * s + 2]);
  d.sort();
  return d[Math.max(0, Math.ceil(0.95 * n) - 1)];
}

// --- The measures of a model, and the check ---------------------------------

export const LEVELS = ['mid', 'far'];

// The measures of a model: for its mid and its far level, `to` (from the
// level to the near level) and `from` (from the near level to the level).
// `read` gives the bytes of a level ('' for near), or null.
export function measure(read, count = 20000) {
  const near = read('');
  if (!near) return null;
  const nearTris = triangles(near);
  const nearGrid = grid(nearTris);
  const nearPoints = samples(nearTris, count);
  const out = {};
  for (const level of LEVELS) {
    const bytes = read(`.${level}`);
    if (!bytes) continue;
    const tris = triangles(bytes);
    out[level] = { to: p95(samples(tris, count), nearGrid), from: p95(nearPoints, grid(tris)) };
  }
  return out;
}

// A level fails when one of its numbers grows by more than 20 % and by
// more than 2 cm.
export function worse(before, after) {
  return after > before * 1.2 && after - before > 0.02;
}

// The levels of a model that fail, from its measures before and after.
// The near level of the work tree against the near level at the base
// (the GLB files): `{to, from}`, or null when one of the two is not there.
export function nearer(before, after, count = 20000) {
  if (!before || !after) return null;
  const [a, b] = [triangles(before), triangles(after)];
  return { to: p95(samples(b, count), grid(a)), from: p95(samples(a, count), grid(b)) };
}

export function failures(name, before, after, near = null) {
  const out = [];
  for (const way of ['to', 'from'])
    if (near && worse(0, near[way])) out.push(`${name}.near ${way === 'to' ? 'to the base' : 'from the base'}: ${cm(near[way])}`);
  for (const level of LEVELS)
    for (const way of ['to', 'from']) {
      const [b, a] = [before?.[level]?.[way], after?.[level]?.[way]];
      if (b !== undefined && a !== undefined && worse(b, a)) out.push(`${name}.${level} ${way === 'to' ? 'to near' : 'from near'}: ${cm(b)} to ${cm(a)}`);
    }
  return out;
}

const cm = (m) => `${(100 * m).toFixed(1)} cm`;

// The names of the models of a directory (NAME of NAME.glb).
function models(dir) {
  return readdirSync(dir)
    .filter((f) => f.endsWith('.glb') && !f.endsWith('.mid.glb') && !f.endsWith('.far.glb'))
    .map((f) => f.slice(0, -4))
    .sort();
}

function main(args) {
  const opts = { dir: 'priv/models', samples: 20000, base: null, names: [] };
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === '--base') opts.base = args[++i];
    else if (args[i] === '--dir') opts.dir = args[++i];
    else if (args[i] === '--samples') opts.samples = Number(args[++i]);
    else opts.names.push(args[i]);
  }
  const file = (name, level) => join(opts.dir, `${name}${level}.glb`);
  const disk = (name) => (level) => (existsSync(file(name, level)) ? new Uint8Array(readFileSync(file(name, level))) : null);
  const git = (name) => (level) => {
    try {
      return new Uint8Array(execFileSync('git', ['show', `${opts.base}:${file(name, level)}`], { maxBuffer: 1 << 30 }));
    } catch {
      return null;
    }
  };

  if (!opts.base) {
    for (const name of opts.names.length ? opts.names : models(opts.dir)) {
      const m = measure(disk(name), opts.samples);
      const row = LEVELS.filter((l) => m?.[l]).map((l) => `${l} ${cm(m[l].to)} / ${cm(m[l].from)}`);
      console.log(`${name}: ${row.join(', ')}`);
    }
    return 0;
  }

  // The models with a file that changed since the base.
  const changed = execFileSync('git', ['diff', '--name-only', opts.base, '--', opts.dir], { encoding: 'utf8' })
    .split('\n')
    .filter((f) => f.endsWith('.glb'))
    .map((f) => f.slice(opts.dir.length + 1).replace(/(\.mid|\.far)?\.glb$/, ''));
  const names = opts.names.length ? opts.names : [...new Set(changed)].sort();
  const bad = [];
  for (const name of names) {
    const [before, after] = [measure(git(name), opts.samples), measure(disk(name), opts.samples)];
    const near = nearer(git(name)(''), disk(name)(''), opts.samples);
    const row = LEVELS.filter((l) => before?.[l] && after?.[l]).map(
      (l) => `${l} ${cm(before[l].to)} / ${cm(before[l].from)} to ${cm(after[l].to)} / ${cm(after[l].from)}`,
    );
    if (near) row.unshift(`near ${cm(near.to)} / ${cm(near.from)}`);
    console.log(`${name}: ${before && after ? row.join(', ') : before ? 'gone' : 'new'}`);
    bad.push(...failures(name, before, after, near));
  }
  const levels = new Set(bad.map((b) => b.split(' ')[0]));
  console.log(`${names.length} models with a changed file, ${levels.size} levels worse`);
  for (const b of bad) console.log(`  worse: ${b}`);
  return bad.length > 0 ? 1 : 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main(process.argv.slice(2)));
