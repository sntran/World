// The tests of the files of MakeHuman for the VM (asset_store.js), with
// a fake of the static files, of the program on this computer
// (scripts/asset-store.mjs), and of the release and the site that they
// need (mix.exs, scripts/site.sh, wrangler.jsonc, worker.js).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { assetStore, PATH, PREFIX } from '../../asset_store.js';

const bytes = (body) => new Response(body).arrayBuffer().then((b) => new Uint8Array(b));
const text = (body) => new Response(body).text();

// The static files: one file of ten bytes, with ranges (206) or not (200).
const assets = ({ ranges = true } = {}) => {
  const calls = [];
  const files = new Map([['clothes/a.png', new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])]]);
  return {
    calls,
    async fetch(request) {
      const name = new URL(request.url).pathname.slice(PREFIX.length);
      const range = request.headers.get('range');
      calls.push([request.method, new URL(request.url).pathname, range]);
      const file = files.get(name);
      if (!file) return new Response('no such file\n', { status: 404 });
      if (request.method === 'HEAD') return new Response(null);
      const m = /^bytes=(\d+)-(\d+)$/.exec(range ?? '');
      if (!m || !ranges) return new Response(file);
      return new Response(file.subarray(Number(m[1]), Number(m[2]) + 1), { status: 206 });
    },
  };
};

const port = (store, ...argv) => store.port(null, { argv });

test('get and has: a file of MakeHuman from the static files of the site', async () => {
  const a = assets();
  const store = assetStore(a);
  assert.deepEqual([...(await bytes(await port(store, 'get', 'clothes/a.png')))], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  assert.equal(await text(await port(store, 'has', 'clothes/a.png')), 'yes\n');
  assert.equal(await text(await port(store, 'has', 'clothes/b.png')), 'no\n');
  await assert.rejects(port(store, 'get', 'clothes/b.png'), /no file clothes\/b.png in the static files: 404/);
  assert.deepEqual(a.calls, [
    ['GET', '/makehuman/clothes/a.png', null],
    ['HEAD', '/makehuman/clothes/a.png', null],
    ['HEAD', '/makehuman/clothes/b.png', null],
    ['GET', '/makehuman/clothes/b.png', null],
  ]);
});

test('range: the parts with a range each (206), or from one read of the whole file (200)', async () => {
  const a = assets();
  const parts = await port(assetStore(a), 'range', 'clothes/a.png', '0', '2', '7', '3', '5', '0');
  assert.deepEqual([...(await bytes(parts))], [0, 1, 7, 8, 9]);
  assert.deepEqual(a.calls, [
    ['GET', '/makehuman/clothes/a.png', 'bytes=0-1'],
    ['GET', '/makehuman/clothes/a.png', 'bytes=7-9'],
  ]);

  const whole = assets({ ranges: false });
  const again = await port(assetStore(whole), 'range', 'clothes/a.png', '0', '2', '7', '3');
  assert.deepEqual([...(await bytes(again))], [0, 1, 7, 8, 9]);
  assert.deepEqual(whole.calls, [['GET', '/makehuman/clothes/a.png', 'bytes=0-1']]);

  // A part out of the file is an error, also in a short answer to a range.
  await assert.rejects(port(assetStore(assets({ ranges: false })), 'range', 'clothes/a.png', '8', '4'), /out of its 10 bytes/);
  await assert.rejects(port(assetStore(assets()), 'range', 'clothes/a.png', '8', '4'), /has 2 of 4 bytes/);
});

test('a path that is not a path of the folder, a count that is not a count, another operation: an error', async () => {
  const store = assetStore(assets());
  for (const name of ['../wrangler.jsonc', 'clothes/../../x', '/etc/passwd', 'a b', '', undefined, '.hidden']) {
    await assert.rejects(port(store, 'get', name), /not a path of the files of MakeHuman/, String(name));
  }
  assert.equal(PATH.test('clothes/elvs_caesar_sandals1.obj.gz'), true);
  await assert.rejects(port(store, 'range', 'clothes/a.png', '-1', '2'), /not a count: -1/);
  await assert.rejects(port(store, 'range', 'clothes/a.png', '1.5', '2'), /not a count: 1.5/);
  await assert.rejects(port(store, 'range', 'clothes/a.png', '1'), /not an operation of the files: range clothes\/a.png 1/);
  await assert.rejects(port(store, 'put', 'clothes/a.png', '3'), /not an operation of the files/);
  await assert.rejects(port(store, 'get'), /not an operation of the files: get/);
});

test('the program on this computer reads a folder, with ranges, and ends with 1 on an error', () => {
  const dir = mkdtempSync(join(tmpdir(), 'asset-store-'));
  try {
    writeFileSync(join(dir, 'base.bin'), Buffer.from([5, 6, 7, 8]));
    const run = (...argv) => spawnSync('node', ['scripts/asset-store.mjs', ...argv], { env: { ...process.env, WORLD_ASSET_DIR: dir } });
    assert.deepEqual([...run('get', 'base.bin').stdout], [5, 6, 7, 8]);
    assert.deepEqual([...run('range', 'base.bin', '1', '2', '3', '1').stdout], [6, 7, 8]);
    assert.equal(run('has', 'base.bin').stdout.toString(), 'yes\n');
    assert.equal(run('has', 'none.bin').stdout.toString(), 'no\n');
    assert.equal(run('get', 'none.bin').status, 1);
    assert.equal(spawnSync('node', ['scripts/asset-store.mjs', 'get', 'base.bin'], { env: { ...process.env, WORLD_ASSET_DIR: '' } }).status, 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('the release of the edge has no priv/makehuman, the site has /makehuman/, and the VM has the port', () => {
  const read = (path) => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
  assert.match(read('mix.exs'), /for dir <- ~w\(models kit makehuman\)/);
  assert.match(read('scripts/site.sh'), /^cp -R priv\/makehuman site\/makehuman$/m);
  assert.match(read('worker.js'), /ASSET_STORE: assetStore\(env\.ASSETS\)/);
  const config = JSON.parse(read('wrangler.jsonc').split('\n').filter((line) => !line.trim().startsWith('//')).join('\n'));
  assert.equal(config.assets.binding, 'ASSETS');
  for (const vars of [config.vars, config.previews.vars]) assert.equal(vars.WORLD_ASSET_STORE, '/env/ASSET_STORE');
});
