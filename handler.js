// The routes of the factory that are not static files (docs/factory.md,
// "The URLs"). The static files of site/ (the catalog, the review page)
// go out before the Worker runs. The VM of World (World.Service) has the
// orders, their store and the MCP server; this file keeps the files that
// the VM built, so that a file goes out of R2 with no VM. handler() takes:
//
// - vm(request, hash): the VM of World. The hash of the order, when there
//   is one, chooses the builder;
// - env.ORDERS: the R2 bucket. builds/COMMIT/FILE is a file that the VM
//   built at the commit COMMIT, and urls/COMMIT/SHA is the hash of the
//   order of a URL /m/ (SHA: the SHA-256 of its path and its query), so
//   that a URL that the factory knows needs no VM, and a new URL needs
//   one request to the VM (the check of the order and the build). The VM keeps the full
//   orders in the same bucket (orders/HASH.json, World.Orders.Store);
// - commit: the commit of the deploy (site/version.json). A new deploy
//   builds each file again at its first request, so a correction of
//   World reaches each order.
//
// The routes:
//
// - GET /blueprints: the blueprints and their options (the VM).
// - POST /blueprints: a blueprint in data of a project (the VM keeps it).
// - POST /orders: an order in JSON (the VM). 200 with the hash, the full
//   order, the URLs of its files and the URL of its replay page; 422
//   with the errors.
// - POST /orders/HASH/edits: small changes to an order (the VM,
//   World.Orders.Edits). 200 with the new hash and its history.
// - POST /sets: a set of orders in JSON (the VM, World.Orders.Set). 200
//   with the hash of the set and each variant (its hash, its order, its
//   files and its lot); 422 with the errors.
// - /mcp: the MCP server (the VM, World.MCP).
// - GET /o/HASH.glb, .mid.glb, .far.glb, .parts.json, .receipt.json,
//   .solids.json, .log.json, .replay.glb: the files of an order of POST /orders. The
//   people of the node build the model (World.Construction): the log
//   tells what each one did, and the replay GLB has a node for each part.
// - GET /o/HASH.elements.json (and .mid.elements.json, .far.elements.json):
//   the parts list of the model at a level (World.Elements): each part
//   with its key and its place. The factory does not join the parts.
// - GET /census: the census of the VM, with the starts of the shifts of
//   the day for all the projects (shift.js, in R2), and the starts and the
//   ends of the VM of the last 7 days with the cause of each end
//   (isolates.js, in R2).
// - GET /p/KEY.glb: a part by its key, from R2 (parts/KEY.glb) with no
//   VM, else the VM builds it from its recipe and keeps it in R2 (202
//   with retry-after while a large part is in work).
// - GET /m/BLUEPRINT.glb (and the other files) ?OPTION=VALUE&color.ROLE=
//   %23rrggbb&joint.NAME=DEGREES&target.LIMB=X,Y,Z: an order in the URL. A list is
//   VALUE,VALUE, and OPTION.FIELD=VALUE is a field of an object.
//
// The construction shifts (docs/factory.md, "Construction shifts" and
// "The secrets"):
//
// - POST /shift/join: a shift (the ID token of the job of shift.yml,
//   oidc.js) joins. The VM gives the name of its node, a cookie of 32
//   random bytes for that node only, and the pass of its shift
//   (World.Shift.Passes).
// - /.tcp/4370: distributed Erlang to the node of the edge (a WebSocket
//   to the listener of DIST_PORT in the VM, 4370 by default, BEAM.com
//   docs/WORKERS.md). Only a node with the cookie of a join connects (the
//   edge has a secret cookie of its own), and BEAM_MAX_WEBSOCKETS limits
//   the connections that are open. Each other path of /.tcp/, and a
//   request that is not a WebSocket, gets 404 at the Worker.
// - /store/KEY: the store for the node of a shift, with its pass. The
//   Worker reads and writes R2 itself, only for a key that the edge gave
//   to that shift (the VM says so), else 403.
//
// The check of the bucket (docs/factory.md, "The check of the bucket"):
//
// - GET /bucket/list?cursor=: the objects of R2 whose upload time is in
//   the window of the fault of the listeners (WINDOW), 1000 objects of
//   the bucket for each request, with the cursor of the next ones.
// - GET /bucket/object?key=KEY: the bytes of an object (any time).
// - POST /bucket/quarantine?key=KEY: an object of the window goes to
//   quarantine/KEY. No route of the site gives quarantine/.
// - With held=1, /bucket/list and /bucket/object are for the objects in
//   quarantine/ (read only): each with its key and its upload time from
//   before the move, to check it again.
//
// Only the job of .github/workflows/bucket-check.yml on main calls them
// (its ID token, oidc.js), else 403. The check ended on 2026-11-21: the
// routes answer 404 unless the variable WORLD_BUCKET_CHECK is "true"
// (wrangler.jsonc).
//
// The Worker gives the VM the header x-world-origin (the start of the
// URLs of an order), and x-world-project for a request of a project of
// the owner (callerOf). When the VM stops (an order that needs more
// memory than the edge has), the answer is 503 with the errors in JSON,
// and the next request starts the VM again.

import { KEY, type } from './order_store.js';
import { AUDIENCE, verify, who } from './oidc.js';
import { STATE, startShift } from './shift.js';
import { isolates, noteEnd, stoppedAnswer } from './isolates.js';

const CACHE = 'public, max-age=300, stale-while-revalidate=86400';

// The suffix of each file: the level and the file of /build.
const FILES = [
  ['.mid.flat.glb', 'mid', 'flat', 'model/gltf-binary'],
  ['.far.flat.glb', 'far', 'flat', 'model/gltf-binary'],
  ['.flat.glb', 'near', 'flat', 'model/gltf-binary'],
  ['.mid.light.glb', 'mid', 'light', 'model/gltf-binary'],
  ['.far.light.glb', 'far', 'light', 'model/gltf-binary'],
  ['.light.glb', 'near', 'light', 'model/gltf-binary'],
  ['.mid.elements.json', 'mid', 'elements', 'application/json'],
  ['.far.elements.json', 'far', 'elements', 'application/json'],
  ['.elements.json', 'near', 'elements', 'application/json'],
  ['.mid.glb', 'mid', 'glb', 'model/gltf-binary'],
  ['.far.glb', 'far', 'glb', 'model/gltf-binary'],
  ['.parts.json', 'near', 'parts', 'application/json'],
  ['.receipt.json', 'near', 'receipt', 'application/json'],
  ['.solids.json', 'near', 'solids', 'application/json'],
  ['.drawing.json', 'near', 'drawing', 'application/json'],
  ['.log.json', 'near', 'log', 'application/json'],
  ['.replay.glb', 'near', 'replay', 'model/gltf-binary'],
  ['.glb', 'near', 'glb', 'model/gltf-binary'],
];

const HASH = /^[0-9a-f]{32}$/;
const PART = /^[0-9a-f]{32}$/;

// The name of a project: letters a to z, digits, _, . and -.
const PROJECT = /^[a-z0-9_.-]{1,100}$/;

// The caller of a request, from "authorization: Bearer ...", or null:
//
// - an ID token of GitHub Actions (oidc.js): { kind: 'shift' | 'request',
//   project, claims } for a job of shift.yml or shift-request.yml (the
//   project in the header x-world-project), or { kind: 'project',
//   project, claims } for a job of a repository of the owner (the name of
//   the repository is the project);
// - the secret WORLD_TOKEN (32 characters or more), for a caller that is
//   not a job of GitHub Actions: { kind: 'token', project }, with the
//   project in x-world-project.
//
// A part of an order of a project that does not fit the edge waits for a
// construction shift (World.Labour); a public order gets an error.
export async function callerOf(request, env, check = verify) {
  const auth = request.headers.get('authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return null;
  const token = auth.slice(7);
  const named = request.headers.get('x-world-project') ?? '';
  const project = PROJECT.test(named) ? named : null;
  if (token.split('.').length === 3) {
    const claims = await check(token, { audience: env.WORLD_AUDIENCE ?? AUDIENCE });
    const job = who(claims, env);
    if (!job) return null;
    return job.kind === 'project' ? { ...job, claims } : { ...job, project, claims };
  }
  const secret = env.WORLD_TOKEN;
  if (typeof secret === 'string' && secret.length >= 32 && same(auth, `Bearer ${secret}`) && project) return { kind: 'token', project };
  return null;
}

// The store of the Worker for a node on a computer (a test of a shift on
// one computer, docs/factory.md): the secret WORLD_STORE_TOKEN (32
// characters or more) in "authorization: Bearer TOKEN", for each key. The
// site has no such secret.
export function storeToken(request, env) {
  const token = env.WORLD_STORE_TOKEN;
  if (typeof token !== 'string' || token.length < 32) return false;
  return same(request.headers.get('authorization') ?? '', `Bearer ${token}`);
}

// The control key of a construction (docs/factory.md, "The control key"):
// POST /builds gives it only to the caller that opened the construction
// (the VM says so in x-world-started), in the body of its answer, not in
// a header, so no log of the requests has it. It is 32 random bytes in
// hex. R2 keeps only its SHA-256 at controls/ID: no key of the VM can
// read it or write it (order_store.js, KEY). The key does not go to the
// VM, so it is not in /events, /census, GET /builds/ID, or the log of the
// node.
const BUILD = /^[A-Za-z0-9_.-]{1,200}$/;
const CONTROL = /^[0-9a-f]{64}$/;
const controlKey = (id) => `controls/${id}`;

async function sha256(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// A pause, a resume, a cancel or a change of the construction ID: its
// control key, or the secret WORLD_TOKEN (32 characters or more), in
// "authorization: Bearer ...".
export async function controls(request, env, id) {
  const auth = request.headers.get('authorization') ?? '';
  const secret = env.WORLD_TOKEN;
  if (typeof secret === 'string' && secret.length >= 32 && same(auth, `Bearer ${secret}`)) return true;
  const key = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!CONTROL.test(key) || !BUILD.test(id)) return false;
  const stored = await env.ORDERS.get(controlKey(id));
  return stored ? same(await stored.text(), await sha256(key)) : false;
}

// POST /builds: the answer of the VM, and the control key of a new
// construction: "control" in the JSON of a 202, or a first event
// "control" in a stream. When R2 does not keep its hash, the answer has
// no key (only WORLD_TOKEN controls that construction).
async function builds(request, env, vm, origin) {
  const r = await ask(request, vm, origin, '/builds');
  const out = answer(r, '/builds');
  const id = r.headers.get('x-world-started');
  if (!id || !BUILD.test(id) || r.status >= 300) return out;
  const key = [...crypto.getRandomValues(new Uint8Array(32))].map((b) => b.toString(16).padStart(2, '0')).join('');
  try {
    await env.ORDERS.put(controlKey(id), await sha256(key));
  } catch {
    return out;
  }
  const extra = { ...Object.fromEntries(out.headers), 'cache-control': 'no-store' };
  if ((out.headers.get('content-type') ?? '').startsWith('text/event-stream')) {
    return new Response(prepend(`event: control\ndata: ${JSON.stringify({ build: id, control: key })}\n\n`, out.body), { status: out.status, headers: extra });
  }
  const body = await out.json().catch(() => ({ build: id }));
  return new Response(JSON.stringify({ ...body, control: key }), { status: out.status, headers: extra });
}

// A stream with `text` before the body.
function prepend(text, body) {
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();
  writer
    .write(new TextEncoder().encode(text))
    .then(() => {
      writer.releaseLock();
      return body ? body.pipeTo(writable) : writable.close();
    })
    .catch(() => {});
  return readable;
}

// Two texts, compared in a time that does not depend on where they differ.
function same(a, b) {
  const [x, y] = [new TextEncoder().encode(a), new TextEncoder().encode(b)];
  let diff = x.length ^ y.length;
  for (let i = 0; i < y.length; i++) diff |= (x[i] ?? 0) ^ y[i];
  return diff === 0;
}

// The store for the node of a shift: it reads the orders and the
// recipes of the parts, and puts the GLB of each part that it builds (the
// GLB goes to R2 here, not through the VM of the edge).
async function store(request, env, key) {
  if (!KEY.test(key)) return errors(404, 'no such key');
  if (request.method === 'GET') {
    const object = await env.ORDERS.get(key);
    return object ? new Response(object.body, { headers: { 'content-type': type(key) } }) : errors(404, 'no such key');
  }
  if (request.method === 'HEAD') return new Response(null, { status: (await env.ORDERS.head(key)) ? 200 : 404 });
  if (request.method === 'PUT') {
    const bytes = await request.arrayBuffer();
    if (bytes.byteLength === 0) return errors(400, 'an empty body');
    await env.ORDERS.put(key, bytes, { httpMetadata: { contentType: type(key) } });
    return new Response('ok\n');
  }
  return errors(405, 'the method is not allowed');
}

const headers = (extra = {}) => ({
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type, accept, authorization, mcp-protocol-version, mcp-session-id, last-event-id',
  ...extra,
});

const json = (status, body, extra = {}) =>
  new Response(JSON.stringify(body), { status, headers: headers({ 'content-type': 'application/json', ...extra }) });

const errors = (status, message) => json(status, { errors: [{ path: '', message }] });

// The name and the file of a path: "ford.mid.glb" is ["ford", FILES[0]].
export function split(name) {
  for (const file of FILES) {
    if (name.endsWith(file[0]) && name.length > file[0].length) return [name.slice(0, -file[0].length), file];
  }
  return null;
}

// The order of a URL /m/BLUEPRINT.EXT?...: color.ROLE, joint.NAME and
// target.LIMB (a point X,Y,Z: the order has targets only with one), and
// the options. OPTION.FIELD is a field of an option that is an object
// (origin.asian=1).
export function orderOf(blueprint, params) {
  const order = { blueprint, options: {}, colors: {}, joints: {} };
  for (const [key, value] of params) {
    if (key.startsWith('color.')) order.colors[key.slice(6)] = value;
    else if (key.startsWith('joint.')) order.joints[key.slice(6)] = Number(value);
    else if (key.startsWith('target.')) (order.targets ??= {})[key.slice(7)] = value.split(',').map(Number);
    else if (key.includes('.')) {
      const [option, field] = key.split('.', 2);
      const object = typeof order.options[option] === 'object' ? order.options[option] : {};
      order.options[option] = { ...object, [field]: value };
    } else order.options[key] = value;
  }
  return order;
}

// A request of the client to the VM, with its method, its body, the
// headers that the VM reads, the origin of the URLs, and the project of
// a project token. A stream of events (text/event-stream) goes back as
// it comes.
async function forward(request, vm, origin, path, project = null) {
  return answer(await ask(request, vm, origin, path, project), path);
}

// The request to the VM: only some headers of the caller (no
// authorization: no token and no control key goes to the VM).
async function ask(request, vm, origin, path, project = null) {
  const keep = ['content-type', 'accept', 'mcp-protocol-version', 'last-event-id'].filter((name) => request.headers.has(name));
  const asked = new Headers(keep.map((name) => [name, request.headers.get(name)]));
  asked.set('x-world-origin', origin);
  if (project) asked.set('x-world-project', project);
  const body = request.method === 'GET' || request.method === 'HEAD' ? undefined : await request.arrayBuffer();
  return vm(new Request(`http://vm${path}`, { method: request.method, headers: asked, body }));
}

// The answer of the VM to the caller, with only some of its headers. A
// 202 of a file has no body; a 202 of a part or of POST /builds has its
// body (the id of the construction, the URL of its events).
function answer(r, path) {
  const extra = Object.fromEntries(['content-type', 'allow', 'cache-control', 'retry-after', 'x-world-shift'].filter((name) => r.headers.has(name)).map((name) => [name, r.headers.get(name)]));
  const body = r.status === 202 && !path.startsWith('/p/') && path !== '/builds' ? null : r.body;
  return new Response(body, { status: r.status, headers: headers(extra) });
}

const buildKey = (commit, hash, level, kind) => `builds/${commit}/${hash}.${level}.${kind}`;

// The key of the hash of the order of a URL /m/ (its path and its query).
export async function urlKey(commit, url) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(url.pathname + url.search));
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return `urls/${commit}/${hex}`;
}

const failure = (r) => new Response(r.body, { status: r.status, headers: headers({ 'content-type': 'application/json' }) });

// A file of an order of POST /orders: from R2, else from the VM, which
// reads the order from its store by the hash (then into R2).
async function file(request, env, vm, commit, hash, [, level, kind, type]) {
  const key = buildKey(commit, hash, level, kind);
  let object = await env.ORDERS.get(key);
  // (A model of the catalog with no change: its file of the site, with no build.)
  const catalog = object ? null : await catalogFile(env, hash, level, kind);
  if (catalog) {
    await env.ORDERS.put(key, catalog, { httpMetadata: { contentType: type } });
    object = await env.ORDERS.get(key);
  }
  if (!object) {
    const r = await vm(new Request(`http://vm/build?level=${level}&file=${kind}&hash=${hash}`, { method: 'POST' }), hash);
    // (A parts list of a large model that builds on: ask again after retry-after.)
    if (r.status === 202) return json(202, await r.json(), { 'retry-after': r.headers.get('retry-after') ?? '15' });
    if (r.status !== 200) return failure(r);
    await env.ORDERS.put(key, await r.arrayBuffer(), { httpMetadata: { contentType: type } });
    object = await env.ORDERS.get(key);
  }
  return send(request, object, commit, hash, type);
}

// The path of the file of the catalog of an order, or null. An order of a
// model of the catalog with no change has the blueprint catalog, only the
// name of the model in its options, and no color and no pose: its files
// at each level are the files of priv/models, in the static files of the
// site (/models/, scripts/site.sh). mix world.build checks that each of
// them is the build of the order at the same commit, as a clone builds
// it (mix world.order). So the edge gives them with no build, also to a
// public caller, also when the build needs more memory than the edge has.
export function catalogPath(order, level, kind) {
  if (kind !== 'glb' || order?.blueprint !== 'catalog') return null;
  const empty = (value) => value == null || (typeof value === 'object' && Object.keys(value).length === 0);
  const other = Object.keys(order).some((k) => !['blueprint', 'options', 'colors', 'joints'].includes(k));
  const name = order.options?.name;
  if (other || Object.keys(order.options ?? {}).length !== 1 || !/^[a-z0-9_]+$/.test(name ?? '')) return null;
  if (!empty(order.colors) || !empty(order.joints)) return null;
  return `/models/${name}${level === 'near' ? '' : `.${level}`}.glb`;
}

// The bytes of the file of the catalog of the order HASH at a level, from
// the static files of the site (env.ASSETS), or null.
async function catalogFile(env, hash, level, kind) {
  if (!env.ASSETS || kind !== 'glb') return null;
  const stored = await env.ORDERS.get(`orders/${hash}.json`);
  const order = stored ? await stored.json().catch(() => null) : null;
  const path = catalogPath(order, level, kind);
  if (!path) return null;
  const r = await env.ASSETS.fetch(new Request(`https://assets${path}`));
  return r.ok ? r.arrayBuffer() : null;
}

// A file of a URL /m/: from R2 when the factory knows the URL (no VM),
// else one request to the VM, which checks the order of the URL and
// builds the file, and gives the hash of the order (x-world-order). The
// file and the hash of the URL go into R2.
async function model(request, env, vm, commit, url, blueprint, [, level, kind, type]) {
  const key = await urlKey(commit, url);
  const known = await env.ORDERS.get(key);
  if (known) {
    const { hash } = await known.json();
    const object = await env.ORDERS.get(buildKey(commit, hash, level, kind));
    if (object) return send(request, object, commit, hash, type);
  }
  const body = JSON.stringify(orderOf(blueprint, url.searchParams));
  // The builder of the URL: the first digit of its SHA.
  const r = await vm(new Request(`http://vm/build?level=${level}&file=${kind}`, { method: 'POST', body }), key.slice(-64));
  if (r.status !== 200) return failure(r);
  const hash = r.headers.get('x-world-order');
  await env.ORDERS.put(buildKey(commit, hash, level, kind), await r.arrayBuffer(), { httpMetadata: { contentType: type } });
  if (!known) await env.ORDERS.put(key, JSON.stringify({ hash }), { httpMetadata: { contentType: 'application/json' } });
  return send(request, await env.ORDERS.get(buildKey(commit, hash, level, kind)), commit, hash, type);
}

// A file of R2, with its ETag (304 for the same ETag).
function send(request, object, commit, hash, type) {
  const etag = object.httpEtag;
  const extra = { etag, 'cache-control': CACHE, 'x-world-commit': commit, 'x-world-order': hash };
  if (request.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers: headers(extra) });
  return new Response(object.body, { headers: headers({ 'content-type': type, ...extra }) });
}

// A part of R2: its key is a hash of its data, so it does not change.
function part(request, object, key) {
  const extra = { etag: `"${key}"`, 'cache-control': 'public, max-age=31536000, immutable' };
  if (request.headers.get('if-none-match') === extra.etag) return new Response(null, { status: 304, headers: headers(extra) });
  return new Response(object.body, { headers: headers({ 'content-type': 'model/gltf-binary', ...extra }) });
}

// The window of the fault of the listeners of the VM (docs/factory.md):
// from the first deploy with the open listeners to the delete of the
// Previews (I said at 00:54:35 UTC that I had deleted them).
export const WINDOW = { from: Date.parse('2026-11-18T20:10:00Z'), to: Date.parse('2026-11-21T00:55:00Z') };
export const QUARANTINE = 'quarantine/';
const OBJECT = /^(?!quarantine\/)(?!.*\.\.)[A-Za-z0-9_.\/-]{1,512}$/;
const inWindow = (date) => date instanceof Date && date.getTime() >= WINDOW.from && date.getTime() <= WINDOW.to;
const noStore = { 'cache-control': 'no-store' };

// The check of the bucket: only the job of bucket-check.yml on main.
async function bucket(request, env, check, url) {
  const caller = await callerOf(request, env, check);
  if (caller?.kind !== 'check') return errors(403, 'only the job of bucket-check.yml on main checks the bucket');
  const path = url.pathname;
  const held = url.searchParams.get('held') === '1';
  if (path === '/bucket/list' && request.method === 'GET') {
    const cursor = url.searchParams.get('cursor') || undefined;
    if (held) {
      // (The objects in quarantine/, with the upload time and the ETag that they had before the move.)
      const page = await env.ORDERS.list({ limit: 1000, cursor, prefix: QUARANTINE, include: ['customMetadata'] });
      const objects = page.objects.map((o) => ({ key: o.key.slice(QUARANTINE.length), size: o.size, uploaded: o.customMetadata?.uploaded ?? o.uploaded.toISOString(), etag: o.customMetadata?.etag ?? o.etag }));
      return json(200, { objects, seen: page.objects.length, cursor: page.truncated ? page.cursor : null }, noStore);
    }
    const page = await env.ORDERS.list({ limit: 1000, cursor });
    const objects = page.objects.filter((o) => inWindow(o.uploaded)).map((o) => ({ key: o.key, size: o.size, uploaded: o.uploaded.toISOString(), etag: o.etag }));
    return json(200, { objects, seen: page.objects.length, cursor: page.truncated ? page.cursor : null }, noStore);
  }
  const read = path === '/bucket/object' && request.method === 'GET';
  if (!read && !(path === '/bucket/quarantine' && request.method === 'POST' && !held)) return errors(404, 'no such page');
  const key = url.searchParams.get('key') ?? '';
  if (!OBJECT.test(key)) return errors(400, 'not a key of the bucket');
  if (held) {
    const object = await env.ORDERS.get(QUARANTINE + key);
    if (!object) return errors(404, 'no such key in quarantine/');
    const uploaded = object.customMetadata?.uploaded ?? object.uploaded.toISOString();
    return new Response(object.body, { headers: headers({ 'content-type': 'application/octet-stream', 'x-world-uploaded': uploaded, ...noStore }) });
  }
  const object = await env.ORDERS.get(key);
  if (!object) return errors(404, 'no such key');
  if (read) return new Response(object.body, { headers: headers({ 'content-type': 'application/octet-stream', 'x-world-uploaded': object.uploaded.toISOString(), ...noStore }) });
  if (!inWindow(object.uploaded)) return errors(409, 'the upload time of the object is not in the window of the fault');
  // (A copy first, only when quarantine/ does not have the key; then the delete of the object.)
  const meta = { uploaded: object.uploaded.toISOString(), etag: object.etag };
  const put = await env.ORDERS.put(QUARANTINE + key, await object.arrayBuffer(), { httpMetadata: object.httpMetadata, customMetadata: meta, onlyIf: { etagDoesNotMatch: '*' } });
  if (!put) return errors(409, 'quarantine/ has this key already');
  await env.ORDERS.delete(key);
  return json(200, { moved: key, to: QUARANTINE + key, ...meta }, noStore);
}

// GET /census: the census of the VM, and the starts of the shifts of the
// day (UTC) for all the projects (shift.js): { day, starts, limit, last }.
// The state of the starts is in R2, not in the VM.
async function census(request, env, vm, origin, path) {
  const r = await ask(request, vm, origin, path);
  if (r.status !== 200 || !(r.headers.get('content-type') ?? '').startsWith('application/json')) return answer(r, path);
  const body = await r.json();
  const object = await env.ORDERS.get(STATE);
  const state = object ? await object.json() : { day: '', count: 0, last: 0 };
  const day = new Date().toISOString().slice(0, 10);
  const starts = state.day === day ? state.count : 0;
  body.shifts = { day, starts, limit: Number(env.WORLD_SHIFTS_A_DAY ?? '6'), last: state.last ? new Date(state.last).toISOString() : null };
  body.isolates = await isolates(env.ORDERS).catch(() => null);
  return json(200, body, { 'cache-control': 'no-store' });
}

// The join of a shift: a job of shift.yml (its ID token), or the token
// of the store of a test. The VM gives its node, its cookie and its pass.
async function join(request, env, vm, check) {
  const caller = await callerOf(request, env, check);
  let run = null;
  if (caller?.kind === 'shift') run = `${caller.claims.run_id}-${caller.claims.run_attempt}`;
  else if (storeToken(request, env)) run = 'test';
  if (!run) return errors(401, 'only a construction shift joins');
  const r = await vm(new Request('http://vm/shift/join', { method: 'POST', headers: { 'x-world-shift-run': run } }));
  return new Response(r.body, { status: r.status, headers: headers({ 'content-type': 'application/json', 'cache-control': 'no-store' }) });
}

// The store with the pass of a shift (64 hex digits): only a key that the
// edge gave to that shift (the VM checks it with the SHA-256 of the pass),
// else 403. The token of the
// store of a test takes each key.
async function shiftStore(request, env, vm, key) {
  if (storeToken(request, env)) return store(request, env, key);
  const pass = (request.headers.get('authorization') ?? '').replace(/^Bearer /, '');
  if (!/^[0-9a-f]{64}$/.test(pass) || !KEY.test(key)) return errors(403, 'no pass for this key');
  const access = request.method === 'PUT' ? 'write' : 'read';
  // (Only the SHA-256 of the pass goes to the VM: the Workers Logs keep the headers of a request to the VM.)
  const r = await vm(new Request(`http://vm/shift/allowed?key=${encodeURIComponent(key)}&access=${access}`, { headers: { 'x-world-shift-pass-hash': await sha256(pass) } }));
  return r.status === 204 ? store(request, env, key) : errors(403, 'the edge did not give this key to this shift');
}

// A WebSocket to the port of the distribution of the VM (DIST_PORT, 4370
// by default), with the same digits as the port: the only path of /.tcp/
// that goes to the VM.
export function distribution(request, env) {
  const port = String(env.DIST_PORT ?? '4370');
  const upgrade = request.headers.get('upgrade')?.toLowerCase() === 'websocket';
  return upgrade && new URL(request.url).pathname === `/.tcp/${port}`;
}

export async function handler(request, env, options) {
  // (A request to the VM that fails: its isolate ended, or the VM stopped
  // itself. The record keeps the time and the word of the cause.)
  const note = (cause) => {
    const done = noteEnd(env.ORDERS, cause).catch(() => {});
    if (options.later) options.later(done);
  };
  const vm = async (...args) => {
    let response;
    try {
      response = await options.vm(...args);
    } catch (e) {
      note(e);
      throw e;
    }
    if (await stoppedAnswer(response)) note('stopped');
    return response;
  };
  try {
    return await route(request, env, { ...options, vm });
  } catch {
    return json(503, { errors: [{ path: '', message: 'the builder stopped: the order needs more memory than the edge has, or the VM failed' }] }, { 'retry-after': '10' });
  }
}

// The options: vm, commit, later(promise), the work after the answer
// (ctx.waitUntil of the Worker: the start of a shift), and verify (the
// check of an ID token, oidc.js; another one in the tests).
async function route(request, env, { vm, commit, later = () => {}, verify: check = verify }) {
  const url = new URL(request.url);
  const path = url.pathname;

  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers({ 'access-control-max-age': '86400' }) });

  // The node of a shift: distributed Erlang to the node of the edge (the
  // cookie of its join protects it), its join, and the store.
  if (path.startsWith('/.tcp/')) return distribution(request, env) ? vm(request) : errors(404, 'no such page');
  if (path === '/shift/join' && request.method === 'POST') return join(request, env, vm, check);
  if (path.startsWith('/store/')) return shiftStore(request, env, vm, path.slice(7));
  if (path.startsWith('/bucket/')) return env.WORLD_BUCKET_CHECK === 'true' ? bucket(request, env, check, url) : errors(404, 'no such page');

  if (path === '/blueprints' && request.method === 'GET') {
    const r = await vm(new Request('http://vm/blueprints'));
    return new Response(r.body, { status: r.status, headers: headers({ 'content-type': 'application/json', 'cache-control': CACHE }) });
  }

  if (path === '/orders' && request.method === 'POST') return forward(request, vm, url.origin, '/orders');

  // The edits of an order that the VM has.
  if (/^\/orders\/[0-9a-f]{32}\/edits$/.test(path) && request.method === 'POST') return forward(request, vm, url.origin, path);

  if (path === '/blueprints' && request.method === 'POST') return forward(request, vm, url.origin, '/blueprints');

  if (path === '/sets' && request.method === 'POST') return forward(request, vm, url.origin, '/sets');

  if (path === '/mcp') return forward(request, vm, url.origin, '/mcp');

  // The constructions of the people of the node, and the streams.
  if (path === '/builds' && request.method === 'POST') return builds(request, env, vm, url.origin);

  // A pause, a resume, a cancel or a change of a construction: with its
  // control key or WORLD_TOKEN, else 403.
  const act = path.match(/^\/builds\/([^/]+)\/(pause|resume|cancel|change)$/);
  if (act && request.method === 'POST') {
    if (!(await controls(request, env, act[1]))) return errors(403, 'a pause, a resume, a cancel or a change needs the control key of the construction');
    return forward(request, vm, url.origin, path);
  }

  if (request.method !== 'GET' && request.method !== 'HEAD') return errors(405, 'the method is not allowed');

  if (path.startsWith('/o/')) {
    const parts = split(path.slice(3));
    if (!parts || !HASH.test(parts[0])) return errors(404, 'no such file');
    return file(request, env, vm, commit, parts[0], parts[1]);
  }

  // A part of a model by its key: from R2 with no VM, else the VM builds
  // it from its recipe and keeps it in R2 (World.Elements).
  if (path.startsWith('/p/')) {
    const key = path.slice(3).replace(/\.glb$/, '');
    if (!PART.test(key) || !path.endsWith('.glb')) return errors(404, 'no such part');
    const object = await env.ORDERS.get(`parts/${key}.glb`);
    if (object) return part(request, object, key);
    const project = (await callerOf(request, env, check))?.project ?? null;
    const r = await forward(request, vm, url.origin, path, project);
    // (Only a project starts a shift: a request with no token does not use
    // the starts of the day. A project can ask for a shorter shift:
    // x-world-shift-hours.)
    const hours = project ? request.headers.get('x-world-shift-hours') : null;
    if (project && r.headers.get('x-world-shift') === 'wanted') later(startShift(env, commit, { hours }));
    if (r.status !== 204) return r;
    // (A node of a shift built the part and put it in R2: it goes out of R2, not through the VM.)
    const built = await env.ORDERS.get(`parts/${key}.glb`);
    return built ? part(request, built, key) : json(202, { building: key }, { 'retry-after': '1' });
  }

  if (path === '/census') return census(request, env, vm, url.origin, path + url.search);

  if (path === '/events' || path === '/places' || path.startsWith('/places/') || path.startsWith('/builds/')) return forward(request, vm, url.origin, path + url.search);

  if (path.startsWith('/m/')) {
    const parts = split(path.slice(3));
    if (!parts) return errors(404, 'no such file');
    return model(request, env, vm, commit, url, parts[0], parts[1]);
  }

  return errors(404, 'no such page');
}
