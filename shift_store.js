// The store of the passes of the construction shifts: a port program of
// the VM (BEAM.com, "Ports to bindings"). worker.js gives it to the object
// of the VM as the binding SHIFT_STORE, with the SQLite of the Durable
// Object, and scripts/shift-store.mjs runs it on this computer with a
// file. The other side is World.Shift.Store. A VM that starts again reads
// the passes back, so the shifts that run connect again (World.Shift.Passes).
// The arguments:
//
// - put PASS NODE COOKIE AT: keep a pass, the name of its node, the cookie
//   of that node, and the time of the join (ms of the Unix clock). The
//   result is "ok".
// - drop PASS: forget a pass. The result is "ok".
// - all: each pass that the store keeps, one on each line: "PASS NODE
//   COOKIE AT".
//
// Each value is checked: a wrong value or operation ends the port with
// the exit status 1.

const text = (value) => new Response(value).body;

const CHECKS = {
  pass: /^[0-9a-f]{64}$/,
  node: /^shift_[A-Za-z0-9]*_\d+_\d+@127\.0\.0\.1$/,
  cookie: /^[A-Za-z0-9_-]{43}$/,
  at: /^\d{1,16}$/,
};

const checked = (name, value) => {
  if (!CHECKS[name].test(String(value))) throw new Error(`not a ${name}: ${value}`);
  return value;
};

// The table of the passes in the SQLite of a Durable Object
// (ctx.storage.sql): put(row), drop(pass), all().
export const shiftTable = (sql) => {
  sql.exec('CREATE TABLE IF NOT EXISTS shift_passes (pass TEXT PRIMARY KEY, node TEXT NOT NULL, cookie TEXT NOT NULL, at INTEGER NOT NULL)');
  return {
    put({ pass, node, cookie, at }) {
      sql.exec('INSERT OR REPLACE INTO shift_passes (pass, node, cookie, at) VALUES (?, ?, ?, ?)', pass, node, cookie, at);
    },
    drop(pass) {
      sql.exec('DELETE FROM shift_passes WHERE pass = ?', pass);
    },
    all() {
      return sql.exec('SELECT pass, node, cookie, at FROM shift_passes ORDER BY at, pass').toArray();
    },
  };
};

export const shiftStore = (table) => ({
  async port(_stdin, { argv: [op, ...args] }) {
    if (op === 'put' && args.length === 4) {
      const [pass, node, cookie, at] = args;
      await table.put({ pass: checked('pass', pass), node: checked('node', node), cookie: checked('cookie', cookie), at: Number(checked('at', at)) });
      return text('ok\n');
    }
    if (op === 'drop' && args.length === 1) {
      await table.drop(checked('pass', args[0]));
      return text('ok\n');
    }
    if (op === 'all' && args.length === 0) {
      return text((await table.all()).map((r) => `${r.pass} ${r.node} ${r.cookie} ${r.at}\n`).join(''));
    }
    throw new Error(`not an operation of the passes: ${[op, ...args].join(' ')}`);
  },
});
