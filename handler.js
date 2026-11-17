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
// - GET /p/KEY.glb: a part by its key, from R2 (parts/KEY.glb) with no
//   VM, else the VM builds it from its recipe and keeps it in R2 (202
//   with retry-after while a large part is in work).
// - GET /m/BLUEPRINT.glb (and the other files) ?OPTION=VALUE&color.ROLE=
//   %23rrggbb&joint.NAME=DEGREES&target.LIMB=X,Y,Z: an order in the URL. A list is
//   VALUE,VALUE, and OPTION.FIELD=VALUE is a field of an object.
//
// The Worker gives the VM the header x-world-origin (the start of the
// URLs of an order). When the VM stops (an order that needs more memory
// than the edge has), the answer is 503 with the errors in JSON, and the
// next request starts the VM again.

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

// The Durable Object of a request to the VM (worker.js). A part (GET
// /p/KEY.glb) builds in an object of its own, named from its key: the
// parts of one list build at the same time, each in the memory of its
// own VM (128 MB), and a second request of the same part goes to the
// same object, which builds it one time. Each other request goes to the
// node "world" (its orders, its constructions, its streams and its log).
// (The name of an object has at most 32 characters.)
export function objectOf(request) {
  const part = /^\/p\/([0-9a-f]{32})\.glb$/.exec(new URL(request.url).pathname);
  return part ? `p-${part[1].slice(0, 30)}` : 'world';
}

const headers = (extra = {}) => ({
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type, accept, mcp-protocol-version, mcp-session-id, last-event-id',
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
// headers that the VM reads, and the origin of the URLs. A stream of
// events (text/event-stream) goes back as it comes.
async function forward(request, vm, origin, path) {
  const keep = ['content-type', 'accept', 'mcp-protocol-version', 'last-event-id'].filter((name) => request.headers.has(name));
  const ask = new Headers(keep.map((name) => [name, request.headers.get(name)]));
  ask.set('x-world-origin', origin);
  const body = request.method === 'GET' || request.method === 'HEAD' ? undefined : await request.arrayBuffer();
  const r = await vm(new Request(`http://vm${path}`, { method: request.method, headers: ask, body }));
  const extra = Object.fromEntries(['content-type', 'allow', 'cache-control', 'retry-after'].filter((name) => r.headers.has(name)).map((name) => [name, r.headers.get(name)]));
  return new Response(r.status === 202 && !path.startsWith('/p/') ? null : r.body, { status: r.status, headers: headers(extra) });
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

export async function handler(request, env, options) {
  try {
    return await route(request, env, options);
  } catch {
    return json(503, { errors: [{ path: '', message: 'the builder stopped: the order needs more memory than the edge has, or the VM failed' }] }, { 'retry-after': '10' });
  }
}

async function route(request, env, { vm, commit }) {
  const url = new URL(request.url);
  const path = url.pathname;

  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers({ 'access-control-max-age': '86400' }) });

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
  if (path === '/builds' && request.method === 'POST') return forward(request, vm, url.origin, '/builds');

  // A pause, a resume, a cancel or a change of a construction.
  if (/^\/builds\/[^/]+\/(pause|resume|cancel|change)$/.test(path) && request.method === 'POST') return forward(request, vm, url.origin, path);

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
    return forward(request, vm, url.origin, path);
  }

  if (path === '/events' || path === '/census' || path === '/places' || path.startsWith('/places/') || path.startsWith('/builds/')) return forward(request, vm, url.origin, path + url.search);

  if (path.startsWith('/m/')) {
    const parts = split(path.slice(3));
    if (!parts) return errors(404, 'no such file');
    return model(request, env, vm, commit, url, parts[0], parts[1]);
  }

  return errors(404, 'no such page');
}
