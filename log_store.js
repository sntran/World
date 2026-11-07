// The store of the log of the node: a port program of the VM (BEAM.com,
// "Ports to bindings"). worker.js gives it to the object of the VM as the
// binding LOG_STORE, with the SQLite of the Durable Object, and
// scripts/log-store.mjs runs it on this computer with a file. The other
// side is World.Log.Store. Each event is one line of JSON with its id.
// The arguments:
//
// - append LENGTH: the lines come on the input, with this length. The
//   result is "ok".
// - read AFTER LIMIT: the lines of the events after the id AFTER, at most
//   LIMIT, in the order of their ids.
// - last: the id of the last event, or 0.
//
// An error ends the port with the exit status 1.
import { read } from './order_store.js';

const text = (value) => new Response(value).body;

const count = (value, name) => {
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n < 0) throw new Error(`not a ${name}: ${value}`);
  return n;
};

// The table of the events in the SQLite of a Durable Object
// (ctx.storage.sql): append(rows), after(id, limit), last().
export const sqlTable = (sql) => {
  sql.exec('CREATE TABLE IF NOT EXISTS log (id INTEGER PRIMARY KEY, line TEXT NOT NULL)');
  return {
    append(rows) {
      for (const { id, line } of rows) sql.exec('INSERT OR REPLACE INTO log (id, line) VALUES (?, ?)', id, line);
    },
    after(id, limit) {
      return sql.exec('SELECT line FROM log WHERE id > ? ORDER BY id LIMIT ?', id, limit).toArray().map((r) => r.line);
    },
    last() {
      return sql.exec('SELECT MAX(id) AS id FROM log').one().id ?? 0;
    },
  };
};

// table: the table of the events (sqlTable, or a file on this computer).
export const logStore = (table) => ({
  async port(stdin, { argv: [op, ...args] }) {
    if (op === 'append' && args.length === 1) {
      const lines = new TextDecoder().decode(await read(stdin, count(args[0], 'length'))).split('\n').filter(Boolean);
      await table.append(lines.map((line) => ({ id: count(JSON.parse(line).id, 'id'), line })));
      return text('ok\n');
    }
    if (op === 'read' && args.length === 2) {
      return text((await table.after(count(args[0], 'id'), count(args[1], 'limit'))).map((l) => `${l}\n`).join(''));
    }
    if (op === 'last' && args.length === 0) return text(`${await table.last()}\n`);
    throw new Error(`not an operation of the log: ${[op, ...args].join(' ')}`);
  },
});
