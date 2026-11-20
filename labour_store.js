// The store of the queue of the parts of the construction shifts: a port
// program of the VM (BEAM.com, "Ports to bindings"). worker.js gives it
// to the object of the VM as the binding LABOUR_STORE, with the SQLite of
// the Durable Object, and scripts/labour-store.mjs runs it on this
// computer with a file. The other side is World.Labour.Store. A VM that
// starts again (a deploy, the limit of its memory) reads the parts back:
// the queue, its order, and the node of each part in work
// (World.Labour). The arguments:
//
// - wait KEY TICKET: a part that waits. The first ticket of a key stays
//   (a part asked again keeps its place). The result is that ticket.
// - give KEY NODE: the part is in work on the node NODE. "ok".
// - back KEY: the part waits again, at its place. "ok".
// - done KEY: the part is built, or failed. "ok".
// - all: each part, one on each line in the order of the queue: "KEY
//   TICKET NODE", with "-" for a part that waits.
//
// Each value is checked: a wrong value or operation ends the port with
// the exit status 1.

const text = (value) => new Response(value).body;

const CHECKS = {
  key: /^[0-9a-f]{32}$/,
  ticket: /^\d{1,19}$/,
  node: /^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$/,
};

const checked = (name, value) => {
  if (!CHECKS[name].test(String(value))) throw new Error(`not a ${name}: ${value}`);
  return value;
};

// The table of the parts in the SQLite of a Durable Object
// (ctx.storage.sql). A ticket is a number of 19 digits at most, kept as
// text so that no digit goes (SQLite and JavaScript numbers have 53 bits).
export const labourTable = (sql) => {
  sql.exec('CREATE TABLE IF NOT EXISTS labour_parts (key TEXT PRIMARY KEY, ticket TEXT NOT NULL, node TEXT)');
  return {
    wait(key, ticket) {
      sql.exec('INSERT OR IGNORE INTO labour_parts (key, ticket, node) VALUES (?, ?, NULL)', key, ticket);
      return sql.exec('SELECT ticket FROM labour_parts WHERE key = ?', key).one().ticket;
    },
    give(key, node) {
      sql.exec('UPDATE labour_parts SET node = ? WHERE key = ?', node, key);
    },
    back(key) {
      sql.exec('UPDATE labour_parts SET node = NULL WHERE key = ?', key);
    },
    done(key) {
      sql.exec('DELETE FROM labour_parts WHERE key = ?', key);
    },
    all() {
      return sql.exec('SELECT key, ticket, node FROM labour_parts ORDER BY length(ticket), ticket, key').toArray();
    },
  };
};

export const labourStore = (table) => ({
  async port(_stdin, { argv: [op, ...args] }) {
    if (op === 'wait' && args.length === 2) {
      return text(`${await table.wait(checked('key', args[0]), checked('ticket', args[1]))}\n`);
    }
    if (op === 'give' && args.length === 2) {
      await table.give(checked('key', args[0]), checked('node', args[1]));
      return text('ok\n');
    }
    if ((op === 'back' || op === 'done') && args.length === 1) {
      await table[op](checked('key', args[0]));
      return text('ok\n');
    }
    if (op === 'all' && args.length === 0) {
      return text((await table.all()).map((r) => `${r.key} ${r.ticket} ${r.node ?? '-'}\n`).join(''));
    }
    throw new Error(`not an operation of the queue: ${[op, ...args].join(' ')}`);
  },
});
