// The script of the check of the bucket (scripts/bucket-check.mjs), with
// the routes /bucket/ of handler.js and a fake bucket.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { WINDOW, handler } from '../../handler.js';
import { BUILT, NEAR, bare, client, compare, deployed, fetchAll, keyless, kindOf, merge, named, plan, siteLists, summary, tasks, verdicts } from '../../scripts/bucket-check.mjs';
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

test('the commits that the site ran in the window: the commit of main at its start, and each commit after it to its end', () => {
  const at = (ms) => new Date(ms).toISOString();
  const log = [
    `e5 ${at(WINDOW.to + 1)}`,
    `e4 ${at(WINDOW.to)}`,
    `e3 ${at(WINDOW.from + 1)}`,
    `e2 ${at(WINDOW.from - 10)}`,
    `e1 ${at(WINDOW.from - 20)}`,
  ].join('\n');
  assert.deepEqual(deployed(() => log).map((c) => c.commit), ['e2', 'e3', 'e4']);
  // (No commit before the window: each commit to its end.)
  assert.deepEqual(deployed(() => `e3 ${at(WINDOW.from + 1)}\n`).map((c) => c.commit), ['e3']);
});

test('a log of a construction with no times, process ids or measures of the run', () => {
  const log = (at, who, ms) => new TextEncoder().encode([
    `{"scale":86400,"start":${at}}`,
    `{"at":${at},"data":{"trade":"sculptor"},"kind":"hired","order":"o","wall":${at},"who":"${who}"}`,
    `{"at":${at + 1},"data":{"ms":${ms}},"kind":"run_done","order":"o","wall":${at},"who":null}`,
    '',
  ].join('\n'));
  assert.equal(bare(log(1, '<0.1.0>', 5)), bare(log(9, '<0.7.0>', 50)));
  assert.notEqual(bare(log(1, '<0.1.0>', 5)), bare(new TextEncoder().encode('{}\n{"kind":"hired","data":{"trade":"mason"}}\n')));
});

test('the plan, the tasks of each group and the compare: a part that agrees, a part that differs, a file of a Preview, and an order', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'rebuild-'));
  const C1 = '1'.repeat(40);
  const C2 = '2'.repeat(40);
  const P = 'f'.repeat(40);
  const [A, Z, R] = ['a'.repeat(32), 'e'.repeat(32), '9'.repeat(32)];
  const put = async (key, value) => {
    await mkdir(join(dir, 'bucket', key, '..'), { recursive: true });
    await writeFile(join(dir, 'bucket', key), value);
  };
  await put(`orders/${H}.json`, '{"blueprint":"box"}');
  await put(`blueprints/${B}.json`, '{"name":"b"}');
  await put(`parts/${A}.glb`, 'glTF A');
  await put(`parts/${Z}.glb`, 'glTF Z');
  await put(`parts/${R}.json`, JSON.stringify({ order: H, level: 'near', node: 'n' }));
  // (A recipe of before the window: in the store of the rebuild.)
  await put(`parts/${A}.json`, JSON.stringify({ order: H, level: 'mid', node: 'm' }));
  await put(`builds/${C2}/${H}.far.elements`, '{"parts":[]}');
  await put(`builds/${C1}/${H}.far.glb`, 'glTF far');
  await put(`builds/${P}/${H}.far.glb`, 'glTF of a Preview');
  await put(`urls/${C1}/${'b'.repeat(64)}`, '{}');
  const keys = [`orders/${H}.json`, `blueprints/${B}.json`, `parts/${A}.glb`, `parts/${Z}.glb`, `parts/${R}.json`, `builds/${C2}/${H}.far.elements`, `builds/${C1}/${H}.far.glb`, `builds/${P}/${H}.far.glb`, `urls/${C1}/${'b'.repeat(64)}`];
  await writeFile(join(dir, 'list.json'), JSON.stringify(keys.map((key) => ({ key, size: 1, uploaded: new Date(WINDOW.from).toISOString(), etag: 'e', kind: kindOf(key) }))));
  // (Two commits of main with the same code, a third with other code; P is not on main.)
  const git = (args) => {
    if (args[0] === 'log') return `${C2} ${new Date(WINDOW.from + 5).toISOString()}\n${'3'.repeat(40)} ${new Date(WINDOW.from + 2).toISOString()}\n${C1} ${new Date(WINDOW.from - 5).toISOString()}\n`;
    if (args[0] === 'rev-parse') return args[1].startsWith(C2) ? 'other code\n' : 'code\n';
    if (args[0] === 'merge-base' && args[2] === P) throw new Error('not on main');
    return '';
  };
  const work = await plan(dir, git);
  // (Group 1: C1 and the commit 3 with the same code; group 2: C2.)
  assert.deepEqual(work.groups.map((g) => [g.id, g.commits.length, g.files.map((f) => f.file)]), [['1', 2, ['glb']], ['2', 1, ['elements']]]);
  // The parts and the recipes of the window go to the group of their time: C1 ran then.
  const [one, two] = work.groups;
  assert.deepEqual([one.parts, one.recipes, two.parts], [[A, Z], [`parts/${R}.json`], []]);
  // The list of the recipe; for Z (no recipe), the list of each file of the group (far), then the orders of the time of the group at each level.
  assert.deepEqual(one.lists, [{ hash: H, level: 'near' }, { hash: H, level: 'far' }, { hash: H, level: 'mid' }]);
  assert.deepEqual(two.lists, []);
  assert.deepEqual(work.hashes, [`orders/${H}.json`, `blueprints/${B}.json`]);
  assert.deepEqual(work.preview, [`builds/${P}/${H}.far.glb`]);
  assert.equal(await readFile(join(dir, 'store', `parts/${A}.json`), 'utf8'), JSON.stringify({ order: H, level: 'mid', node: 'm' }));
  // (And each recipe of the window: the rebuild builds each part from the recipe of the site.)
  assert.equal(await readFile(join(dir, 'store', `parts/${R}.json`), 'utf8'), JSON.stringify({ order: H, level: 'near', node: 'n' }));
  assert.deepEqual(await tasks(dir, '1'), { files: one.files, lists: one.lists, parts: [A, Z], maps: [], hashes: work.hashes });

  // Group 1 builds A again with the same bytes, Z with other bytes, the file of C1, and no recipe R.
  const out = async (id, key, value) => {
    await mkdir(join(dir, 'out', id, key, '..'), { recursive: true });
    await writeFile(join(dir, 'out', id, key), value);
  };
  await out('1', `parts/${A}.glb`, 'glTF A');
  await out('1', `parts/${Z}.glb`, 'glTF other');
  await out('1', `builds/${C1}/${H}.far.glb`, 'glTF far');
  await out('1', 'hashes.json', JSON.stringify({ [`orders/${H}.json`]: true, [`blueprints/${B}.json`]: false }));
  await out('2', `builds/${C2}/${H}.far.elements`, '{"parts":[]}');
  // (A file of C2 that group 1 built is not a file of group 1.)
  await out('1', `builds/${C2}/${H}.far.elements`, 'other');
  await out('2', 'hashes.json', JSON.stringify({ [`orders/${H}.json`]: false }));

  const report = await compare(dir);
  const of = (key) => report.find((o) => o.key === key);
  assert.equal(of(`parts/${A}.glb`).verdict, 'agrees');
  assert.equal(of(`parts/${Z}.glb`).verdict, 'differs');
  assert.equal(of(`parts/${R}.json`).verdict, 'none');
  assert.equal(of(`builds/${C1}/${H}.far.glb`).verdict, 'agrees');
  assert.equal(of(`builds/${C2}/${H}.far.elements`).verdict, 'agrees');
  assert.deepEqual([of(`builds/${P}/${H}.far.glb`).verdict, of(`builds/${P}/${H}.far.glb`).note], ['none', 'a commit that is not on main']);
  assert.deepEqual([of(`orders/${H}.json`).verdict, of(`orders/${H}.json`).note], ['request', 'its content gives its hash']);
  assert.equal(of(`blueprints/${B}.json`).note, 'its content does not give its hash');
  assert.equal(of(`urls/${C1}/${'b'.repeat(64)}`).verdict, 'request');
  const text = verdicts(report);
  assert.match(text, /\| part \| 2 \| 1 \| 1 \| 0 \| 0 \|/);
  assert.match(text, /\| file \| 3 \| 2 \| 0 \| 1 \| 0 \|/);
  assert.match(text, new RegExp(`- \`parts/${Z}.glb\` \\(.*\\): differs`));
  assert.match(text, /a commit that is not on main/);
  assert.doesNotMatch(text, new RegExp(`parts/${A}.glb`));
  assert.match(verdicts(report.filter((o) => o.verdict === 'agrees')), /Each object that World builds agrees/);

  // The report of each group alone, then the reports joined: the best verdict of a group for each object.
  const [first, second] = [await compare(dir, ['1']), await compare(dir, ['2'])];
  assert.equal(second.find((o) => o.key === `parts/${A}.glb`).verdict, 'none');
  assert.equal(first.find((o) => o.key === `builds/${C2}/${H}.far.elements`).verdict, 'none');
  assert.equal(second.find((o) => o.key === `orders/${H}.json`).note, 'its content does not give its hash');
  const joined = merge([second, first]);
  assert.deepEqual(joined.map((o) => [o.key, o.verdict, o.note]), report.map((o) => [o.key, o.verdict, o.note]).sort((a, b) => (a[0] < b[0] ? -1 : 1)));
});

test('the group of a part near a deploy: the commit of its time, and the commit before it', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'near-'));
  const [K1, K2] = ['1'.repeat(32), '2'.repeat(32)];
  const t0 = WINDOW.from + 3600_000;
  for (const k of [K1, K2]) {
    await mkdir(join(dir, 'bucket', 'parts'), { recursive: true });
    await writeFile(join(dir, 'bucket', `parts/${k}.glb`), 'g');
  }
  const list = [{ key: `parts/${K1}.glb`, uploaded: new Date(t0 + NEAR - 1).toISOString() }, { key: `parts/${K2}.glb`, uploaded: new Date(t0 + NEAR).toISOString() }];
  await writeFile(join(dir, 'list.json'), JSON.stringify(list.map((o) => ({ ...o, size: 1, etag: 'e', kind: 'part' }))));
  const git = (args) => (args[0] === 'log' ? `${'b'.repeat(40)} ${new Date(t0).toISOString()}\n${'a'.repeat(40)} ${new Date(WINDOW.from - 1).toISOString()}\n` : args[0] === 'rev-parse' ? `${args[1].slice(0, 1)}\n` : '');
  const work = await plan(dir, git);
  assert.deepEqual(work.groups.map((g) => g.parts), [[K1], [K1, K2]]);
});

test('the command line: fetch and quarantine with the ID token of the job, against a Worker on this computer', async () => {
  const orders = bucket({ clock: () => WINDOW.from + 1 });
  await orders.put(`parts/${K}.glb`, 'glTF');
  const claims = { repository: 'sntran/World', repository_owner_id: '973206', job_workflow_ref: 'sntran/World/.github/workflows/bucket-check.yml@refs/heads/main' };
  const env = { ORDERS: orders, WORLD_OWNER_ID: '973206' };
  const tokens = [];
  const server = createServer(async (req, res) => {
    const url = `http://${req.headers.host}${req.url}`;
    if (req.url.startsWith('/token')) {
      tokens.push(req.headers.authorization);
      return res.end(JSON.stringify({ value: 'a.b.c' }));
    }
    const r = await handler(new Request(url, { method: req.method, headers: req.headers }), env, { vm: vm(), commit: 'c1', verify: async (t) => (t === 'a.b.c' ? claims : null) });
    res.writeHead(r.status, Object.fromEntries(r.headers));
    res.end(Buffer.from(await r.arrayBuffer()));
  });
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  const base = `http://127.0.0.1:${server.address().port}`;
  const dir = await mkdtemp(join(tmpdir(), 'cli-'));
  const run = (...args) => new Promise((done) => {
    // (A folder with no git: the fetch goes on with no commits of main.)
    const child = spawn('node', [join(process.cwd(), 'scripts/bucket-check.mjs'), ...args], { cwd: dir, env: { ...process.env, WORLD_URL: base, ACTIONS_ID_TOKEN_REQUEST_URL: `${base}/token?x=1`, ACTIONS_ID_TOKEN_REQUEST_TOKEN: 'req', GITHUB_STEP_SUMMARY: join(dir, 'summary.md') } });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.on('close', (code) => done({ code, out }));
  });
  try {
    const fetched = await run('fetch', join(dir, 'b'));
    assert.equal(fetched.code, 0);
    assert.match(fetched.out, /The bucket has 1 objects; 1 have an upload time in the window/);
    assert.match(fetched.out, /no commits of main in git, so no parts lists of the site/);
    assert.equal(await readFile(join(dir, 'b', 'bucket', `parts/${K}.glb`), 'utf8'), 'glTF');
    assert.match(await readFile(join(dir, 'summary.md'), 'utf8'), /\| part \| 1 \| build again \|/);
    assert.deepEqual([...new Set(tokens)], ['bearer req']);
    const moved = await run('quarantine', `parts/${K}.glb`, 'orders/none.json');
    assert.equal(moved.code, 1);
    assert.match(moved.out, new RegExp(`200 parts/${K}.glb`));
    assert.match(moved.out, /404 orders\/none.json/);
    assert.equal((await run('other')).code, 2);
  } finally {
    server.close();
  }
});

test('the parts lists of the site: the lists of the orders and the recipes of the window, at each commit; a list with no keys', async () => {
  const orders = bucket({ clock: () => WINDOW.from - 5 });
  const [C1, C2] = ['1'.repeat(40), '2'.repeat(40)];
  await orders.put(`builds/${C2}/${H}.near.elements`, '{"parts":[]}');
  await orders.put(`builds/${C1}/${B}.far.elements`, '{"parts":[]}');
  const claims = { repository: 'sntran/World', repository_owner_id: '973206', job_workflow_ref: 'sntran/World/.github/workflows/bucket-check.yml@refs/heads/main' };
  const env = { ORDERS: orders, WORLD_OWNER_ID: '973206' };
  const worker = (url, init) => handler(new Request(url, init), env, { vm: vm(), commit: 'c1', verify: async () => claims });
  const api = client('https://world.example', async () => 'a.b.c', worker);
  const dir = await mkdtemp(join(tmpdir(), 'lists-'));
  await mkdir(join(dir, 'bucket', 'parts'), { recursive: true });
  await writeFile(join(dir, 'bucket', `parts/${K}.json`), JSON.stringify({ order: B, level: 'far', node: 'n' }));
  await writeFile(join(dir, 'list.json'), JSON.stringify([{ key: `parts/${K}.json`, kind: 'recipe' }, { key: `orders/${H}.json`, kind: 'order' }]));
  const logs = [];
  assert.equal(await siteLists(api, dir, [C1, C2], (l) => logs.push(l)), 2);
  // (The recipe: B far; the order: H at each level; at two commits.)
  assert.deepEqual(logs, ['bucket: 2 parts lists of the site of before the window, of 8 looks']);
  assert.equal(await readFile(join(dir, 'bucket', `builds/${C2}/${H}.near.elements`), 'utf8'), '{"parts":[]}');
  const list = (key) => new TextEncoder().encode(JSON.stringify({ order: H, parts: [{ key, url: `/p/${key}.glb`, node: 'n' }] }));
  assert.equal(keyless(list('a')), keyless(list('b')));
  assert.notEqual(keyless(list('a')), keyless(new TextEncoder().encode(JSON.stringify({ order: B, parts: [{ key: 'a', node: 'n' }] }))));
  assert.equal(keyless(new TextEncoder().encode('{"x":1}')), null);
});

test('a parts list of the site with other keys agrees when it is the same list; each group gets the lists of its commits', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'keys-'));
  const C1 = '1'.repeat(40);
  const key = `builds/${C1}/${H}.mid.elements`;
  const site = JSON.stringify({ order: H, parts: [{ key: '7'.repeat(32), url: '/p/7.glb', node: 'n' }] });
  await mkdir(join(dir, 'bucket', 'builds', C1), { recursive: true });
  await mkdir(join(dir, 'bucket', 'orders'), { recursive: true });
  await writeFile(join(dir, 'bucket', key), site);
  await writeFile(join(dir, 'bucket', `orders/${H}.json`), '{}');
  await writeFile(join(dir, 'list.json'), JSON.stringify([{ key, kind: 'file', uploaded: new Date(WINDOW.from).toISOString(), size: 1, etag: 'e' }]));
  const git = (args) => (args[0] === 'log' ? `${C1} ${new Date(WINDOW.from - 1).toISOString()}\n` : args[0] === 'rev-parse' ? 'code\n' : '');
  const work = await plan(dir, git);
  assert.deepEqual(work.groups[0].maps, [{ key, hash: H, level: 'mid' }]);
  assert.deepEqual((await tasks(dir, '1')).maps, work.groups[0].maps);
  await mkdir(join(dir, 'out', '1', 'builds', C1), { recursive: true });
  await writeFile(join(dir, 'out', '1', key), site.replaceAll('7'.repeat(32), '8'.repeat(32)).replace('/p/7.glb', '/p/8.glb'));
  const [o] = await compare(dir);
  assert.deepEqual([o.verdict, o.note], ['agrees', 'the same list with the keys of the build of the site']);
  // (Another list: it differs.)
  await writeFile(join(dir, 'out', '1', key), site.replace('"node":"n"', '"node":"m"'));
  assert.deepEqual(await compare(dir).then(([o]) => [o.verdict, o.note]), ['differs', '/parts/0/node: "n" at the site, "m" in the rebuild']);
});

test('the notes of the compare: where a recipe differs, and a part with the bytes of a part of the rebuild under another key', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'notes-'));
  const C1 = '1'.repeat(40);
  const [R, S, T, P, Q] = ['1', '2', '3', '4', '5'].map((c) => c.repeat(32));
  const files = {
    [`parts/${R}.json`]: '{"order":"h","tile":{"box":[[0.1,2]]}}',
    [`parts/${S}.json`]: '{"order":"h","tile":{"box":[[0.1,2]]}}',
    [`parts/${T}.json`]: '{"a":1}',
    [`parts/${P}.glb`]: 'glTF P',
    [`parts/${Q}.glb`]: 'glTF Q',
  };
  for (const [key, value] of Object.entries(files)) {
    await mkdir(join(dir, 'bucket', 'parts'), { recursive: true });
    await writeFile(join(dir, 'bucket', key), value);
  }
  await writeFile(join(dir, 'list.json'), JSON.stringify(Object.keys(files).map((key) => ({ key, kind: kindOf(key), uploaded: new Date(WINDOW.from).toISOString(), size: 1, etag: 'e' }))));
  await writeFile(join(dir, 'groups.json'), JSON.stringify({ groups: [{ id: '1', commits: [C1] }], hashes: [], preview: [] }));
  await mkdir(join(dir, 'out', '1', 'parts'), { recursive: true });
  // (The rebuild: other numbers in R, the same values with other bytes in S, P under the key 9…, no Q.)
  await writeFile(join(dir, 'out', '1', `parts/${R}.json`), '{"order":"h","tile":{"box":[[0.10000000000000002,2,3]]}}');
  await writeFile(join(dir, 'out', '1', `parts/${S}.json`), '{"tile":{"box":[[0.1,2]]},"order":"h"}');
  await writeFile(join(dir, 'out', '1', `parts/${T}.json`), 'no JSON');
  await writeFile(join(dir, 'out', '1', `parts/${'9'.repeat(32)}.glb`), 'glTF P');
  const report = await compare(dir);
  const of = (key) => report.find((o) => o.key === key);
  assert.deepEqual([of(`parts/${R}.json`).verdict, of(`parts/${R}.json`).note], ['differs', '/tile/box/0/0: 0.1 at the site, 0.10000000000000002 in the rebuild; /tile/box/0/2: none at the site, 3 in the rebuild']);
  assert.deepEqual([of(`parts/${S}.json`).verdict, of(`parts/${S}.json`).note], ['agrees', 'the same JSON values with other bytes']);
  assert.deepEqual([of(`parts/${T}.json`).verdict, of(`parts/${T}.json`).note], ['differs', '']);
  assert.deepEqual([of(`parts/${P}.glb`).verdict, of(`parts/${P}.glb`).note], ['agrees', `the same bytes as the part ${'9'.repeat(32)} of the rebuild`]);
  assert.deepEqual([of(`parts/${Q}.glb`).verdict, of(`parts/${Q}.glb`).note], ['none', '']);
});

// A GLB with a JSON chunk (and a BIN chunk that the data leaves out).
const glb = (json) => {
  const text = Buffer.from(JSON.stringify(json));
  const pad = Buffer.concat([text, Buffer.alloc((4 - (text.length % 4)) % 4, 0x20)]);
  const head = Buffer.alloc(20);
  head.write('glTF', 0, 'latin1');
  head.writeUInt32LE(2, 4);
  head.writeUInt32LE(20 + pad.length + 12, 8);
  head.writeUInt32LE(pad.length, 12);
  head.write('JSON', 16, 'latin1');
  return Buffer.concat([head, pad, Buffer.from([4, 0, 0, 0, 0x42, 0x49, 0x4e, 0, 1, 2, 3, 4])]);
};

test('the part from the recipe of the site; a recipe of another order with the same part; a part with the name of a part of the rebuild', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'recipe-'));
  const [K, M, N] = ['6', '7', '8'].map((c) => c.repeat(32));
  const [o1, o2] = ['1', '2'].map((c) => c.repeat(32));
  const lamp = (size) => glb({ asset: { version: '2.0' }, scenes: [{ name: 'lamp', extras: { level: 'mid', size } }], buffers: [{ byteLength: 4 }] });
  const files = {
    [`parts/${K}.json`]: JSON.stringify({ order: o1, level: 'mid', node: 'n' }),
    [`parts/${K}.glb`]: 'glTF K',
    [`parts/${M}.json`]: JSON.stringify({ order: o1, level: 'mid', node: 'n' }),
    [`parts/${N}.glb`]: lamp([1, 2]),
  };
  await mkdir(join(dir, 'bucket', 'parts'), { recursive: true });
  for (const [key, value] of Object.entries(files)) await writeFile(join(dir, 'bucket', key), value);
  // (The GLB of M is of before the window.)
  await writeFile(join(dir, 'bucket', `parts/${M}.glb`), 'glTF M');
  await writeFile(join(dir, 'list.json'), JSON.stringify(Object.keys(files).map((key) => ({ key, kind: kindOf(key), uploaded: new Date(WINDOW.from).toISOString(), size: 1, etag: 'e' }))));
  await writeFile(join(dir, 'groups.json'), JSON.stringify({ groups: [{ id: '1', commits: ['1'.repeat(40)] }], hashes: [], preview: [] }));
  const out = async (key, value) => {
    await mkdir(join(dir, 'out', '1', key, '..'), { recursive: true });
    await writeFile(join(dir, 'out', '1', key), value);
  };
  // (The rebuild: K from its recipe; the recipes of K and M at the place of the list name the other order; M from its recipe; a lamp of another size.)
  await out(`from-recipe/${K}.glb`, 'glTF K');
  await out(`parts/${K}.json`, JSON.stringify({ order: o2, level: 'mid', node: 'n' }));
  await out(`parts/${M}.json`, JSON.stringify({ order: o2, level: 'mid', node: 'n' }));
  await out(`from-recipe/${M}.glb`, 'glTF other');
  await out(`parts/${'9'.repeat(32)}.glb`, lamp([1, 3]));
  const report = await compare(dir);
  const of = (key) => [report.find((o) => o.key === key).verdict, report.find((o) => o.key === key).note];
  assert.deepEqual(of(`parts/${K}.glb`), ['agrees', 'the part from the recipe of the site agrees']);
  assert.deepEqual(of(`parts/${K}.json`), ['agrees', `another order with the same part (/order: "${o1}" at the site, "${o2}" in the rebuild); the part from this recipe agrees`]);
  // (The part from the recipe of M has other bytes than the GLB of the site: the recipe differs.)
  assert.deepEqual(of(`parts/${M}.json`), ['differs', `/order: "${o1}" at the site, "${o2}" in the rebuild`]);
  assert.deepEqual(of(`parts/${N}.glb`), ['none', `the part ${'9'.repeat(32)} of the rebuild has the same name: /scenes/0/extras/size/1: 2 at the site, 3 in the rebuild`]);
});
