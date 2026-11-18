// The tests of the store of the orders (order_store.js), with a fake R2
// bucket, and of its program on this computer (scripts/order-store.mjs).
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { orderStore, remoteBucket, s3Bucket, sign } from '../../order_store.js';
import { bucket } from './fakes.js';

const KEY = 'orders/0123456789abcdef0123456789abcdef.json';

// An input of parts that stays open, as the input of a port of the VM;
// ended() is an input that ends after its parts.
const input = (...parts) => new ReadableStream({
  start(c) {
    for (const p of parts) c.enqueue(new TextEncoder().encode(p));
  },
});
const ended = (...parts) => new ReadableStream({
  start(c) {
    for (const p of parts) c.enqueue(new TextEncoder().encode(p));
    c.close();
  },
});

const text = (body) => new Response(body).text();

test('the store of the local edge for a node of a test: get, head and put with the token, over HTTP', async () => {
  const calls = [];
  const items = new Map();
  const fetcher = async (url, { method, body, headers }) => {
    calls.push([method, url, headers.authorization]);
    const key = url.slice('https://edge/store/'.length);
    if (method === 'PUT') items.set(key, body);
    if (key.startsWith('fail')) return new Response('', { status: 500 });
    if (!items.has(key)) return new Response('', { status: 404 });
    return new Response(method === 'GET' ? items.get(key) : null);
  };
  const remote = remoteBucket('https://edge/store', 'T', fetcher);
  assert.equal(await remote.get('orders/a.json'), null);
  assert.equal(await remote.head('orders/a.json'), null);
  await remote.put('orders/a.json', new TextEncoder().encode('{}'));
  assert.equal(await new Response((await remote.get('orders/a.json')).body).text(), '{}');
  assert.deepEqual(await remote.head('orders/a.json'), {});
  assert.deepEqual(calls[0], ['GET', 'https://edge/store/orders/a.json', 'Bearer T']);
  await assert.rejects(remote.get('fail/x'), /the store of the edge: 500/);
});

test('put keeps the order with its length, and get gives it back', async () => {
  const b = bucket();
  const store = orderStore(b);
  // The order comes in parts, and the VM does not end the input: the
  // store reads its length only.
  assert.equal(await text(await store.port(input('{"blue', 'print":"box"}', 'more'), { argv: ['put', KEY, '19'] })), 'ok\n');
  assert.equal(new TextDecoder().decode(b.items.get(KEY)), '{"blueprint":"box"}');
  assert.equal(await text(await store.port(input(), { argv: ['get', KEY] })), '{"blueprint":"box"}');
});

test('a proposal of a new drawing has a key of its own', async () => {
  const store = orderStore(bucket());
  const key = 'proposals/0123456789abcdef0123456789abcdef.json';
  assert.equal(await text(await store.port(input('{}'), { argv: ['put', key, '2'] })), 'ok\n');
  assert.equal(await text(await store.port(input(), { argv: ['get', key] })), '{}');
});

test('a request of a tool has a key of its own', async () => {
  const store = orderStore(bucket());
  const key = 'requests/0123456789abcdef0123456789abcdef.json';
  assert.equal(await text(await store.port(input('{}'), { argv: ['put', key, '2'] })), 'ok\n');
  assert.equal(await text(await store.port(input(), { argv: ['get', key] })), '{}');
});

test('the history of the edits of an order has a key of its own', async () => {
  const store = orderStore(bucket());
  const key = 'history/0123456789abcdef0123456789abcdef.json';
  assert.equal(await text(await store.port(input('[]'), { argv: ['put', key, '2'] })), 'ok\n');
  assert.equal(await text(await store.port(input(), { argv: ['get', key] })), '[]');
});

test('a blueprint in data of a project has a key of its own', async () => {
  const store = orderStore(bucket());
  const key = 'blueprints/0123456789abcdef0123456789abcdef.json';
  assert.equal(await text(await store.port(input('{}'), { argv: ['put', key, '2'] })), 'ok\n');
  assert.equal(await text(await store.port(input(), { argv: ['get', key] })), '{}');
});

test('a part of a model and its recipe have keys of their own, with their types, and has tells if the store has a key', async () => {
  const b = bucket();
  const store = orderStore(b);
  const glb = 'parts/0123456789abcdef0123456789abcdef.glb';
  const recipe = 'parts/0123456789abcdef0123456789abcdef.json';
  assert.equal(await text(await store.port(input('glTF'), { argv: ['put', glb, '4'] })), 'ok\n');
  assert.equal(await text(await store.port(input('{}'), { argv: ['put', recipe, '2'] })), 'ok\n');
  assert.equal(b.types.get(glb), 'model/gltf-binary');
  assert.equal(b.types.get(recipe), 'application/json');
  assert.equal(await text(await store.port(input(), { argv: ['get', glb] })), 'glTF');
  assert.equal(await text(await store.port(input(), { argv: ['has', glb] })), 'yes\n');
  assert.equal(await text(await store.port(input(), { argv: ['has', glb.replace('0123', 'ffff')] })), 'no\n');
  await assert.rejects(store.port(input(), { argv: ['has', 'parts/x.glb'] }));
  await assert.rejects(store.port(input(), { argv: ['put', 'parts/0123456789abcdef0123456789abcdef.png', '2'] }));
});

test('get of an order that the store does not have gives nothing', async () => {
  const store = orderStore(bucket());
  assert.equal(await text(await store.port(input(), { argv: ['get', KEY] })), '');
});

test('a wrong key, length, operation or input is an error', async () => {
  const store = orderStore(bucket());
  const fails = (argv, stdin = input()) => assert.rejects(store.port(stdin, { argv }));
  await fails(['get', '../x']);
  await fails(['get']);
  await fails(['put', KEY, '0']);
  await fails(['put', KEY, 'x']);
  await fails(['put', 'orders/x.json', '2']);
  await fails(['put', 'drawings/0123456789abcdef0123456789abcdef.json', '2']);
  await fails(['put', KEY, '9'], ended('{}'));
  await fails(['delete', KEY]);
});

test('the program on this computer keeps the orders in a folder', () => {
  const dir = mkdtempSync(join(tmpdir(), 'world-orders-'));
  const env = { ...process.env, WORLD_ORDER_DIR: dir };
  const program = new URL('../../scripts/order-store.mjs', import.meta.url).pathname;
  assert.equal(execFileSync(program, ['put', KEY, '2'], { env, input: '{}' }).toString(), 'ok\n');
  assert.equal(execFileSync(program, ['get', KEY], { env }).toString(), '{}');
  assert.equal(execFileSync(program, ['get', KEY.replace('0123', 'ffff')], { env }).toString(), '');
  assert.equal(execFileSync(program, ['has', KEY], { env }).toString(), 'yes\n');
  assert.equal(execFileSync(program, ['has', KEY.replace('0123', 'ffff')], { env }).toString(), 'no\n');
  assert.equal(spawnSync(program, ['get', '../x'], { env }).status, 1);
  assert.equal(spawnSync(program, ['get', KEY], { env: { PATH: process.env.PATH } }).status, 1);
  rmSync(dir, { recursive: true });
});

test('the signature of a request of the S3 API: the example of the documentation of AWS (GET with a range)', async () => {
  const headers = await sign({
    method: 'GET',
    url: new URL('https://examplebucket.s3.amazonaws.com/test.txt'),
    headers: { Range: 'bytes=0-9' },
    payload: new Uint8Array(0),
    date: new Date('2013-05-24T00:00:00Z'),
    keyId: 'AKIAIOSFODNN7EXAMPLE',
    secret: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region: 'us-east-1',
  });
  assert.equal(
    headers.authorization,
    'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
  );
  assert.equal(headers['x-amz-date'], '20130524T000000Z');
  // A query is in the signature, in its order of sort.
  const q = await sign({ method: 'GET', url: new URL('https://h/b?list-type=2&a=1'), headers: {}, payload: new Uint8Array(0), date: new Date(0), keyId: 'k', secret: 's' });
  assert.match(q.authorization, /Credential=k\/19700101\/auto\/s3\/aws4_request/);
});

test('the S3 bucket of a shift: get, head and put of R2, with a signed request; 404 is null; another error raises', async () => {
  const calls = [];
  const items = new Map();
  const fetcher = async (url, init) => {
    calls.push({ url: String(url), method: init.method, auth: init.headers.authorization });
    const key = new URL(url).pathname;
    if (init.method === 'PUT') items.set(key, new TextDecoder().decode(init.body));
    if (key.endsWith('fail')) return new Response('', { status: 500 });
    if (!items.has(key)) return new Response('', { status: 404 });
    return new Response(init.method === 'HEAD' ? null : items.get(key));
  };
  const s3 = s3Bucket({ endpoint: 'https://acc.r2.cloudflarestorage.com', bucket: 'world', keyId: 'id', secret: 'sec' }, fetcher, () => new Date('2026-11-18T00:00:00Z'));
  const key = `parts/${'a'.repeat(32)}.glb`;
  assert.equal(await s3.get(key), null);
  assert.equal(await s3.head(key), null);
  await s3.put(key, new TextEncoder().encode('glTF'));
  assert.equal(await new Response((await s3.get(key)).body).text(), 'glTF');
  assert.deepEqual(await s3.head(key), {});
  assert.equal(calls[2].url, `https://acc.r2.cloudflarestorage.com/world/${key}`);
  assert.match(calls[2].auth, /^AWS4-HMAC-SHA256 Credential=id\/20261118\/auto\/s3\/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=[0-9a-f]{64}$/);
  await assert.rejects(s3.get('fail'), /the S3 store: 500/);
  // (The clock by default.)
  assert.equal(await s3Bucket({ endpoint: 'https://h', bucket: 'b', keyId: 'k', secret: 's' }, fetcher).get('none'), null);
});
