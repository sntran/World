// The tests of handler.js, with a fake VM and a fake R2 bucket.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handler, orderOf, split } from '../../handler.js';

const HASH = '0123456789abcdef0123456789abcdef';

// A bucket in memory, with the API of R2 that handler.js uses.
function bucket() {
  const items = new Map();
  return {
    items,
    async get(key) {
      if (!items.has(key)) return null;
      const bytes = items.get(key);
      return {
        httpEtag: `"${key.length}-${bytes.byteLength}"`,
        body: bytes,
        async json() { return JSON.parse(new TextDecoder().decode(bytes)); },
      };
    },
    async put(key, value) {
      items.set(key, typeof value === 'string' ? new TextEncoder().encode(value) : new Uint8Array(value));
    },
  };
}

// A VM that checks an order with a blueprint "box", and counts the builds.
function vm() {
  const calls = [];
  const fn = async (request) => {
    const url = new URL(request.url);
    calls.push(url.pathname + url.search);
    if (url.pathname === '/blueprints') return Response.json([{ name: 'box' }]);
    const order = await request.json();
    if (order.blueprint !== 'box') return Response.json({ errors: [{ path: 'blueprint', message: 'no' }] }, { status: 422 });
    if (url.pathname === '/check') return Response.json({ hash: HASH, order: { ...order, full: true } });
    if (order.joints?.bad) return Response.json({ errors: [{ path: 'joints.bad', message: 'no' }] }, { status: 422 });
    return new Response(`${url.searchParams.get('level')} ${url.searchParams.get('file')}`);
  };
  fn.calls = calls;
  return fn;
}

const req = (path, init) => new Request(`https://3d.mkfifo.com${path}`, init);

test('the name and the file of a path', () => {
  assert.deepEqual(split('van.mid.glb')[0], 'van');
  assert.equal(split('van.mid.glb')[1][1], 'mid');
  assert.equal(split('van.glb')[1][1], 'near');
  assert.equal(split('van.receipt.json')[1][2], 'receipt');
  assert.equal(split('.glb'), null);
  assert.equal(split('van.txt'), null);
});

test('an order from a URL', () => {
  const order = orderOf('van', new URLSearchParams('make=ford&color.paint=%23ff0000&joint.hood=50&gear=a,b'));
  assert.deepEqual(order, { blueprint: 'van', options: { make: 'ford', gear: 'a,b' }, colors: { paint: '#ff0000' }, joints: { hood: 50 } });
});

test('POST /orders keeps the full order and gives the URLs of its files', async () => {
  const env = { ORDERS: bucket() };
  const r = await handler(req('/orders', { method: 'POST', body: JSON.stringify({ blueprint: 'box' }) }), env, { vm: vm(), commit: 'c1' });
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  const body = await r.json();
  assert.equal(body.hash, HASH);
  assert.equal(body.files['mid.glb'], `https://3d.mkfifo.com/o/${HASH}.mid.glb`);
  assert.ok(env.ORDERS.items.has(`orders/${HASH}.json`));
});

test('POST /orders gives the errors of a wrong order, and 400 for a body that is not JSON', async () => {
  const env = { ORDERS: bucket() };
  const wrong = await handler(req('/orders', { method: 'POST', body: '{"blueprint":"x"}' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(wrong.status, 422);
  assert.equal((await wrong.json()).errors[0].path, 'blueprint');
  const bad = await handler(req('/orders', { method: 'POST', body: 'nope' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(bad.status, 400);
});

test('GET /o/ builds a file one time, then serves it from R2, with an ETag', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  await env.ORDERS.put(`orders/${HASH}.json`, JSON.stringify({ blueprint: 'box' }));
  const first = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(first.status, 200);
  assert.equal(first.headers.get('content-type'), 'model/gltf-binary');
  assert.equal(first.headers.get('x-xuong-commit'), 'c1');
  assert.equal(await first.text(), 'mid glb');
  const etag = first.headers.get('etag');

  const second = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(await second.text(), 'mid glb');
  assert.equal(v.calls.filter((c) => c.startsWith('/build')).length, 1);

  const same = await handler(req(`/o/${HASH}.mid.glb`, { headers: { 'if-none-match': etag } }), env, { vm: v, commit: 'c1' });
  assert.equal(same.status, 304);

  // A new deploy builds the file again.
  await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c2' });
  assert.equal(v.calls.filter((c) => c.startsWith('/build')).length, 2);

  const receipt = await handler(req(`/o/${HASH}.receipt.json`), env, { vm: v, commit: 'c1' });
  assert.equal(await receipt.text(), 'near receipt');
});

test('GET /o/ of an order that is not in R2, or of a wrong name, is 404', async () => {
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

test('the other routes', async () => {
  const env = { ORDERS: bucket() };
  const blueprints = await handler(req('/blueprints'), env, { vm: vm(), commit: 'c1' });
  assert.deepEqual(await blueprints.json(), [{ name: 'box' }]);
  const options = await handler(req('/orders', { method: 'OPTIONS' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(options.status, 204);
  assert.equal(options.headers.get('access-control-allow-methods'), 'GET, POST, OPTIONS');
  assert.equal((await handler(req('/o/x', { method: 'DELETE' }), env, { vm: vm(), commit: 'c1' })).status, 405);
  assert.equal((await handler(req('/nope'), env, { vm: vm(), commit: 'c1' })).status, 404);
});
