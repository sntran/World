// The tests of handler.js, with a fake VM and a fake R2 bucket.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handler, orderOf, projectOf, split, storeToken, urlKey } from '../../handler.js';
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

test('the project of a request: the name of its token in the secret, or none', () => {
  const env = { WORLD_PROJECT_TOKENS: `vung_tau=${TOKEN}, other=${'o'.repeat(32)},short=abc,Bad Name=${'b'.repeat(40)}` };
  assert.equal(projectOf(auth('/p/x.glb'), env), 'vung_tau');
  assert.equal(projectOf(auth('/p/x.glb', {}, 'o'.repeat(32)), env), 'other');
  assert.equal(projectOf(req('/p/x.glb'), env), null);
  assert.equal(projectOf(auth('/p/x.glb', {}, `${TOKEN}x`), env), null);
  assert.equal(projectOf(auth('/p/x.glb', {}, `${'t'.repeat(39)}u`), env), null);
  // A short token, or a name that is not a name, is never a project; no secret: no project.
  assert.equal(projectOf(auth('/p/x.glb', {}, 'abc'), env), null);
  assert.equal(projectOf(auth('/p/x.glb', {}, 'b'.repeat(40)), env), null);
  assert.equal(projectOf(auth('/p/x.glb'), {}), null);
});

test('the token of the store of a test: the secret, or no store', () => {
  const env = { WORLD_STORE_TOKEN: TOKEN };
  assert.equal(storeToken(auth('/store/x'), env), true);
  assert.equal(storeToken(req('/store/x'), env), false);
  assert.equal(storeToken(auth('/store/x', {}, `${TOKEN}x`), env), false);
  assert.equal(storeToken(auth('/store/x'), {}), false);
  assert.equal(storeToken(auth('/store/x', {}, 'short'), { WORLD_STORE_TOKEN: 'short' }), false);
});

test('/.tcp/ goes to the VM (distributed Erlang: the cookie of the nodes protects it)', async () => {
  const v = async (request) => new Response(`to the VM: ${new URL(request.url).pathname}`, { status: 200 });
  assert.equal(await (await handler(req('/.tcp/4370'), { ORDERS: bucket() }, { vm: v, commit: 'c1' })).text(), 'to the VM: /.tcp/4370');
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
  assert.equal((await handler(req(`/store/${key}`), env, { vm: vm(), commit: 'c1' })).status, 404);
  assert.equal((await handler(auth(`/store/${key}`), { ORDERS: bucket() }, { vm: vm(), commit: 'c1' })).status, 404);
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

test('a part of a project: the VM gets the project; when it wants a shift, the Worker starts one after the answer', async () => {
  const later = [];
  const seen = [];
  const env = { ORDERS: bucket(), WORLD_PROJECT_TOKENS: `vung_tau=${TOKEN}` };
  const v = async (request) => {
    seen.push(request.headers.get('x-world-project'));
    return Response.json({ building: 'x' }, { status: 202, headers: { 'retry-after': '15', 'x-world-shift': 'wanted' } });
  };
  const key = 'c'.repeat(32);
  const r = await handler(auth(`/p/${key}.glb`), env, { vm: v, commit: 'c1', later: (p) => later.push(p) });
  assert.equal(r.status, 202);
  assert.equal(r.headers.get('x-world-shift'), 'wanted');
  // (No WORLD_SHIFT_TOKEN in this env: the start says so.)
  assert.deepEqual(await Promise.all(later), ['no token']);
  // A request with no token: no project; with no later(), nothing breaks.
  await handler(req(`/p/${key}.glb`), env, { vm: v, commit: 'c1' });
  assert.deepEqual(seen, ['vung_tau', null]);
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
  for (const act of ['pause', 'resume', 'cancel', 'change']) {
    await handler(req(`/builds/abc-far/${act}`, { method: 'POST', body: '{}' }), env, { vm: v, commit: 'c1' });
  }
  assert.deepEqual(v.calls.slice(-4), ['/builds/abc-far/pause', '/builds/abc-far/resume', '/builds/abc-far/cancel', '/builds/abc-far/change']);
  assert.equal((await handler(req('/builds/abc-far/stop', { method: 'POST' }), env, { vm: v, commit: 'c1' })).status, 405);
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
