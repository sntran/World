#!/usr/bin/env node
// The check of the bucket after the fault of the listeners of the VM
// (docs/factory.md, "The check of the bucket"), in the job of
// .github/workflows/bucket-check.yml. Only that job can call the routes
// /bucket/ of the Worker (handler.js): it asks GitHub for its ID token.
//
//   node scripts/bucket-check.mjs fetch DIR
//     The objects of the window into DIR/bucket/KEY, with each order,
//     blueprint and recipe that they name (of any time), DIR/list.json
//     (the objects of the window) and DIR/kinds.json (the count of each
//     kind).
//   node scripts/bucket-check.mjs quarantine KEY...
//     Each key goes to quarantine/KEY (only an object of the window).
//
// WORLD_URL: the address of the Worker (https://world.mkfifo.workers.dev).
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const AUDIENCE = 'https://world.mkfifo.com';

// The kind of an object of the bucket, by its key. A kind that World
// builds (a part, the recipe of a part, a file of an order at a level)
// can be built again and compared; each other kind needs the request of
// the site that wrote it.
export function kindOf(key) {
  if (/^parts\/[0-9a-f]{32}\.glb$/.test(key)) return 'part';
  if (/^parts\/[0-9a-f]{32}\.json$/.test(key)) return 'recipe';
  if (/^builds\/[0-9a-f]{40}\/[0-9a-f]{32}\.(near|mid|far)\.[a-z]+$/.test(key)) return 'file';
  const prefix = key.split('/')[0];
  const kinds = { orders: 'order', blueprints: 'blueprint', history: 'history', proposals: 'proposal', requests: 'request', urls: 'url', controls: 'control', shifts: 'shift' };
  return kinds[prefix] ?? 'other';
}

export const BUILT = new Set(['part', 'recipe', 'file']);

// The keys of the objects that an object names: the order of a file or
// of a recipe, the recipe of a part, the blueprint in data of an order.
export function named(key, bytes) {
  const kind = kindOf(key);
  if (kind === 'file') return [`orders/${key.split('/')[2].split('.')[0]}.json`];
  if (kind === 'part') return [key.replace(/\.glb$/, '.json')];
  const data = kind === 'recipe' || kind === 'order' || kind === 'history' ? parse(bytes) : null;
  if (kind === 'recipe' && /^[0-9a-f]{32}$/.test(data?.order ?? '')) return [`orders/${data.order}.json`];
  if (kind === 'order' && /^[0-9a-f]{32}$/.test(data?.blueprint?.hash ?? '')) return [`blueprints/${data.blueprint.hash}.json`];
  return [];
}

function parse(bytes) {
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

// The ID token of the job, new each minute (a token is good for some minutes).
function tokens(env, fetcher) {
  let token = null;
  let at = 0;
  return async () => {
    if (token && Date.now() - at < 60_000) return token;
    const r = await fetcher(`${env.ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${encodeURIComponent(AUDIENCE)}`, { headers: { authorization: `bearer ${env.ACTIONS_ID_TOKEN_REQUEST_TOKEN}` } });
    if (!r.ok) throw new Error(`the ID token of the job: ${r.status}`);
    token = (await r.json()).value;
    at = Date.now();
    return token;
  };
}

// The client of the routes /bucket/ of the Worker.
export function client(base, token, fetcher = fetch, wait = (ms) => new Promise((done) => setTimeout(done, ms))) {
  const call = async (path, method = 'GET') => {
    for (let attempt = 1; ; attempt++) {
      const r = await fetcher(`${base}${path}`, { method, headers: { authorization: `Bearer ${await token()}` } });
      if (r.status < 500 || attempt === 4) return r;
      await wait(2000 * attempt);
    }
  };
  return {
    async list() {
      const objects = [];
      let seen = 0;
      let cursor = '';
      do {
        const r = await call(`/bucket/list?cursor=${encodeURIComponent(cursor)}`);
        if (r.status !== 200) throw new Error(`the list of the bucket: ${r.status} ${await r.text()}`);
        const page = await r.json();
        objects.push(...page.objects);
        seen += page.seen;
        cursor = page.cursor ?? '';
      } while (cursor);
      return { objects, seen };
    },
    async get(key) {
      const r = await call(`/bucket/object?key=${encodeURIComponent(key)}`);
      if (r.status === 404) return null;
      if (r.status !== 200) throw new Error(`the object ${key}: ${r.status}`);
      return { bytes: new Uint8Array(await r.arrayBuffer()), uploaded: r.headers.get('x-world-uploaded') };
    },
    async quarantine(key) {
      const r = await call(`/bucket/quarantine?key=${encodeURIComponent(key)}`, 'POST');
      return { key, status: r.status, body: await r.json().catch(() => null) };
    },
  };
}

// Each item of a list through `fn`, `width` at a time.
async function each(items, width, fn) {
  let next = 0;
  await Promise.all(Array.from({ length: width }, async () => {
    while (next < items.length) await fn(items[next++]);
  }));
}

// The objects of the window, and each object that they name, into DIR.
export async function fetchAll(api, dir, log = console.log) {
  const { objects, seen } = await api.list();
  log(`bucket: ${seen} objects, ${objects.length} with an upload time in the window`);
  const done = new Set();
  const keep = async (key, bytes) => {
    await mkdir(dirname(join(dir, 'bucket', key)), { recursive: true });
    await writeFile(join(dir, 'bucket', key), bytes);
  };
  // (An object of the window, then the objects that it names, of any time.)
  const visit = async (key) => {
    if (done.has(key)) return;
    done.add(key);
    const object = await api.get(key);
    if (!object) return;
    await keep(key, object.bytes);
    for (const more of named(key, object.bytes)) await visit(more);
  };
  await each(objects.map((o) => o.key), 8, visit);
  const kinds = {};
  for (const o of objects) kinds[kindOf(o.key)] = (kinds[kindOf(o.key)] ?? 0) + 1;
  const list = objects.map((o) => ({ ...o, kind: kindOf(o.key) }));
  await writeFile(join(dir, 'list.json'), JSON.stringify(list, null, 1));
  await writeFile(join(dir, 'kinds.json'), JSON.stringify({ seen, window: objects.length, kinds }, null, 1));
  return { seen, list, kinds };
}

// The text of the summary of the job: the count of each kind, and the commits of the files.
export function summary({ seen, list, kinds }) {
  const commits = {};
  for (const o of list) if (o.kind === 'file' || o.kind === 'url') commits[o.key.split('/')[1]] = (commits[o.key.split('/')[1]] ?? 0) + 1;
  const rows = Object.entries(kinds).sort().map(([k, n]) => `| ${k} | ${n} | ${BUILT.has(k) ? 'build again' : 'request in the logs'} |`);
  const crows = Object.entries(commits).sort().map(([c, n]) => `| ${c} | ${n} |`);
  return [
    `The bucket has ${seen} objects; ${list.length} have an upload time in the window.`,
    '',
    '| Kind | Objects | Check |',
    '|---|---|---|',
    ...rows,
    '',
    '| Commit of the files and the URLs | Objects |',
    '|---|---|',
    ...crows,
    '',
  ].join('\n');
}

async function main([command, ...args], env = process.env) {
  const api = client(env.WORLD_URL ?? 'https://world.mkfifo.workers.dev', tokens(env, fetch));
  if (command === 'fetch' && args.length === 1) {
    const result = await fetchAll(api, args[0]);
    const text = summary(result);
    console.log(text);
    if (env.GITHUB_STEP_SUMMARY) await writeFile(env.GITHUB_STEP_SUMMARY, text, { flag: 'a' });
    return 0;
  }
  if (command === 'quarantine' && args.length > 0) {
    let failed = 0;
    for (const key of args) {
      const r = await api.quarantine(key);
      console.log(`${r.status} ${key} ${JSON.stringify(r.body)}`);
      if (r.status !== 200) failed++;
    }
    return failed === 0 ? 0 : 1;
  }
  console.error('usage: bucket-check.mjs fetch DIR | quarantine KEY...');
  return 2;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = await main(process.argv.slice(2));
