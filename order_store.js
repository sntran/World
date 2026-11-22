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
// parts/KEY.glb, the recipe of a part that is not built yet,
// parts/KEY.json, and the mark of a build of a part at the edge,
// parts/KEY.edge (World.Elements.Store.mark/1).
export const KEY = /^((orders|history|proposals|requests|blueprints)\/[0-9a-f]{32}\.json|parts\/[0-9a-f]{32}\.(glb|json|edge))$/;

// The type of the content of a key.
export const type = (value) => (value.endsWith('.glb') ? 'model/gltf-binary' : value.endsWith('.edge') ? 'text/plain' : 'application/json');

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

// The store of the Worker, BASE/KEY (https://world.mkfifo.com/store),
// for the node of a construction shift: it reads the orders and the
// recipes of its parts, and puts the GLB of each part that it builds,
// with the pass of its shift (or the token of the store of a test on one
// computer). The Worker writes R2 with its binding.
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
