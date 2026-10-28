// The Worker of https://3d.mkfifo.com (docs/factory.md). The static files
// of site/ (the review page and the catalog) go out before the Worker
// runs. The other requests go to handler.js: the orders, with their
// files in R2, and the VM of Xưởng for each file that R2 does not have.
//
// The VM is edge.com (scripts/edge.sh): the release of Xưởng for the
// WebAssembly runtime of the npm package beam.com, with XUONG_SERVER=true
// (wrangler.jsonc), so Xuong.Service answers on port 4000. The VM runs
// in the Durable Object Beam: the builds of one order go to one object,
// so the object builds it one time and the next request finds it in R2.
import app from './edge.com' with { type: 'bytes' };
import { Beam as BeamObject, serve } from 'beam.com';
import version from './site/version.json';
import { handler } from './handler.js';

export class Beam extends BeamObject {}

// The object of a request: one of 4 builders, from the first digit of
// the hash in the URL, or the builder 0.
const builders = serve(app, {
  name: (request) => `builder-${parseInt(request.headers.get('x-xuong-builder') ?? '0', 16) % 4}`,
});

export default {
  fetch(request, env, ctx) {
    const vm = (r) => {
      const hash = new URL(request.url).pathname.match(/[0-9a-f]{32}/)?.[0] ?? '0';
      r.headers.set('x-xuong-builder', hash[0]);
      return builders.fetch(r, env, ctx);
    };
    return handler(request, env, { vm, commit: version.commit });
  },
};
