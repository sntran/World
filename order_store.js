// The store of the orders: a port program of the VM (BEAM.com, "Ports to
// bindings"). worker.js gives it to the object of the VM as the binding
// ORDER_STORE, with the R2 bucket ORDERS, and scripts/order-store.mjs
// runs it on this computer with a folder. World.Orders.Store is the
// other side. The arguments:
//
// - get KEY: the result is the full order, or nothing when the store has
//   no order of the key (an order is never empty).
// - put KEY LENGTH: the order comes on the input, with this length. The
//   result is "ok".
// - has KEY: the result is "yes" when the store has the key, else "no".
//
// An error ends the port with the exit status 1.

// The keys of World.Orders.Store: orders/HASH.json, the history of the
// edits of an order, history/HASH.json, the proposals of new
// drawings, proposals/HASH.json, the requests of tools of the projects,
// requests/HASH.json, the blueprints in data of the projects,
// blueprints/HASH.json, and the parts of the models (World.Elements):
// parts/KEY.glb, and the recipe of a part that is not built yet,
// parts/KEY.json.
export const KEY = /^((orders|history|proposals|requests|blueprints)\/[0-9a-f]{32}\.json|parts\/[0-9a-f]{32}\.(glb|json))$/;

// The type of the content of a key.
export const type = (value) => (value.endsWith('.glb') ? 'model/gltf-binary' : 'application/json');

const key = (value) => {
  if (!KEY.test(value ?? '')) throw new Error(`not a key of an order: ${value}`);
  return value;
};

const text = (value) => new Response(value).body;

// The first `total` bytes of the input. The VM does not end the input
// of a port, so the length comes in the arguments.
export async function read(stdin, total) {
  const bytes = new Uint8Array(total);
  const reader = stdin.getReader();
  let n = 0;
  while (n < total) {
    const { value, done } = await reader.read();
    if (done) throw new Error(`the input ended after ${n} of ${total} bytes`);
    const part = value.subarray(0, total - n);
    bytes.set(part, n);
    n += part.byteLength;
  }
  reader.releaseLock();
  return bytes;
}

// bucket: an R2 bucket, or an object with the same get, put and head.
export const orderStore = (bucket) => ({
  async port(stdin, { argv: [op, ...args] }) {
    if (op === 'get' && args.length === 1) {
      const object = await bucket.get(key(args[0]));
      return object ? object.body : text('');
    }
    if (op === 'put' && args.length === 2) {
      const length = Number(args[1]);
      if (!Number.isSafeInteger(length) || length <= 0) throw new Error(`not a length: ${args[1]}`);
      await bucket.put(key(args[0]), await read(stdin, length), { httpMetadata: { contentType: type(args[0]) } });
      return text('ok\n');
    }
    if (op === 'has' && args.length === 1) {
      return text((await bucket.head(key(args[0]))) ? 'yes\n' : 'no\n');
    }
    throw new Error(`not an operation of the store: ${[op, ...args].join(' ')}`);
  },
});

// The R2 bucket for the node of a construction shift (docs/factory.md,
// "Construction shifts"), through the S3 API of R2, with a token of the
// bucket only (an access key and its secret): the node reads the orders
// and the recipes, and puts the GLB of each part that it builds. The GLB
// does not go through the edge. s3 is { endpoint, bucket, keyId, secret,
// region }: endpoint is https://ACCOUNT.r2.cloudflarestorage.com, and the
// region of R2 is "auto".
export const s3Bucket = (s3, fetcher = fetch, clock = () => new Date()) => {
  const call = async (method, key, body) => {
    const url = new URL(`${s3.endpoint}/${s3.bucket}/${key}`);
    const bytes = body ? new Uint8Array(body) : new Uint8Array(0);
    const headers = await sign({ method, url, headers: {}, payload: bytes, date: clock(), ...s3 });
    const r = await fetcher(url, { method, headers, body: body ? bytes : undefined });
    if (r.status === 404) return null;
    if (!r.ok) throw new Error(`the S3 store: ${r.status}`);
    return r;
  };
  return {
    async get(key) {
      const r = await call('GET', key);
      return r && { body: r.body };
    },
    async head(key) {
      return (await call('HEAD', key)) && {};
    },
    async put(key, bytes) {
      await call('PUT', key, bytes);
    },
  };
};

const hex = (bytes) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');
const sha256 = async (data) => hex(await crypto.subtle.digest('SHA-256', typeof data === 'string' ? new TextEncoder().encode(data) : data));

async function hmac(key, text) {
  const k = await crypto.subtle.importKey('raw', typeof key === 'string' ? new TextEncoder().encode(key) : key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return crypto.subtle.sign('HMAC', k, new TextEncoder().encode(text));
}

// The headers of a request with AWS Signature Version 4 (the S3 API):
// host, x-amz-date, x-amz-content-sha256 and authorization, with the
// other headers of the request. Each header of the request is signed.
export async function sign({ method, url, headers, payload, date, keyId, secret, region = 'auto', service = 's3' }) {
  const stamp = date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const day = stamp.slice(0, 8);
  const all = { ...headers, host: url.host, 'x-amz-content-sha256': await sha256(payload), 'x-amz-date': stamp };
  const names = Object.keys(all).map((n) => n.toLowerCase()).sort();
  const value = (n) => String(Object.entries(all).find(([k]) => k.toLowerCase() === n)[1]).trim();
  const path = url.pathname.split('/').map((p) => encodeURIComponent(decodeURIComponent(p))).join('/');
  const query = [...url.searchParams].map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).sort().join('&');
  const canonical = [method, path, query, ...names.map((n) => `${n}:${value(n)}`), '', names.join(';'), all['x-amz-content-sha256']].join('\n');
  const scope = `${day}/${region}/${service}/aws4_request`;
  const text = ['AWS4-HMAC-SHA256', stamp, scope, await sha256(canonical)].join('\n');
  let key = await hmac(`AWS4${secret}`, day);
  for (const part of [region, service, 'aws4_request']) key = await hmac(key, part);
  const signature = hex(await hmac(key, text));
  return { ...all, authorization: `AWS4-HMAC-SHA256 Credential=${keyId}/${scope}, SignedHeaders=${names.join(';')}, Signature=${signature}` };
}

// The store of the Worker, BASE/KEY (for a test on one computer, where
// the local edge has no S3 API: docs/factory.md, "A shift on this
// computer"), with the token WORLD_STORE_TOKEN.
export const remoteBucket = (base, token, fetcher = fetch) => {
  const call = async (method, key, body) => {
    const r = await fetcher(`${base}/${key}`, { method, body, headers: { authorization: `Bearer ${token}` } });
    if (r.status === 404) return null;
    if (!r.ok) throw new Error(`the store of the edge: ${r.status}`);
    return r;
  };
  return {
    async get(key) {
      const r = await call('GET', key);
      return r && { body: r.body };
    },
    async head(key) {
      return (await call('HEAD', key)) && {};
    },
    async put(key, bytes) {
      await call('PUT', key, bytes);
    },
  };
};
