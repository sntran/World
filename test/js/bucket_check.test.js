// The script of the check of the bucket (scripts/bucket-check.mjs), with
// the routes /bucket/ of handler.js and a fake bucket.
import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { WINDOW, handler } from '../../handler.js';
import { BUILT, client, fetchAll, kindOf, named, summary } from '../../scripts/bucket-check.mjs';
import { bucket, vm } from './fakes.js';

const H = 'a'.repeat(32);
const K = 'b'.repeat(32);
const B = 'c'.repeat(32);
const C = 'd'.repeat(40);

test('the kind of each object of the bucket, and the objects that it names', () => {
  assert.equal(kindOf(`parts/${K}.glb`), 'part');
  assert.equal(kindOf(`parts/${K}.json`), 'recipe');
  assert.equal(kindOf(`builds/${C}/${H}.mid.elements`), 'file');
  assert.equal(kindOf(`builds/x/${H}.mid.elements`), 'other');
  assert.equal(kindOf(`orders/${H}.json`), 'order');
  assert.equal(kindOf(`urls/${C}/${'e'.repeat(64)}`), 'url');
  assert.equal(kindOf('shifts/state.json'), 'shift');
  assert.equal(kindOf('quarantine/x'), 'other');
  assert.deepEqual([...BUILT].sort(), ['file', 'part', 'recipe']);
  const bytes = (value) => new TextEncoder().encode(JSON.stringify(value));
  assert.deepEqual(named(`builds/${C}/${H}.near.glb`, null), [`orders/${H}.json`]);
  assert.deepEqual(named(`parts/${K}.glb`, null), [`parts/${K}.json`]);
  assert.deepEqual(named(`parts/${K}.json`, bytes({ order: H, level: 'near', node: 'x' })), [`orders/${H}.json`]);
  assert.deepEqual(named(`orders/${H}.json`, bytes({ blueprint: { hash: B } })), [`blueprints/${B}.json`]);
  assert.deepEqual(named(`orders/${H}.json`, bytes({ blueprint: 'box' })), []);
  assert.deepEqual(named(`parts/${K}.json`, new TextEncoder().encode('not JSON')), []);
  assert.deepEqual(named(`parts/${K}.json`, bytes({ order: '../x' })), []);
});

test('fetch: the objects of the window and each order, recipe and blueprint that they name, of any time', async () => {
  let now = WINDOW.from - 10;
  const orders = bucket({ clock: () => now });
  await orders.put(`orders/${H}.json`, JSON.stringify({ blueprint: { hash: B } }));
  await orders.put(`blueprints/${B}.json`, '{"name":"x"}');
  await orders.put(`parts/${K}.json`, JSON.stringify({ order: H, level: 'near', node: 'n' }));
  now = WINDOW.from + 10;
  await orders.put(`parts/${K}.glb`, 'glTF');
  await orders.put(`builds/${C}/${H}.near.elements`, '{}');
  await orders.put(`urls/${C}/${'e'.repeat(64)}`, `{"hash":"${H}"}`);
  await orders.put('shifts/state.json', '{}');
  // (A recipe of the window that names an order that the bucket does not have.)
  await orders.put(`parts/${'f'.repeat(32)}.json`, JSON.stringify({ order: 'f'.repeat(32) }));
  const claims = { repository: 'sntran/World', repository_owner_id: '973206', job_workflow_ref: 'sntran/World/.github/workflows/bucket-check.yml@refs/heads/main' };
  const env = { ORDERS: orders, WORLD_OWNER_ID: '973206' };
  const worker = (url, init) => handler(new Request(url, init), env, { vm: vm(), commit: 'c1', verify: async (t) => (t === 'a.b.c' ? claims : null) });
  const api = client('https://world.example', async () => 'a.b.c', worker);
  const dir = await mkdtemp(join(tmpdir(), 'bucket-'));
  const logs = [];
  const result = await fetchAll(api, dir, (line) => logs.push(line));
  assert.deepEqual(logs, ['bucket: 8 objects, 5 with an upload time in the window']);
  assert.deepEqual(result.kinds, { file: 1, part: 1, recipe: 1, shift: 1, url: 1 });
  assert.equal(await readFile(join(dir, 'bucket', `blueprints/${B}.json`), 'utf8'), '{"name":"x"}');
  assert.equal(await readFile(join(dir, 'bucket', `parts/${K}.glb`), 'utf8'), 'glTF');
  assert.match(await readFile(join(dir, 'bucket', `parts/${K}.json`), 'utf8'), /"node":"n"/);
  const list = JSON.parse(await readFile(join(dir, 'list.json'), 'utf8'));
  assert.deepEqual(list.map((o) => o.kind).sort(), ['file', 'part', 'recipe', 'shift', 'url']);
  const text = summary(result);
  assert.match(text, /The bucket has 8 objects; 5 have an upload time in the window/);
  assert.match(text, /\| part \| 1 \| build again \|/);
  assert.match(text, /\| url \| 1 \| request in the logs \|/);
  assert.match(text, new RegExp(`\\| ${C} \\| 2 \\|`));

  // The move of an object of the window, and of one of before.
  assert.equal((await api.quarantine('shifts/state.json')).status, 200);
  assert.equal((await api.quarantine(`orders/${H}.json`)).status, 409);
});

test('the client asks again after a 5xx, at most four times, and stops on another answer', async () => {
  let calls = 0;
  const flaky = async () => (++calls < 3 ? new Response('', { status: 503 }) : Response.json({ objects: [], seen: 0, cursor: null }));
  const waits = [];
  assert.deepEqual(await client('https://w', async () => 't', flaky, async (ms) => waits.push(ms)).list(), { objects: [], seen: 0 });
  assert.equal(calls, 3);
  assert.deepEqual(waits, [2000, 4000]);
  const refused = client('https://w', async () => 't', async () => new Response('no', { status: 403 }));
  await assert.rejects(refused.list(), /the list of the bucket: 403 no/);
  await assert.rejects(refused.get('orders/x.json'), /the object orders\/x.json: 403/);
});
