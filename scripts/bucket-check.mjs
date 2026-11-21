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
//   node scripts/bucket-check.mjs plan DIR
//     The commits of main in the window, in groups with the same code
//     (DIR/groups.json), and the store of the rebuild (DIR/store: the
//     orders, the blueprints, and the recipes of before the window).
//   node scripts/bucket-check.mjs tasks DIR GROUP
//     The tasks of scripts/bucket-rebuild.exs for a group.
//   node scripts/bucket-check.mjs compare DIR [GROUP...]
//     Each object of the window against its rebuild (DIR/out/GROUP/), in
//     DIR/report.json.
//   node scripts/bucket-check.mjs merge OUT REPORT...
//     The reports of the groups in one report, and the summary of the job.
//   node scripts/bucket-check.mjs quarantine KEY...
//     Each key goes to quarantine/KEY (only an object of the window).
//
// WORLD_URL: the address of the Worker (https://world.mkfifo.workers.dev).
import { execFileSync } from 'node:child_process';
import { cp, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { WINDOW } from '../handler.js';

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
// The parts lists of the site that can give the key of a part or a
// recipe of the window: for the order and the level of each recipe of the
// window, and for each order of the window at each level, the list
// builds/COMMIT/HASH.LEVEL.elements of each commit that the site ran
// (most of them are not there: 404).
export async function siteLists(api, dir, commits, log = console.log) {
  const list = JSON.parse(await readFile(join(dir, 'list.json'), 'utf8'));
  const pairs = new Set();
  for (const o of list) {
    if (o.kind === 'recipe') {
      const recipe = parse(await readFile(join(dir, 'bucket', o.key)).catch(() => null));
      if (/^[0-9a-f]{32}$/.test(recipe?.order ?? '') && ['near', 'mid', 'far'].includes(recipe?.level)) pairs.add(`${recipe.order}.${recipe.level}`);
    }
    if (o.kind === 'order') for (const level of ['near', 'mid', 'far']) pairs.add(`${o.key.slice(7, 39)}.${level}`);
  }
  const keys = [...pairs].flatMap((pair) => commits.map((c) => `builds/${c}/${pair}.elements`)).filter((key) => !list.some((o) => o.key === key));
  let found = 0;
  await each(keys, 8, async (key) => {
    const object = await api.get(key);
    if (!object) return;
    found++;
    await mkdir(dirname(join(dir, 'bucket', key)), { recursive: true });
    await writeFile(join(dir, 'bucket', key), object.bytes);
  });
  log(`bucket: ${found} parts lists of the site of before the window, of ${keys.length} looks`);
  return found;
}

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

const exists = (path) => readFile(path).then(() => true, () => false);
const json = async (path) => JSON.parse(await readFile(path, 'utf8'));

// The commits of main that the site ran in the window: the commit of main
// at the start of the window, and each commit of main after it, to the
// end of the window. git(args): the output of git.
export function deployed(git) {
  const commits = git(['log', '--first-parent', '--format=%H %cI', 'origin/main']).trim().split('\n').map((line) => {
    const [commit, at] = line.split(' ');
    return { commit, at: Date.parse(at) };
  });
  const before = commits.findIndex((c) => c.at <= WINDOW.from);
  const window = commits.filter((c, i) => c.at <= WINDOW.to && (before < 0 || i <= before));
  return window.reverse();
}

// The code of a commit, for the groups: the trees that a build reads.
const code = (git, commit) => git(['rev-parse', ...['lib', 'priv', 'wings', 'mix.exs', 'mix.lock'].map((p) => `${commit}:${p}`)]).trim().replace(/\s+/g, ' ');

// A file of an order of the window: builds/COMMIT/HASH.LEVEL.FILE.
const fileOf = (key) => {
  const [, commit, name] = key.split('/');
  const [hash, level, file] = name.split('.');
  return { key, commit, hash, level, file };
};

// The groups of the commits that the site ran at a time: the commit of
// that time, and the commit before it when the time is less than NEAR
// after a deploy (a build that started before the deploy). times: the
// commits, the oldest first, each with its group.
export const NEAR = 10 * 60_000;
const at = (times, t) => {
  const i = times.findLastIndex((c) => c.at <= t);
  const now = times[Math.max(i, 0)];
  const before = i > 0 && t - now.at < NEAR ? times[i - 1] : null;
  return [...new Set([now.group, before?.group].filter(Boolean))];
};

// The plan of the rebuild: the groups of commits with the same code (the
// oldest first), each with its own work, and the store of the rebuild.
// The work of a group: the files of its commits; each part and recipe of
// the window that the site made while it ran a commit of the group; the
// lists for them (the order and the level of each recipe; for a part with
// no recipe, the parts lists of the group and the orders of its time, at
// each level); and the hashes of the orders and the blueprints.
export async function plan(dir, git) {
  const list = await json(join(dir, 'list.json'));
  const inWindow = new Set(list.map((o) => o.key));
  const onMain = (commit) => {
    try {
      git(['merge-base', '--is-ancestor', commit, 'origin/main']);
      return true;
    } catch {
      return false;
    }
  };
  const files = list.filter((o) => o.kind === 'file').map((o) => fileOf(o.key));
  const times = deployed(git);
  const groups = [];
  const join_ = (commit) => {
    const tree = code(git, commit);
    let group = groups.find((g) => g.code === tree);
    if (!group) groups.push((group = { id: String(groups.length + 1), commit, commits: [], code: tree, files: [], lists: [], parts: [], recipes: [], maps: [] }));
    if (!group.commits.includes(commit)) group.commits.push(commit);
    return group.id;
  };
  for (const c of times) c.group = join_(c.commit);
  for (const f of files) if (!times.some((c) => c.commit === f.commit) && onMain(f.commit)) join_(f.commit);
  const of = (id) => groups.find((g) => g.id === id);
  for (const f of files) {
    const g = groups.find((g) => g.commits.includes(f.commit));
    if (g) g.files.push(f);
  }

  // The store: each order and blueprint, and each recipe of before the window.
  const store = join(dir, 'store');
  for (const prefix of ['orders', 'blueprints', 'parts']) {
    const names = await readdir(join(dir, 'bucket', prefix)).catch(() => []);
    for (const name of names) {
      const key = `${prefix}/${name}`;
      if (prefix === 'parts' && (!name.endsWith('.json') || inWindow.has(key))) continue;
      await mkdir(join(store, prefix), { recursive: true });
      await cp(join(dir, 'bucket', key), join(store, key));
    }
  }

  const add = async (g, hash, level) => {
    const ok = /^[0-9a-f]{32}$/.test(hash ?? '') && ['near', 'mid', 'far'].includes(level) && (await exists(join(store, `orders/${hash}.json`)));
    if (ok && !g.lists.some((c) => c.hash === hash && c.level === level)) g.lists.push({ hash, level });
  };
  const time = (o) => Date.parse(o.uploaded);
  for (const o of list.filter((o) => o.kind === 'recipe')) {
    const recipe = await json(join(dir, 'bucket', o.key)).catch(() => null);
    for (const id of at(times, time(o))) {
      of(id).recipes.push(o.key);
      await add(of(id), recipe?.order, recipe?.level);
    }
  }
  for (const o of list.filter((o) => o.kind === 'part')) {
    const key = o.key.slice(6, 38);
    const recipe = list.some((r) => r.key === `parts/${key}.json`) || (await exists(join(store, `parts/${key}.json`)));
    for (const id of at(times, time(o))) {
      const g = of(id);
      g.parts.push(key);
      if (recipe) continue;
      // (A part with no recipe: a part of a list, or of a construction, that the site made then.)
      for (const f of g.files.filter((f) => f.file === 'elements')) await add(g, f.hash, f.level);
      for (const r of list.filter((r) => r.kind === 'order' && at(times, time(r)).includes(id))) for (const level of ['near', 'mid', 'far']) await add(g, r.key.slice(7, 39), level);
    }
  }
  // The parts lists of the site of the commits of each group: the job
  // makes each one again, and gives each native part and recipe the key
  // of the site at the same place of the list.
  for (const commit of await readdir(join(dir, 'bucket', 'builds')).catch(() => [])) {
    const g = groups.find((g) => g.commits.includes(commit));
    if (!g) continue;
    for (const name of await readdir(join(dir, 'bucket', 'builds', commit))) {
      const [hash, level, file] = name.split('.');
      if (file === 'elements' && (await exists(join(store, `orders/${hash}.json`)))) g.maps.push({ key: `builds/${commit}/${name}`, hash, level });
    }
  }
  const work = {
    groups: groups.map(({ code: _, ...g }) => g),
    hashes: list.filter((o) => o.kind === 'order' || o.kind === 'blueprint').map((o) => o.key),
    preview: files.filter((f) => !groups.some((g) => g.commits.includes(f.commit))).map((f) => f.key),
  };
  await writeFile(join(dir, 'groups.json'), JSON.stringify(work, null, 1));
  return work;
}

// A log of a construction with no times, process ids or measures of the
// run: the events, in order of their text.
export function bare(bytes) {
  const lines = new TextDecoder().decode(bytes).split('\n').filter(Boolean).slice(1);
  return lines.map((line) => {
    const { at: _a, wall: _w, who: _p, ...event } = JSON.parse(line);
    if (event.kind === 'run_done') event.data = {};
    return JSON.stringify(event);
  }).sort().join('\n');
}

// A parts list with no keys and no URLs of its parts: the keys of a build
// of World depend on the folder of the build (World.Elements.version/1,
// docs/factory.md, "The check of the bucket").
export function keyless(bytes) {
  const list = parse(bytes);
  if (!list || !Array.isArray(list.parts)) return null;
  return JSON.stringify({ ...list, parts: list.parts.map(({ key: _k, url: _u, ...p }) => p) });
}

const exact = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)) === 0;
const same = (key, a, b) => (key.endsWith('.log') ? bare(a) === bare(b) : exact(a, b));

// The tasks of a group for scripts/bucket-rebuild.exs.
export async function tasks(dir, id) {
  const work = await json(join(dir, 'groups.json'));
  const g = work.groups.find((g) => g.id === id);
  return { files: g.files, lists: g.lists, parts: g.parts, maps: g.maps, hashes: work.hashes };
}

// The verdicts of the groups in DIR/out/GROUP: each object of the window
// against its rebuild. A verdict: agrees, differs (a rebuild with other
// bytes), none (no rebuild: no recipe, no list, or a commit that is not on
// main), or request (a kind that World does not build: it needs the
// request of the site in the Workers Logs).
export async function compare(dir, ids = null) {
  const list = await json(join(dir, 'list.json'));
  const work = await json(join(dir, 'groups.json'));
  const groups = work.groups.filter((g) => !ids || ids.includes(g.id));
  const hashes = {};
  for (const g of groups) {
    for (const [key, agrees] of Object.entries(await json(join(dir, 'out', g.id, 'hashes.json')).catch(() => ({})))) hashes[key] = hashes[key] === true || agrees;
  }
  const read = (g, key) => readFile(join(dir, 'out', g.id, key)).then((b) => [b], () => []);
  const report = [];
  for (const o of list) {
    let verdict = 'request';
    let note = '';
    if (BUILT.has(o.kind)) {
      const mine = await readFile(join(dir, 'bucket', o.key));
      // (A file of an order only from the group of its commit.)
      const from = o.kind === 'file' ? groups.filter((g) => g.commits.includes(o.key.split('/')[1])) : groups;
      const out = (await Promise.all(from.map((g) => read(g, o.key)))).flat();
      verdict = out.some((b) => same(o.key, b, mine)) ? 'agrees' : out.length ? 'differs' : 'none';
      if (verdict === 'differs' && o.key.endsWith('.elements') && out.some((b) => keyless(b) !== null && keyless(b) === keyless(mine))) {
        verdict = 'agrees';
        note = 'the same list with the keys of the build of the site';
      }
      if (work.preview.includes(o.key)) note = 'a commit that is not on main';
    } else if (o.kind === 'order' || o.kind === 'blueprint') {
      note = hashes[o.key] ? 'its content gives its hash' : 'its content does not give its hash';
    }
    report.push({ ...o, verdict, note });
  }
  return report;
}

// The verdicts of all the groups in one report: for each object, the best
// verdict of a group (agrees, then differs, then none).
export function merge(reports) {
  const rank = { agrees: 0, differs: 1, none: 2, request: 3 };
  const best = new Map();
  for (const o of reports.flat()) {
    const was = best.get(o.key);
    const pick = !was || rank[o.verdict] < rank[was.verdict] ? o : was;
    const gives = [was, o].some((x) => x?.note === 'its content gives its hash');
    best.set(o.key, { ...pick, note: gives ? 'its content gives its hash' : pick.note });
  }
  return [...best.values()].sort((a, b) => (a.key < b.key ? -1 : 1));
}

// The text of the summary of the verdicts.
export function verdicts(report) {
  const kinds = [...new Set(report.map((o) => o.kind))].sort();
  const count = (kind, verdict) => report.filter((o) => o.kind === kind && o.verdict === verdict).length;
  const bad = report.filter((o) => o.verdict === 'differs' || o.verdict === 'none' || o.note.includes('does not'));
  return [
    '| Kind | Objects | Agrees | Differs | No rebuild | Needs a request |',
    '|---|---|---|---|---|---|',
    ...kinds.map((k) => `| ${k} | ${report.filter((o) => o.kind === k).length} | ${count(k, 'agrees')} | ${count(k, 'differs')} | ${count(k, 'none')} | ${count(k, 'request')} |`),
    '',
    bad.length ? 'The objects that do not agree:' : 'Each object that World builds agrees.',
    '',
    ...bad.map((o) => `- \`${o.key}\` (${o.uploaded}): ${o.verdict}${o.note ? `, ${o.note}` : ''}`),
    '',
  ].join('\n');
}

async function main([command, ...args], env = process.env) {
  const git = (a) => execFileSync('git', a, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const api = client(env.WORLD_URL ?? 'https://world.mkfifo.workers.dev', tokens(env, fetch));
  if (command === 'fetch' && args.length === 1) {
    const result = await fetchAll(api, args[0]);
    // (With no main in git, as in a checkout of one commit: no lists of the site.)
    let commits = [];
    try {
      commits = deployed(git).map((c) => c.commit);
    } catch {
      console.log('bucket: no commits of main in git, so no parts lists of the site');
    }
    await siteLists(api, args[0], commits);
    const text = summary(result);
    console.log(text);
    if (env.GITHUB_STEP_SUMMARY) await writeFile(env.GITHUB_STEP_SUMMARY, text, { flag: 'a' });
    return 0;
  }
  if (command === 'plan' && args.length === 1) {
    const work = await plan(args[0], git);
    for (const g of work.groups) console.log(`group ${g.id}: ${g.commits.length} commits, ${g.files.length} files, ${g.parts.length} parts, ${g.lists.length} lists`);
    return 0;
  }
  if (command === 'tasks' && args.length === 2) {
    console.log(JSON.stringify(await tasks(args[0], args[1])));
    return 0;
  }
  if (command === 'compare' && args.length >= 1) {
    // (The groups of this job, or all.)
    const report = await compare(args[0], args.length > 1 ? args.slice(1) : null);
    await writeFile(join(args[0], 'report.json'), JSON.stringify(report, null, 1));
    console.log(verdicts(report));
    return 0;
  }
  if (command === 'merge' && args.length >= 2) {
    const reports = await Promise.all(args.slice(1).map((path) => json(path)));
    const report = merge(reports);
    await writeFile(args[0], JSON.stringify(report, null, 1));
    const text = verdicts(report);
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
  console.error('usage: bucket-check.mjs fetch DIR | plan DIR | tasks DIR GROUP | compare DIR [GROUP...] | merge OUT REPORT... | quarantine KEY...');
  return 2;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = await main(process.argv.slice(2));
