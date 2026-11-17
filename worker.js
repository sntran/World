// The Worker of https://world.mkfifo.com (docs/factory.md). The static files
// of site/ (the review page and the catalog) go out before the Worker
// runs. The other requests go to handler.js: the orders, with their
// files in R2, and the VM of World for each file that R2 does not have.
//
// The VM is edge.com (scripts/edge.sh): the release of World for the
// WebAssembly runtime of the npm package beam.com, with WORLD_SERVER=true
// (wrangler.jsonc), so World.Service answers on port 4000. The VM runs
// in the Durable Object Beam, one object for the node: its people build a
// file one time, and the next request finds it in R2. A part of a parts
// list that R2 does not have builds in one of the builders of the parts
// (objectOf and PARTS, handler.js): the classes Part0 to Part7, each with
// one object and its own VM, so that the parts of a list build at the
// same time in more than one VM.
import app from './edge.com' with { type: 'bytes' };
import { Beam as BeamObject, serve } from 'beam.com';
import version from './site/version.json';
import { PARTS, handler, objectOf } from './handler.js';
import { orderStore } from './order_store.js';
import { logStore, sqlTable } from './log_store.js';

// The VM gets two ports, plain objects with port(), so it needs no other
// Worker: /env/ORDER_STORE, the store of the orders with the R2 bucket
// ORDERS (order_store.js, World.Orders.Store), and /env/LOG_STORE, the
// log of the node in the SQLite of the object (log_store.js,
// World.Log.Store).
export class Beam extends BeamObject {
  constructor(ctx, env) {
    super(ctx, { ...env, ORDER_STORE: orderStore(env.ORDERS), LOG_STORE: logStore(sqlTable(ctx.storage.sql)) });
  }
}

// The builders of the parts: a class for each (wrangler.jsonc), the same VM.
export class Part0 extends Beam {}
export class Part1 extends Beam {}
export class Part2 extends Beam {}
export class Part3 extends Beam {}
export class Part4 extends Beam {}
export class Part5 extends Beam {}
export class Part6 extends Beam {}
export class Part7 extends Beam {}

// The VM of each request (objectOf): the node "world", with its people,
// its constructions, its streams and its log (docs/plans/0001, D16), or a
// builder of the parts. A file that R2 has goes out with no VM
// (handler.js).
const vms = new Map([
  ['world', serve(app, { name: () => 'world' })],
  ...Array.from({ length: PARTS }, (_, i) => [`part${i}`, serve(app, { binding: `PART${i}`, name: () => 'part' })]),
]);

export default {
  fetch(request, env, ctx) {
    const vm = (r) => vms.get(objectOf(r)).fetch(r, env, ctx);
    return handler(request, env, { vm, commit: version.commit });
  },
};
