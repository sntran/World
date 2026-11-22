#!/usr/bin/env node
// The files of MakeHuman on this computer: the port program of
// World.People.Files in the tests. It runs the code of the Worker
// (asset_store.js) with a folder in place of the static files of the
// site: WORLD_ASSET_DIR (priv/makehuman). A request with a range header
// gets 206 and the part, as the static files give it.
//
//   WORLD_ASSET_DIR=priv/makehuman scripts/asset-store.mjs get base.obj.gz
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { assetStore, PREFIX } from '../asset_store.js';

const write = (part) => new Promise((resolve) => process.stdout.write(part, resolve));

const dir = process.env.WORLD_ASSET_DIR;

const folder = {
  async fetch(request) {
    const name = decodeURIComponent(new URL(request.url).pathname.slice(PREFIX.length));
    const bytes = await readFile(join(dir, name)).catch(() => null);
    if (!bytes) return new Response('no such file\n', { status: 404 });
    if (request.method === 'HEAD') return new Response(null, { status: 200 });
    const range = /^bytes=(\d+)-(\d+)$/.exec(request.headers.get('range') ?? '');
    if (!range) return new Response(bytes, { status: 200 });
    return new Response(bytes.subarray(Number(range[1]), Number(range[2]) + 1), { status: 206 });
  },
};

// An error ends the port with the exit status 1, as at the edge.
process.stdout.on('error', () => process.exit(1));
try {
  if (!dir) throw new Error('no WORLD_ASSET_DIR');
  const result = await assetStore(folder).port(Readable.toWeb(process.stdin), { argv: process.argv.slice(2) });
  for await (const part of result) await write(part);
  process.exit(0);
} catch {
  process.exit(1);
}
