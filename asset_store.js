// The port program ASSET_STORE of the object of the VM (worker.js,
// World.People.Files): the files of MakeHuman (priv/makehuman) from the
// static files of the site (/makehuman/, scripts/site.sh), with the
// binding ASSETS. The release of the edge has no priv/makehuman
// (mix.exs), so a build reads only the files that it needs, when it
// needs them, and the module edge.com is 35 MB smaller in the isolate.
//
// The operations (argv), each for a path in priv/makehuman:
//
// - get PATH: the bytes of the file.
// - has PATH: "yes\n" or "no\n".
// - range PATH AT N [AT N ...]: the bytes at each offset AT, N bytes
//   each, one after the other. A request with a range header for each
//   part (206), or the whole file one time when the static files give
//   200.
//
// An error (no such file, a path that is not a path of the folder, a
// part out of the file) ends the port with the exit status 1.

export const PREFIX = '/makehuman/';

// A path in the folder: names of letters, digits, "_", "-" and ".", with
// "/" between them, and no "..".
export const PATH = /^[A-Za-z0-9_-][A-Za-z0-9_.-]*(\/[A-Za-z0-9_-][A-Za-z0-9_.-]*)*$/;

const path = (value) => {
  if (!PATH.test(value ?? '') || value.split('/').includes('..')) throw new Error(`not a path of the files of MakeHuman: ${value}`);
  return value;
};

const count = (value) => {
  const n = Number(value);
  if (!/^\d+$/.test(value ?? '') || !Number.isSafeInteger(n)) throw new Error(`not a count: ${value}`);
  return n;
};

const text = (value) => new Response(value).body;

export const assetStore = (assets) => {
  const url = (p) => `https://assets${PREFIX}${path(p)}`;

  const file = async (p, init) => {
    const r = await assets.fetch(new Request(url(p), init));
    if (!r.ok) throw new Error(`no file ${p} in the static files: ${r.status}`);
    return r;
  };

  // The N bytes at AT: the answer to a range, else a part of the whole file.
  const part = async (p, at, n, whole) => {
    if (n === 0) return new Uint8Array(0);
    if (!whole.bytes) {
      const r = await file(p, { headers: { range: `bytes=${at}-${at + n - 1}` } });
      const bytes = new Uint8Array(await r.arrayBuffer());
      if (r.status === 206) {
        if (bytes.byteLength !== n) throw new Error(`the part at ${at} of ${p} has ${bytes.byteLength} of ${n} bytes`);
        return bytes;
      }
      whole.bytes = bytes;
    }
    if (at + n > whole.bytes.byteLength) throw new Error(`the part at ${at} of ${p} is out of its ${whole.bytes.byteLength} bytes`);
    return whole.bytes.subarray(at, at + n);
  };

  return {
    async port(_stdin, { argv: [op, ...args] }) {
      if (op === 'get' && args.length === 1) return (await file(args[0])).body;
      if (op === 'has' && args.length === 1) {
        const r = await assets.fetch(new Request(url(args[0]), { method: 'HEAD' }));
        await r.arrayBuffer();
        return text(r.ok ? 'yes\n' : 'no\n');
      }
      if (op === 'range' && args.length >= 3 && args.length % 2 === 1) {
        const [p, ...pairs] = args;
        const whole = {};
        const parts = [];
        for (let i = 0; i < pairs.length; i += 2) parts.push(await part(p, count(pairs[i]), count(pairs[i + 1]), whole));
        return new Blob(parts).stream();
      }
      throw new Error(`not an operation of the files: ${[op, ...args].join(' ')}`);
    },
  };
};
