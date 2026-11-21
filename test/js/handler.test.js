// The tests of handler.js, with a fake VM and a fake R2 bucket.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import { callerOf, handler, orderOf, split, storeToken, urlKey } from '../../handler.js';
import { BLUEPRINTS, HASH, bucket, vm } from './fakes.js';

const req = (path, init) => new Request(`https://world.mkfifo.com${path}`, init);

test('the name and the file of a path', () => {
  assert.deepEqual(split('van.mid.glb')[0], 'van');
  assert.equal(split('van.mid.glb')[1][1], 'mid');
  assert.equal(split('van.glb')[1][1], 'near');
  assert.equal(split('van.receipt.json')[1][2], 'receipt');
  assert.equal(split('van.solids.json')[1][2], 'solids');
  assert.deepEqual(split('van.far.flat.glb').map((x, i) => (i ? x.slice(1, 3) : x)), ['van', ['far', 'flat']]);
  assert.deepEqual(split('van.flat.glb').map((x, i) => (i ? x.slice(1, 3) : x)), ['van', ['near', 'flat']]);
  assert.deepEqual(split('van.far.light.glb').map((x, i) => (i ? x.slice(1, 3) : x)), ['van', ['far', 'light']]);
  assert.deepEqual(split('van.light.glb').map((x, i) => (i ? x.slice(1, 3) : x)), ['van', ['near', 'light']]);
  assert.equal(split('van.drawing.json')[1][2], 'drawing');
  assert.equal(split('van.log.json')[1][2], 'log');
  assert.deepEqual(split('van.replay.glb').map((x, i) => (i ? x[2] : x)), ['van', 'replay']);
  assert.equal(split('.glb'), null);
  assert.equal(split('van.txt'), null);
});

// A token (32 characters or more).
const TOKEN = 't'.repeat(40);
const auth = (path, init = {}, token = TOKEN) => req(path, { ...init, headers: { authorization: `Bearer ${token}`, ...(init.headers ?? {}) } });

// The check of an ID token in the tests: a token "jwt.of.NAME" has the claims of FAKES[NAME].
const FAKES = {
  shift: { repository: 'sntran/World', repository_owner_id: '973206', job_workflow_ref: 'sntran/World/.github/workflows/shift.yml@refs/heads/main', run_id: '1900', run_attempt: '2' },
  request: { repository: 'sntran/World', repository_owner_id: '973206', job_workflow_ref: 'sntran/World/.github/workflows/shift-request.yml@refs/heads/main' },
  project: { repository: 'sntran/Vung_Tau', repository_owner_id: '973206', job_workflow_ref: 'sntran/Vung_Tau/.github/workflows/w.yml@refs/heads/main' },
  stranger: { repository: 'someone/Vung_Tau', repository_owner_id: '42' },
};
const check = async (token) => FAKES[token.split('.')[2]] ?? null;
const OWNER = { WORLD_OWNER_ID: '973206' };
const jwt = (name, headers = {}) => ({ authorization: `Bearer jwt.of.${name}`, ...headers });

test('the caller of a request: a job of GitHub Actions by its ID token, or WORLD_TOKEN with the name of the project', async () => {
  const caller = (headers, env = {}) => callerOf(req('/p/x.glb', { headers }), { ...OWNER, ...env }, check);
  assert.deepEqual(await caller(jwt('project')), { kind: 'project', project: 'vung_tau', claims: FAKES.project });
  // (A project of a job has the name of its repository, not the name of the header.)
  assert.equal((await caller(jwt('project', { 'x-world-project': 'other' }))).project, 'vung_tau');
  assert.equal((await caller(jwt('request', { 'x-world-project': 'vung_tau' }))).project, 'vung_tau');
  assert.equal((await caller(jwt('shift'))).kind, 'shift');
  assert.equal(await caller(jwt('stranger')), null);
  assert.equal(await caller(jwt('nobody')), null);
  // WORLD_TOKEN: with a project in the header, and a name that is a name.
  const env = { WORLD_TOKEN: TOKEN };
  assert.deepEqual(await caller({ authorization: `Bearer ${TOKEN}`, 'x-world-project': 'vung_tau' }, env), { kind: 'token', project: 'vung_tau' });
  assert.equal(await caller({ authorization: `Bearer ${TOKEN}` }, env), null);
  assert.equal(await caller({ authorization: `Bearer ${TOKEN}`, 'x-world-project': 'Vung Tau; x' }, env), null);
  assert.equal(await caller({ authorization: `Bearer ${TOKEN}x`, 'x-world-project': 'vung_tau' }, env), null);
  assert.equal(await caller({ authorization: 'Bearer short', 'x-world-project': 'vung_tau' }, { WORLD_TOKEN: 'short' }), null);
  assert.equal(await caller({ 'x-world-project': 'vung_tau' }, env), null);
  // (The real check of oidc.js: a token that is not signed by GitHub is no caller.)
  assert.equal(await callerOf(req('/p/x.glb', { headers: { authorization: 'Bearer a.b.c' } }), OWNER), null);
});

test('the join of a shift: the ID token of shift.yml, or the token of the store of a test; another caller gets 401', async () => {
  const runs = [];
  const v = async (request) => {
    runs.push(request.headers.get('x-world-shift-run'));
    return Response.json({ node: 'shift_19002_1_4372@127.0.0.1', cookie: 'c', pass: 'p', edge: 'world@127.0.0.1' });
  };
  const call = (headers, env = {}) => handler(req('/shift/join', { method: 'POST', headers }), { ORDERS: bucket(), ...OWNER, ...env }, { vm: v, commit: 'c1', verify: check });
  const joined = await call(jwt('shift'));
  assert.equal(joined.status, 200);
  assert.equal(joined.headers.get('cache-control'), 'no-store');
  assert.equal((await joined.json()).node, 'shift_19002_1_4372@127.0.0.1');
  assert.equal((await call({ authorization: `Bearer ${TOKEN}` }, { WORLD_STORE_TOKEN: TOKEN })).status, 200);
  assert.deepEqual(runs, ['1900-2', 'test']);
  assert.equal((await call(jwt('project'))).status, 401);
  assert.equal((await call(jwt('request'))).status, 401);
  assert.equal((await call({})).status, 401);
});

test('/store/ with the pass of a shift: only a key that the edge gave to that shift, else 403', async () => {
  const env = { ORDERS: bucket() };
  const pass = 'a'.repeat(64);
  const given = `parts/${HASH}.glb`;
  const asked = [];
  // (The VM gets the SHA-256 of the pass, never the pass.)
  const hash = createHash('sha256').update(pass).digest('hex');
  const v = async (request) => {
    const u = new URL(request.url);
    assert.equal(request.headers.has('x-world-shift-pass'), false);
    assert.equal(JSON.stringify([...request.headers]).includes(pass), false);
    asked.push(`${u.searchParams.get('access')} ${u.searchParams.get('key')} ${request.headers.get('x-world-shift-pass-hash') === hash}`);
    return new Response(null, { status: u.searchParams.get('key') === given && request.headers.get('x-world-shift-pass-hash') === hash ? 204 : 403 });
  };
  const call = (path, init = {}, token = pass) => handler(auth(path, init, token), env, { vm: v, commit: 'c1' });
  assert.equal(await (await call(`/store/${given}`, { method: 'PUT', body: 'glTF' })).text(), 'ok\n');
  assert.equal(await (await call(`/store/${given}`)).text(), 'glTF');
  assert.deepEqual(asked, [`write ${given} true`, `read ${given} true`]);
  // A part that the edge did not give to the shift, another pass, a pass that is not a pass, no pass, and a key that is not a key.
  assert.equal((await call(`/store/parts/${'b'.repeat(32)}.glb`, { method: 'PUT', body: 'glTF' })).status, 403);
  assert.equal((await call(`/store/${given}`, {}, 'b'.repeat(64))).status, 403);
  assert.equal((await call(`/store/${given}`, {}, 'short')).status, 403);
  assert.equal((await handler(req(`/store/${given}`), env, { vm: v, commit: 'c1' })).status, 403);
  assert.equal((await call('/store/secrets/x.json')).status, 403);
  assert.equal(asked.length, 4);
});

test('the token of the store of a test: the secret, or no store', () => {
  const env = { WORLD_STORE_TOKEN: TOKEN };
  assert.equal(storeToken(auth('/store/x'), env), true);
  assert.equal(storeToken(req('/store/x'), env), false);
  assert.equal(storeToken(auth('/store/x', {}, `${TOKEN}x`), env), false);
  assert.equal(storeToken(auth('/store/x'), {}), false);
  assert.equal(storeToken(auth('/store/x', {}, 'short'), { WORLD_STORE_TOKEN: 'short' }), false);
});

test('/.tcp/: only a WebSocket to the port of the distribution goes to the VM; each other path gets 404', async () => {
  const reached = [];
  const v = async (request) => {
    reached.push(new URL(request.url).pathname);
    return new Response(`to the VM: ${new URL(request.url).pathname}`, { status: 200 });
  };
  const ws = (path, env = {}, upgrade = 'websocket') => handler(req(path, { headers: { upgrade } }), { ORDERS: bucket(), ...env }, { vm: v, commit: 'c1' });
  assert.equal(await (await ws('/.tcp/4370')).text(), 'to the VM: /.tcp/4370');
  assert.equal((await ws('/.tcp/4370', {}, 'WebSocket')).status, 200);
  for (const path of ['/.tcp/4000', '/.tcp/1', '/.tcp/4370x', '/.tcp/04370', '/.tcp/4370/', '/.tcp/', '/.tcp/4370/x']) {
    const r = await ws(path);
    assert.equal(r.status, 404, path);
    assert.deepEqual(await r.json(), { errors: [{ path: '', message: 'no such page' }] });
  }
  // Not a WebSocket, or a WebSocket of another kind.
  assert.equal((await handler(req('/.tcp/4370'), { ORDERS: bucket() }, { vm: v, commit: 'c1' })).status, 404);
  assert.equal((await handler(req('/.tcp/4370', { method: 'POST', body: 'x' }), { ORDERS: bucket() }, { vm: v, commit: 'c1' })).status, 404);
  assert.equal((await ws('/.tcp/4370', {}, 'h2c')).status, 404);
  // DIST_PORT gives the port: then 4370 is another port.
  assert.equal((await ws('/.tcp/4371', { DIST_PORT: '4371' })).status, 200);
  assert.equal((await ws('/.tcp/4370', { DIST_PORT: '4371' })).status, 404);
  assert.deepEqual(reached, ['/.tcp/4370', '/.tcp/4370', '/.tcp/4371']);
});

test('/store/ of a test: get, head and put of a key of the store, with the token', async () => {
  const env = { ORDERS: bucket(), WORLD_STORE_TOKEN: TOKEN };
  const call = (path, init) => handler(auth(path, init), env, { vm: vm(), commit: 'c1' });
  const key = `parts/${HASH}.glb`;
  assert.equal((await call(`/store/${key}`)).status, 404);
  assert.equal((await call(`/store/${key}`, { method: 'HEAD' })).status, 404);
  assert.equal(await (await call(`/store/${key}`, { method: 'PUT', body: 'glTF' })).text(), 'ok\n');
  assert.equal(env.ORDERS.types.get(key), 'model/gltf-binary');
  const got = await call(`/store/${key}`);
  assert.equal(got.status, 200);
  assert.equal(got.headers.get('content-type'), 'model/gltf-binary');
  assert.equal(await got.text(), 'glTF');
  assert.equal((await call(`/store/${key}`, { method: 'HEAD' })).status, 200);
  // An empty part, a key that is not a key of the store, another method, no token, and no secret.
  assert.equal((await call(`/store/parts/${HASH}.json`, { method: 'PUT', body: '' })).status, 400);
  assert.equal((await call('/store/secrets/x.json')).status, 404);
  assert.equal((await call(`/store/${key}`, { method: 'DELETE' })).status, 405);
  assert.equal((await handler(req(`/store/${key}`), env, { vm: vm(), commit: 'c1' })).status, 403);
});

test('a part that a node of a shift built: the VM answers 204, and the part goes out of R2', async () => {
  const env = { ORDERS: bucket() };
  const key = 'e'.repeat(32);
  // (The node puts the part in R2 while the VM waits for it.)
  const v = async () => {
    await env.ORDERS.put(`parts/${key}.glb`, 'glTF of a node');
    return new Response(null, { status: 204 });
  };
  const r = await handler(req(`/p/${key}.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(r.status, 200);
  assert.equal(await r.text(), 'glTF of a node');
  // (R2 does not have it yet: ask again.)
  const none = await handler(req(`/p/${'d'.repeat(32)}.glb`), { ORDERS: bucket() }, { vm: async () => new Response(null, { status: 204 }), commit: 'c1' });
  assert.equal(none.status, 202);
  assert.equal(none.headers.get('retry-after'), '1');
});

test('a part of a project: the VM gets the project; when it wants a shift, the Worker starts one after the answer, for a project only', async () => {
  const later = [];
  const seen = [];
  const env = { ORDERS: bucket(), WORLD_TOKEN: TOKEN };
  const v = async (request) => {
    seen.push(request.headers.get('x-world-project'));
    return Response.json({ building: 'x' }, { status: 202, headers: { 'retry-after': '15', 'x-world-shift': 'wanted' } });
  };
  const key = 'c'.repeat(32);
  const r = await handler(auth(`/p/${key}.glb`, { headers: { 'x-world-project': 'vung_tau', 'x-world-shift-hours': '2' } }), env, { vm: v, commit: 'c1', later: (p) => later.push(p) });
  assert.equal(r.status, 202);
  assert.equal(r.headers.get('x-world-shift'), 'wanted');
  // (No WORLD_SHIFT_TOKEN in this env: the start says so.)
  assert.deepEqual(await Promise.all(later), ['no token']);
  // A request with no token: no project, and no shift starts (the starts of the day are for the projects).
  const anyone = await handler(req(`/p/${key}.glb`), env, { vm: v, commit: 'c1', later: (p) => later.push(p) });
  assert.equal(anyone.status, 202);
  assert.equal(later.length, 1);
  // With no later(), nothing breaks.
  await handler(req(`/p/${key}.glb`), env, { vm: v, commit: 'c1' });
  assert.deepEqual(seen, ['vung_tau', null, null]);
});

test('an order from a URL', () => {
  const order = orderOf('van', new URLSearchParams('make=ford&color.paint=%23ff0000&joint.hood=50&gear=a,b'));
  assert.deepEqual(order, { blueprint: 'van', options: { make: 'ford', gear: 'a,b' }, colors: { paint: '#ff0000' }, joints: { hood: 50 } });
  const person = orderOf('traveler', new URLSearchParams('origin.asian=0.5&origin.african=0.5&vehicle=car'));
  assert.deepEqual(person.options, { origin: { asian: '0.5', african: '0.5' }, vehicle: 'car' });
  const reach = orderOf('person', new URLSearchParams('target.arm_r=0.3,0.4,1.3&joint.elbow_l=90'));
  assert.deepEqual(reach.targets, { arm_r: [0.3, 0.4, 1.3] });
  assert.deepEqual(reach.joints, { elbow_l: 90 });
});

test('POST /orders goes to the VM, with the origin of the URLs', async () => {
  const v = vm();
  const r = await handler(req('/orders', { method: 'POST', headers: { 'content-type': 'application/json', 'x-world-origin': 'https://evil.example' }, body: JSON.stringify({ blueprint: 'box' }) }), { ORDERS: bucket() }, { vm: v, commit: 'c1' });
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  assert.equal(r.headers.get('content-type'), 'application/json');
  const body = await r.json();
  assert.equal(body.hash, HASH);
  // The Worker gives the origin, not the client.
  assert.equal(body.files.glb, `https://world.mkfifo.com/o/${HASH}.glb`);
  assert.equal(body.replay, `https://world.mkfifo.com/replay.html?order=${HASH}`);
  assert.equal(v.last.headers.get('content-type'), 'application/json');
  assert.ok(v.orders.has(HASH));
});

test('POST /orders/HASH/edits goes to the VM, with the origin of the URLs', async () => {
  const v = vm();
  const hash = '0123456789abcdef0123456789abcdef';
  const r = await handler(req(`/orders/${hash}/edits`, { method: 'POST', body: JSON.stringify({ edits: [] }) }), { ORDERS: bucket() }, { vm: v, commit: 'c1' });
  assert.equal(r.status, 422);
  assert.deepEqual(v.calls, [`/orders/${hash}/edits`]);
  assert.equal(v.last.headers.get('x-world-origin'), 'https://world.mkfifo.com');
});

test('POST /sets goes to the VM, with the origin of the URLs', async () => {
  const v = vm();
  const r = await handler(req('/sets', { method: 'POST', body: JSON.stringify({ orders: [] }) }), { ORDERS: bucket() }, { vm: v, commit: 'c1' });
  assert.equal(r.status, 422);
  assert.deepEqual(v.calls, ['/sets']);
  assert.equal(v.last.headers.get('x-world-origin'), 'https://world.mkfifo.com');
});

test('POST /orders gives the errors of the VM: 422 for a wrong order, 400 for a body that is not JSON', async () => {
  const env = { ORDERS: bucket() };
  const wrong = await handler(req('/orders', { method: 'POST', body: '{"blueprint":"x"}' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(wrong.status, 422);
  assert.equal((await wrong.json()).errors[0].path, 'blueprint');
  const bad = await handler(req('/orders', { method: 'POST', body: 'nope' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(bad.status, 400);
});

test('/mcp goes to the VM: the body, the version of the protocol, 202 with no body, and 405', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  const call = (body, headers = {}) => handler(req('/mcp', { method: 'POST', headers, body: JSON.stringify(body) }), env, { vm: v, commit: 'c1' });

  const ping = await call({ jsonrpc: '2.0', id: 1, method: 'ping' }, { 'mcp-protocol-version': '2025-06-18', cookie: 'a=b' });
  assert.equal(ping.status, 200);
  assert.equal(ping.headers.get('access-control-allow-origin'), '*');
  assert.deepEqual(await ping.json(), { jsonrpc: '2.0', id: 1, result: { version: '2025-06-18' } });
  assert.equal(v.last.headers.get('x-world-origin'), 'https://world.mkfifo.com');
  assert.equal(v.last.headers.get('cookie'), null);

  const note = await call({ jsonrpc: '2.0', method: 'notifications/initialized' });
  assert.equal(note.status, 202);
  assert.equal(await note.text(), '');

  for (const method of ['GET', 'DELETE']) {
    const r = await handler(req('/mcp', { method }), env, { vm: v, commit: 'c1' });
    assert.equal(r.status, 405);
    assert.equal(r.headers.get('allow'), 'POST');
  }

  const options = await handler(req('/mcp', { method: 'OPTIONS' }), env, { vm: v, commit: 'c1' });
  assert.equal(options.status, 204);
  assert.match(options.headers.get('access-control-allow-headers'), /mcp-protocol-version/);
});

test('GET /o/ builds a file one time, then serves it from R2, with an ETag', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  v.orders.set(HASH, { blueprint: 'box' });
  const first = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(first.status, 200);
  assert.equal(first.headers.get('content-type'), 'model/gltf-binary');
  assert.equal(first.headers.get('x-world-commit'), 'c1');
  assert.equal(await first.text(), 'mid glb');
  const etag = first.headers.get('etag');

  const second = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(await second.text(), 'mid glb');
  assert.deepEqual(v.calls.filter((c) => c.startsWith('/build')), [`/build?level=mid&file=glb&hash=${HASH}`]);

  const same = await handler(req(`/o/${HASH}.mid.glb`, { headers: { 'if-none-match': etag } }), env, { vm: v, commit: 'c1' });
  assert.equal(same.status, 304);

  // A new deploy builds the file again.
  await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c2' });
  assert.equal(v.calls.filter((c) => c.startsWith('/build')).length, 2);

  const receipt = await handler(req(`/o/${HASH}.receipt.json`), env, { vm: v, commit: 'c1' });
  assert.equal(await receipt.text(), 'near receipt');
});

test('GET /o/ of a parts list goes to the VM at its level', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  v.orders.set(HASH, { blueprint: 'box' });
  for (const [name, text] of [['elements.json', 'near elements'], ['mid.elements.json', 'mid elements'], ['far.elements.json', 'far elements']]) {
    const r = await handler(req(`/o/${HASH}.${name}`), env, { vm: v, commit: 'c1' });
    assert.equal(r.headers.get('content-type'), 'application/json');
    assert.equal(await r.text(), text);
  }
});

test('GET /o/ of a parts list that builds on gives 202 with retry-after, and keeps nothing in R2', async () => {
  const env = { ORDERS: bucket() };
  const v = async () => Response.json({ building: 'elements' }, { status: 202, headers: { 'retry-after': '15' } });
  const r = await handler(req(`/o/${HASH}.far.elements.json`), env, { vm: v, commit: 'c1' });
  assert.equal(r.status, 202);
  assert.equal(r.headers.get('retry-after'), '15');
  assert.deepEqual(await r.json(), { building: 'elements' });
  assert.equal(env.ORDERS.items.size, 0);
});

test('GET /p/ serves a part from R2 with no VM, else the VM builds it; a wrong key is 404', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  const key = HASH;
  await env.ORDERS.put(`parts/${key}.glb`, 'glTF');
  const kept = await handler(req(`/p/${key}.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(kept.status, 200);
  assert.equal(await kept.text(), 'glTF');
  assert.equal(kept.headers.get('content-type'), 'model/gltf-binary');
  assert.match(kept.headers.get('cache-control'), /immutable/);
  assert.equal(kept.headers.get('etag'), `"${key}"`);
  assert.equal((await handler(req(`/p/${key}.glb`, { headers: { 'if-none-match': `"${key}"` } }), env, { vm: v, commit: 'c1' })).status, 304);
  assert.deepEqual(v.calls, []);

  // A part that R2 does not have: the VM builds it (its headers come too).
  const other = 'f'.repeat(32);
  const built = await handler(req(`/p/${other}.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(built.status, 200);
  assert.equal(await built.text(), 'glTF built');
  assert.equal(built.headers.get('retry-after'), '15');
  assert.deepEqual(v.calls, [`/p/${other}.glb`]);
  for (const path of ['/p/xyz.glb', `/p/${key}.png`]) assert.equal((await handler(req(path), env, { vm: v, commit: 'c1' })).status, 404);
});

test('GET /o/ of an order that the VM does not have, or of a wrong name, is 404', async () => {
  const env = { ORDERS: bucket() };
  assert.equal((await handler(req(`/o/${HASH}.glb`), env, { vm: vm(), commit: 'c1' })).status, 404);
  assert.equal((await handler(req('/o/xyz.glb'), env, { vm: vm(), commit: 'c1' })).status, 404);
  assert.equal((await handler(req(`/o/${HASH}.txt`), env, { vm: vm(), commit: 'c1' })).status, 404);
});

test('GET /m/ checks the order of the URL, then builds it', async () => {
  const env = { ORDERS: bucket() };
  const ok = await handler(req('/m/box.far.glb?size=2'), env, { vm: vm(), commit: 'c1' });
  assert.equal(await ok.text(), 'far glb');
  const wrong = await handler(req('/m/ball.glb'), env, { vm: vm(), commit: 'c1' });
  assert.equal(wrong.status, 422);
  const joint = await handler(req('/m/box.glb?joint.bad=1'), env, { vm: vm(), commit: 'c1' });
  assert.equal(joint.status, 422);
  assert.equal((await handler(req('/m/box'), env, { vm: vm(), commit: 'c1' })).status, 404);
});

test('GET /m/ of a URL that the factory knows needs no VM', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  const first = await handler(req('/m/box.mid.glb?size=2'), env, { vm: v, commit: 'c1' });
  assert.equal(await first.text(), 'mid glb');
  const key = await urlKey('c1', new URL('https://world.mkfifo.com/m/box.mid.glb?size=2'));
  assert.match(key, /^urls\/c1\/[0-9a-f]{64}$/);
  assert.deepEqual(JSON.parse(new TextDecoder().decode(env.ORDERS.items.get(key))), { hash: HASH });
  // One request to the VM: it checks the order and builds the file.
  assert.deepEqual(v.calls, ['/build?level=mid&file=glb']);

  // The same URL: the file of R2, with no call of the VM.
  const second = await handler(req('/m/box.mid.glb?size=2'), env, { vm: v, commit: 'c1' });
  assert.equal(second.status, 200);
  assert.equal(second.headers.get('x-world-order'), HASH);
  assert.equal(await second.text(), 'mid glb');
  const etag = second.headers.get('etag');
  const same = await handler(req('/m/box.mid.glb?size=2', { headers: { 'if-none-match': etag } }), env, { vm: v, commit: 'c1' });
  assert.equal(same.status, 304);
  assert.equal(v.calls.length, 1);

  // Another file: the VM builds it, and the key of the URL stays.
  const far = await handler(req('/m/box.far.glb?size=2'), env, { vm: v, commit: 'c1' });
  assert.equal(await far.text(), 'far glb');
  const known = await handler(req('/m/box.mid.glb?size=2'), env, { vm: v, commit: 'c1' });
  assert.equal(await known.text(), 'mid glb');
  const keyFar = await urlKey('c1', new URL('https://world.mkfifo.com/m/box.far.glb?size=2'));
  assert.ok(env.ORDERS.items.has(keyFar));

  // A known URL with no file in R2 (a file that the bucket lost): the VM.
  env.ORDERS.items.delete(`builds/c1/${HASH}.mid.glb`);
  const again = await handler(req('/m/box.mid.glb?size=2'), env, { vm: v, commit: 'c1' });
  assert.equal(await again.text(), 'mid glb');
  assert.equal(v.calls.filter((c) => c.startsWith('/build')).length, 3);

  // A known URL with a file of the same level, and the key of the URL
  // stays.
  const known2 = await urlKey('c1', new URL('https://world.mkfifo.com/m/box.mid.glb?size=2'));
  assert.deepEqual(JSON.parse(new TextDecoder().decode(env.ORDERS.items.get(known2))), { hash: HASH });

  // A new deploy builds the URL again.
  const calls = v.calls.length;
  await handler(req('/m/box.mid.glb?size=2'), env, { vm: v, commit: 'c2' });
  assert.equal(v.calls.length, calls + 1);
});

test('a blueprint in data of a project goes to the VM', async () => {
  const v = vm();
  await handler(req('/blueprints', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }), { ORDERS: bucket() }, { vm: v, commit: 'c1' });
  assert.equal(v.calls.at(-1), '/blueprints');
  assert.equal(v.last.method, 'POST');
});

test('the constructions and the streams go to the VM, with Last-Event-ID, and come back as they come', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  const post = await handler(req('/builds', { method: 'POST', headers: { accept: 'text/event-stream', 'content-type': 'application/json' }, body: '{}' }), env, { vm: v, commit: 'c1' });
  assert.equal(post.headers.get('content-type'), 'text/event-stream');
  assert.equal(post.headers.get('cache-control'), 'no-cache');
  assert.equal(await post.text(), 'id: 1\ndata: {"id":1}\n\n');
  assert.equal(v.last.headers.get('accept'), 'text/event-stream');
  assert.equal(v.last.headers.get('x-world-origin'), 'https://world.mkfifo.com');

  const events = await handler(req('/events?after=4', { headers: { 'last-event-id': '7' } }), env, { vm: v, commit: 'c1' });
  assert.equal(events.status, 200);
  assert.equal(v.last.headers.get('last-event-id'), '7');
  for (const path of ['/census', '/places', '/places/nui_nho/ground.glb', '/builds/abc-far', '/builds/abc-far/events', '/builds/abc-far/elements/0.glb']) {
    await handler(req(path), env, { vm: v, commit: 'c1' });
  }
  assert.deepEqual(v.calls.slice(-8), ['/builds', '/events?after=4', '/census', '/places', '/places/nui_nho/ground.glb', '/builds/abc-far', '/builds/abc-far/events', '/builds/abc-far/elements/0.glb']);
  assert.equal((await handler(req('/builds', { method: 'PUT' }), env, { vm: v, commit: 'c1' })).status, 405);
  assert.equal((await handler(req('/builds/abc-far/stop', { method: 'POST' }), env, { vm: v, commit: 'c1' })).status, 405);
});

// A VM of constructions: POST /builds opens the construction of the
// "id" of the body (x-world-started) or joins it ("joined": true), and
// each other request answers 202.
function builder() {
  const seen = [];
  const fn = async (request) => {
    const url = new URL(request.url);
    seen.push({ path: url.pathname, headers: [...request.headers], body: request.body ? await request.text() : '' });
    if (url.pathname === '/builds') {
      const job = JSON.parse(seen.at(-1).body);
      if (job.bad) return Response.json({ errors: [{ path: 'order', message: 'no' }] }, { status: 422, headers: { 'x-world-started': job.id } });
      const extra = job.joined ? {} : { 'x-world-started': job.id };
      if (job.stream) return new Response('id: 1\ndata: {"id":1}\n\n', { headers: { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', ...extra } });
      return Response.json({ build: job.id, events: `/builds/${job.id}/events?after=0` }, { status: 202, headers: extra });
    }
    return Response.json({ build: url.pathname.split('/')[2], asked: url.pathname.split('/')[3] }, { status: 202 });
  };
  fn.seen = seen;
  return fn;
}

const open = (env, v, job, headers = {}) =>
  handler(req('/builds', { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(job) }), env, { vm: v, commit: 'c1' });

test('POST /builds gives a control key only to the caller that opens the construction, in the body; R2 keeps only its hash', async () => {
  const env = { ORDERS: bucket() };
  const v = builder();
  const r = await open(env, v, { id: 'a-far' });
  assert.equal(r.status, 202);
  assert.equal(r.headers.get('cache-control'), 'no-store');
  assert.equal(r.headers.get('content-type'), 'application/json');
  const body = await r.json();
  const key = body.control;
  assert.match(key, /^[0-9a-f]{64}$/);
  assert.deepEqual(body, { build: 'a-far', events: '/builds/a-far/events?after=0', control: key });
  // (No header has the key, nor the mark of the VM.)
  for (const [name, value] of r.headers) assert.ok(!value.includes(key) && name !== 'x-world-started', name);
  const stored = new TextDecoder().decode(env.ORDERS.items.get('controls/a-far'));
  assert.match(stored, /^[0-9a-f]{64}$/);
  assert.notEqual(stored, key);
  // A stream of a new construction: its first event is the key, then the events of the VM.
  const stream = await open(env, v, { id: 'b-far', stream: true }, { accept: 'text/event-stream' });
  assert.equal(stream.headers.get('content-type'), 'text/event-stream');
  assert.equal(stream.headers.get('cache-control'), 'no-store');
  const text = await stream.text();
  const [first, rest] = [text.split('\n\n')[0], text.split('\n\n').slice(1).join('\n\n')];
  assert.match(first, /^event: control\ndata: \{"build":"b-far","control":"[0-9a-f]{64}"\}$/);
  assert.notEqual(JSON.parse(first.split('data: ')[1]).control, key);
  assert.equal(rest, 'id: 1\ndata: {"id":1}\n\n');
  // A caller that joins a construction gets no key, and the key of the first caller stays.
  const joined = await open(env, v, { id: 'a-far', joined: true });
  assert.equal(joined.status, 202);
  assert.equal((await joined.json()).control, undefined);
  assert.equal(new TextDecoder().decode(env.ORDERS.items.get('controls/a-far')), stored);
  // An error, or an id that is not an id: no key.
  const bad = await open(env, v, { id: 'c-far', bad: true });
  assert.equal(bad.status, 422);
  assert.equal((await bad.json()).control, undefined);
  assert.equal((await (await open(env, v, { id: 'a/b' })).json()).control, undefined);
  assert.ok(!env.ORDERS.items.has('controls/c-far'));
  // R2 does not keep the hash: the construction opens, with no key.
  const failing = { ORDERS: { ...bucket(), put: async () => { throw new Error('R2'); } } };
  const lost = await open(failing, v, { id: 'd-far' });
  assert.equal(lost.status, 202);
  assert.equal((await lost.json()).control, undefined);
  // A 202 with a body that is not JSON (not from World): the key with the id.
  const odd = async () => new Response('?', { status: 202, headers: { 'x-world-started': 'e-far' } });
  const plain = await open(env, odd, {});
  assert.deepEqual(Object.keys(await plain.json()), ['build', 'control']);
  // A stream with no body: only the key.
  const empty = async () => new Response(null, { headers: { 'content-type': 'text/event-stream', 'x-world-started': 'f-far' } });
  assert.match(await (await open(env, empty, {})).text(), /^event: control\ndata: .*\n\n$/);
  // No key of the store of the shifts is a key of a control.
  const shift = await handler(req('/store/controls/a-far', { headers: { authorization: 'Bearer x' } }), env, { vm: v, commit: 'c1' });
  assert.notEqual(shift.status, 200);
});

test('a pause, a resume, a cancel and a change need the control key of the construction or WORLD_TOKEN; each other caller gets 403', async () => {
  const token = 'w'.repeat(40);
  const env = { ORDERS: bucket(), WORLD_TOKEN: token };
  const v = builder();
  const a = (await (await open(env, v, { id: 'a-far' })).json()).control;
  const b = (await (await open(env, v, { id: 'b-far' })).json()).control;
  const act = (name, auth) =>
    handler(req(`/builds/a-far/${name}`, { method: 'POST', headers: { 'content-type': 'application/json', ...(auth ? { authorization: auth } : {}) }, body: '{}' }), env, { vm: v, commit: 'c1' });
  for (const name of ['pause', 'resume', 'cancel', 'change']) {
    const before = v.seen.length;
    // With the key of the construction, and with WORLD_TOKEN: to the VM.
    const keyed = await act(name, `Bearer ${a}`);
    assert.equal(keyed.status, 202, name);
    assert.equal(v.seen.at(-1).path, `/builds/a-far/${name}`);
    assert.equal((await act(name, `Bearer ${token}`)).status, 202, name);
    assert.equal(v.seen.length, before + 2);
    // With no key, a wrong key, another token, or the key of another construction: 403, and nothing goes to the VM.
    for (const auth of [null, 'Bearer ', `Bearer ${'0'.repeat(64)}`, `Bearer ${a.toUpperCase()}`, `Bearer ${'w'.repeat(39)}`, a, `Bearer ${b}`]) {
      const r = await act(name, auth);
      assert.equal(r.status, 403, `${name} ${auth}`);
      assert.match((await r.json()).errors[0].message, /needs the control key/);
    }
    assert.equal(v.seen.length, before + 2);
  }
  // A construction with no key in R2 (another id, or an id that is not an id): 403.
  const other = await handler(req('/builds/z-far/pause', { method: 'POST', headers: { authorization: `Bearer ${a}` } }), env, { vm: v, commit: 'c1' });
  assert.equal(other.status, 403);
  const odd = await handler(req(`/builds/${'x'.repeat(201)}/pause`, { method: 'POST', headers: { authorization: `Bearer ${a}` } }), env, { vm: v, commit: 'c1' });
  assert.equal(odd.status, 403);
  // A short WORLD_TOKEN is not a token.
  const short = { ORDERS: env.ORDERS, WORLD_TOKEN: 'short' };
  assert.equal((await handler(req('/builds/a-far/pause', { method: 'POST', headers: { authorization: 'Bearer short' } }), short, { vm: v, commit: 'c1' })).status, 403);
  // The key and the token do not go to the VM: no request to the VM has them.
  for (const r of v.seen) {
    const text = JSON.stringify(r);
    assert.ok(!text.includes(a) && !text.includes(b) && !text.includes(token), r.path);
    assert.ok(!r.headers.some(([name]) => name === 'authorization'), r.path);
  }
});

test('the other routes', async () => {
  const env = { ORDERS: bucket() };
  const blueprints = await handler(req('/blueprints'), env, { vm: vm(), commit: 'c1' });
  assert.deepEqual(await blueprints.json(), BLUEPRINTS);
  const options = await handler(req('/orders', { method: 'OPTIONS' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(options.status, 204);
  assert.equal(options.headers.get('access-control-allow-methods'), 'GET, POST, OPTIONS');
  assert.equal((await handler(req('/o/x', { method: 'DELETE' }), env, { vm: vm(), commit: 'c1' })).status, 405);
  assert.equal((await handler(req('/nope'), env, { vm: vm(), commit: 'c1' })).status, 404);
});

test('a VM that stops gives 503 with the errors', async () => {
  const stops = async () => {
    throw new Error('the object stopped');
  };
  const r = await handler(req('/m/box.glb'), { ORDERS: bucket() }, { vm: stops, commit: 'c1' });
  assert.equal(r.status, 503);
  assert.equal(r.headers.get('retry-after'), '10');
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  assert.match((await r.json()).errors[0].message, /the builder stopped/);
});
