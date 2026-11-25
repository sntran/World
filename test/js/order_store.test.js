// The tests of the store of the orders (order_store.js), with a fake R2
// bucket, and of its program on this computer (scripts/order-store.mjs).
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { orderStore, remoteBucket } from '../../order_store.js';
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

test('the store of the edge for the node of a shift: get, head and put with its pass, over HTTP', async () => {
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

test('a blueprint in data of a project, and a set with an atlas, have keys of their own', async () => {
  const store = orderStore(bucket());
  const set = 'sets/0123456789abcdef0123456789abcdef.json';
  assert.equal(await text(await store.port(input('{}'), { argv: ['put', set, '2'] })), 'ok\n');
  assert.equal(await text(await store.port(input(), { argv: ['get', set] })), '{}');
  const key = 'blueprints/0123456789abcdef0123456789abcdef.json';
  assert.equal(await text(await store.port(input('{}'), { argv: ['put', key, '2'] })), 'ok\n');
  assert.equal(await text(await store.port(input(), { argv: ['get', key] })), '{}');
});

test('a part of a model, its recipe and the mark of its build at the edge have keys of their own, with their types, and has tells if the store has a key', async () => {
  const b = bucket();
  const store = orderStore(b);
  const glb = 'parts/0123456789abcdef0123456789abcdef.glb';
  const recipe = 'parts/0123456789abcdef0123456789abcdef.json';
  const mark = 'parts/0123456789abcdef0123456789abcdef.edge';
  assert.equal(await text(await store.port(input('glTF'), { argv: ['put', glb, '4'] })), 'ok\n');
  assert.equal(await text(await store.port(input('{}'), { argv: ['put', recipe, '2'] })), 'ok\n');
  assert.equal(await text(await store.port(input('1'), { argv: ['put', mark, '1'] })), 'ok\n');
  assert.equal(b.types.get(glb), 'model/gltf-binary');
  assert.equal(b.types.get(recipe), 'application/json');
  assert.equal(b.types.get(mark), 'text/plain');
  assert.equal(await text(await store.port(input(), { argv: ['has', mark] })), 'yes\n');
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
