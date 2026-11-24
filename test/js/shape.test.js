// The test of the check of the shape of the catalog (scripts/shape.mjs):
// the triangles of a GLB in the axes of its scene (the nodes, the
// instances, a skin, no collision box), the points on a surface and their
// distances to another surface, the rule of a level that is worse, and
// the check of the models that changed since a commit of git.
import assert from 'node:assert/strict';
import { spawnSync, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { distance, failures, grid, measure, p95, samples, triangles, worse } from '../../scripts/shape.mjs';

const script = new URL('../../scripts/shape.mjs', import.meta.url).pathname;

// A box from `lo` to `hi`: 8 points and 12 triangles.
function box(lo, hi) {
  const positions = [];
  for (const x of [lo[0], hi[0]]) for (const y of [lo[1], hi[1]]) for (const z of [lo[2], hi[2]]) positions.push(x, y, z);
  const faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]];
  return { positions, indices: faces.flatMap(([a, b, c, d]) => [a, b, c, a, c, d]) };
}

// A GLB of one mesh with its nodes; `more(add)` adds accessors for the nodes (instances, a skin).
function glb({ positions, indices }, nodes, more = () => ({})) {
  const parts = [];
  const views = [];
  const accessors = [];
  let length = 0;
  const add = (array, type, componentType, count) => {
    const bytes = new Uint8Array(array.buffer);
    views.push({ buffer: 0, byteOffset: length, byteLength: bytes.byteLength });
    parts.push(bytes);
    length += bytes.byteLength;
    const pad = (4 - (length % 4)) % 4;
    parts.push(new Uint8Array(pad));
    length += pad;
    accessors.push({ bufferView: views.length - 1, componentType, count, type });
    return accessors.length - 1;
  };
  const position = add(Float32Array.from(positions), 'VEC3', 5126, positions.length / 3);
  const index = add(Uint16Array.from(indices), 'SCALAR', 5123, indices.length);
  const extra = more(add);
  const json = {
    asset: { version: '2.0' },
    scene: 0,
    scenes: [{ nodes: [0] }],
    nodes,
    meshes: [{ primitives: [{ attributes: { POSITION: position, ...(extra.attributes ?? {}) }, indices: index }] }],
    accessors,
    bufferViews: views,
    buffers: [{ byteLength: length }],
    ...(extra.json ?? {}),
  };
  const text = new TextEncoder().encode(JSON.stringify(json));
  const jsonBytes = new Uint8Array(Math.ceil(text.length / 4) * 4).fill(0x20);
  jsonBytes.set(text);
  const bin = new Uint8Array(length);
  let at = 0;
  for (const p of parts) {
    bin.set(p, at);
    at += p.byteLength;
  }
  const out = new Uint8Array(12 + 8 + jsonBytes.length + 8 + bin.length);
  const view = new DataView(out.buffer);
  view.setUint32(0, 0x46546c67, true);
  view.setUint32(4, 2, true);
  view.setUint32(8, out.length, true);
  view.setUint32(12, jsonBytes.length, true);
  view.setUint32(16, 0x4e4f534a, true);
  out.set(jsonBytes, 20);
  view.setUint32(20 + jsonBytes.length, bin.length, true);
  view.setUint32(24 + jsonBytes.length, 0x004e4942, true);
  out.set(bin, 28 + jsonBytes.length);
  return out;
}

const bounds = (tris) => {
  const lo = [Infinity, Infinity, Infinity];
  const hi = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < tris.length; i += 3)
    for (let c = 0; c < 3; c += 1) {
      lo[c] = Math.min(lo[c], tris[i + c]);
      hi[c] = Math.max(hi[c], tris[i + c]);
    }
  return [lo, hi].map((v) => v.map((x) => Math.round(x * 1e6) / 1e6));
};

test('the triangles of a GLB: each node at its place, each instance, a skin at the places of its joints, no collision box', () => {
  const unit = box([0, 0, 0], [1, 1, 1]);
  // A node moved by 1 on x, with a child at twice the size (the mesh is on the child).
  const nested = glb(unit, [{ translation: [1, 0, 0], children: [1] }, { scale: [2, 2, 2], mesh: 0 }]);
  assert.equal(triangles(nested).length / 9, 12);
  assert.deepEqual(bounds(triangles(nested)), [[1, 0, 0], [3, 2, 2]]);

  // Two instances, at 0 and at 5 on y.
  const instanced = glb(unit, [{ mesh: 0, extensions: { EXT_mesh_gpu_instancing: { attributes: { TRANSLATION: 2 } } } }], (add) => {
    add(Float32Array.from([0, 0, 0, 0, 5, 0]), 'VEC3', 5126, 2);
    return {};
  });
  assert.equal(triangles(instanced).length / 9, 24);
  assert.deepEqual(bounds(triangles(instanced)), [[0, 0, 0], [1, 6, 1]]);

  // A skin of one joint moved by 3 on z: the points go with the joint, not with their node.
  const skinned = glb(
    unit,
    [{ children: [1, 2] }, { mesh: 0, skin: 0, translation: [100, 0, 0] }, { translation: [0, 0, 3] }],
    (add) => {
      const joints = add(new Uint8Array(32), 'VEC4', 5121, 8);
      const weights = add(Float32Array.from(Array.from({ length: 8 }, () => [1, 0, 0, 0]).flat()), 'VEC4', 5126, 8);
      const inverse = add(Float32Array.from([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]), 'MAT4', 5126, 1);
      return { attributes: { JOINTS_0: joints, WEIGHTS_0: weights }, json: { skins: [{ joints: [2], inverseBindMatrices: inverse }] } };
    },
  );
  assert.deepEqual(bounds(triangles(skinned)), [[0, 0, 3], [1, 1, 4]]);

  // A collision box is not a surface of the model.
  const collision = glb(unit, [{ children: [1] }, { name: 'wall-colonly', mesh: 0 }]);
  assert.equal(triangles(collision).length, 0);
});

test('points on a surface by area, the same at each run; the distance of a point to a surface', () => {
  const unit = box([0, 0, 0], [1, 1, 1]);
  const tris = triangles(glb(unit, [{ mesh: 0 }]));
  const points = samples(tris, 600);
  assert.equal(points.length, 1800);
  assert.deepEqual(samples(tris, 600), points);
  const g = grid(tris);
  // Each point is on the surface; the faces of the box have the same area, so about a sixth of the points is on each.
  assert.ok(p95(points, g) < 1e-9);
  const top = Array.from({ length: 600 }, (_, s) => points[3 * s + 2]).filter((z) => Math.abs(z - 1) < 1e-9).length;
  assert.ok(top > 70 && top < 130, `${top} points on the top`);
  // A point 2 m over the top, a point in the box, a point past a corner.
  assert.ok(Math.abs(distance(g, 0.5, 0.5, 3) - 2) < 1e-9);
  assert.ok(Math.abs(distance(g, 0.5, 0.5, 0.6) - 0.4) < 1e-9);
  assert.ok(Math.abs(distance(g, 2, 2, 2) - Math.sqrt(3)) < 1e-9);
  // (No triangle: no distance; no point: 0.)
  assert.equal(distance(grid(new Float64Array(0)), 0, 0, 0), Infinity);
  assert.equal(p95(new Float64Array(0), g), 0);
});

test('the measures of a model, and the rule of a level that is worse', () => {
  const near = glb(box([0, 0, 0], [1, 1, 1]), [{ mesh: 0 }]);
  // A far level that lost the top 0.3 m of the model, and a mid level with no file.
  const far = glb(box([0, 0, 0], [1, 1, 0.7]), [{ mesh: 0 }]);
  const m = measure((level) => ({ '': near, '.far': far })[level] ?? null, 4000);
  assert.equal(m.mid, undefined);
  assert.ok(m.far.to < 0.31 && m.far.from > 0.25, JSON.stringify(m));
  assert.equal(measure(() => null), null);

  assert.equal(worse(0.1, 0.13), true);
  assert.equal(worse(0.1, 0.115), false); // (15 %)
  assert.equal(worse(0.01, 0.025), false); // (1.5 cm)
  assert.equal(worse(0.01, 0.04), true);
  const before = { far: { to: 0.03, from: 0.05 } };
  assert.deepEqual(failures('house', before, { far: { to: 0.18, from: 0.05 } }), ['house.far to near: 3.0 cm to 18.0 cm']);
  assert.deepEqual(failures('house', before, before), []);
});

test('the check of the models that changed since a commit: worse, the same, a new model', () => {
  const repo = mkdtempSync(join(tmpdir(), 'shape-'));
  const git = (...args) => execFileSync('git', args, { cwd: repo, encoding: 'utf8' });
  const run = (...args) => spawnSync('node', [script, ...args, '--samples', '2000'], { cwd: repo, encoding: 'utf8' });
  mkdirSync(join(repo, 'models'));
  const write = (name, bytes) => writeFileSync(join(repo, 'models', name), bytes);
  const cube = glb(box([0, 0, 0], [1, 1, 1]), [{ mesh: 0 }]);
  for (const level of ['', '.mid', '.far']) write(`house${level}.glb`, cube);
  git('init', '-q');
  git('-c', 'user.name=t', '-c', 'user.email=t@t', 'add', '.');
  git('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'models');

  // The measures with no base.
  const plain = run('--dir', 'models');
  assert.equal(plain.status, 0, plain.stderr);
  assert.match(plain.stdout, /house: mid 0\.0 cm \/ 0\.0 cm, far 0\.0 cm \/ 0\.0 cm/);

  // The far level loses its top: worse.
  write('house.far.glb', glb(box([0, 0, 0], [1, 1, 0.6]), [{ mesh: 0 }]));
  const bad = run('--dir', 'models', '--base', 'HEAD');
  assert.equal(bad.status, 1);
  assert.match(bad.stdout, /1 models with a changed file, 1 levels worse/);
  assert.match(bad.stdout, /worse: house\.far from near: 0\.0 cm to/);

  // The same shape again, and a new model: nothing is worse.
  write('house.far.glb', cube);
  for (const level of ['', '.mid', '.far']) write(`shed${level}.glb`, cube);
  git('add', '.');
  const good = run('--dir', 'models', '--base', 'HEAD');
  assert.equal(good.status, 0, good.stdout);
  assert.match(good.stdout, /shed: new/);
});
