// The Worker of https://world.mkfifo.com (docs/factory.md). The static files
// of site/ (the review page and the catalog) go out before the Worker
// runs. The other requests go to handler.js: the orders, with their
// files in R2, and the VM of World for each file that R2 does not have.
//
// The VM is edge.com (scripts/edge.sh): the release of World for the
// WebAssembly runtime of the npm package beam.com, with WORLD_SERVER=true
// (wrangler.jsonc), so World.Service answers on port 4000. The VM runs
// in the Durable Object Beam: one object for the node, whose people build
// a file one time (the next request finds it in R2), and one object for
// each part of a parts list that R2 does not have (objectOf, handler.js),
// so that the parts of a list build at the same time in more than one VM.
import app from './edge.com' with { type: 'bytes' };
import { Beam as BeamObject, serve } from 'beam.com';
import version from './site/version.json';
import { handler, objectOf } from './handler.js';
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

// The object of each request: the node "world", with its people, its
// constructions, its streams and its log (docs/plans/0001, D16), or the
// object of a part (objectOf). A file that R2 has goes out with no VM
// (handler.js).
const node = serve(app, { name: objectOf });

export default {
  fetch(request, env, ctx) {
    const vm = (r) => node.fetch(r, env, ctx);
    return handler(request, env, { vm, commit: version.commit });
  },
};
