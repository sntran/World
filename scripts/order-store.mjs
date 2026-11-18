#!/usr/bin/env node
// The store of the orders on this computer: the port program of
// World.Orders.Store in development and in the tests. It runs the code
// of the Worker (order_store.js) with a folder in place of the R2
// bucket: WORLD_ORDER_DIR. On the node of a construction shift
// (docs/factory.md, "Construction shifts"), the R2 bucket through its S3
// API, with a token of the bucket: WORLD_R2_ENDPOINT, WORLD_R2_BUCKET,
// WORLD_R2_KEY_ID and WORLD_R2_SECRET. For a shift on one computer,
// WORLD_STORE_URL and WORLD_STORE_TOKEN give the store of the local
// Worker.
//
//   WORLD_ORDER_DIR=tmp/orders scripts/order-store.mjs get orders/HASH.json
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { Readable } from 'node:stream';
import { orderStore, remoteBucket, s3Bucket } from '../order_store.js';

const write = (part) => new Promise((resolve) => process.stdout.write(part, resolve));

const dir = process.env.WORLD_ORDER_DIR;
const url = process.env.WORLD_STORE_URL;
const r2 = process.env.WORLD_R2_ENDPOINT;

const folder = {
  async get(key) {
    const bytes = await readFile(join(dir, key)).catch(() => null);
    return bytes && { body: new Response(bytes).body };
  },
  async head(key) {
    return (await stat(join(dir, key)).catch(() => null)) && {};
  },
  async put(key, bytes) {
    await mkdir(dirname(join(dir, key)), { recursive: true });
    await writeFile(join(dir, key), bytes);
  },
};

// An error ends the port with the exit status 1, as at the edge.
process.stdout.on('error', () => process.exit(1));
try {
  if (!dir && !url && !r2) throw new Error('no WORLD_ORDER_DIR');
  const env = process.env;
  const s3 = { endpoint: r2, bucket: env.WORLD_R2_BUCKET ?? 'world', keyId: env.WORLD_R2_KEY_ID ?? '', secret: env.WORLD_R2_SECRET ?? '' };
  const bucket = r2 ? s3Bucket(s3) : url ? remoteBucket(url, env.WORLD_STORE_TOKEN ?? '') : folder;
  const result = await orderStore(bucket).port(Readable.toWeb(process.stdin), { argv: process.argv.slice(2) });
  for await (const part of result) await write(part);
  process.exit(0);
} catch {
  process.exit(1);
}
