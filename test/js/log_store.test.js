// The tests of the store of the log (log_store.js): on SQLite, as in the
// Durable Object, and its program on this computer (scripts/log-store.mjs).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { logStore, sqlTable } from '../../log_store.js';

// The SQLite of a Durable Object (ctx.storage.sql) on node:sqlite.
const sql = () => {
  const db = new DatabaseSync(':memory:');
  return {
    exec(query, ...params) {
      const rows = query.startsWith('SELECT') ? db.prepare(query).all(...params) : (db.prepare(query).run(...params), []);
      return { toArray: () => rows, one: () => rows[0] };
    },
  };
};

const input = (...parts) => new ReadableStream({
  start(c) {
    for (const p of parts) c.enqueue(new TextEncoder().encode(p));
  },
});

const text = (body) => new Response(body).text();
const line = (id) => JSON.stringify({ id, kind: 'done' });

test('append keeps the lines of the events, read gives them after an id, and last gives the last id', async () => {
  const store = logStore(sqlTable(sql()));
  assert.equal(await text(await store.port(input(), { argv: ['last'] })), '0\n');
  const lines = `${line(1)}\n${line(2)}\n${line(3)}\n`;
  // The lines come in parts, and the VM does not end the input.
  assert.equal(await text(await store.port(input(lines.slice(0, 7), lines.slice(7)), { argv: ['append', `${lines.length}`] })), 'ok\n');
  assert.equal(await text(await store.port(input(), { argv: ['read', '1', '10'] })), `${line(2)}\n${line(3)}\n`);
  assert.equal(await text(await store.port(input(), { argv: ['read', '0', '1'] })), `${line(1)}\n`);
  assert.equal(await text(await store.port(input(), { argv: ['last'] })), '3\n');
  // The same id again takes the place of the line.
  const again = `${JSON.stringify({ id: 3, kind: 'stopped' })}\n`;
  await store.port(input(again), { argv: ['append', `${again.length}`] });
  assert.equal(await text(await store.port(input(), { argv: ['read', '2', '10'] })), again);
});

test('a wrong operation, length, id or limit is an error', async () => {
  const store = logStore(sqlTable(sql()));
  await assert.rejects(store.port(input(), { argv: ['drop'] }), /not an operation of the log: drop/);
  await assert.rejects(store.port(input(), { argv: ['append', '-1'] }), /not a length/);
  await assert.rejects(store.port(input(), { argv: ['read', 'x', '1'] }), /not a id/);
  await assert.rejects(store.port(input(), { argv: ['read', '0', '1.5'] }), /not a limit/);
  const bad = '{"id":"one"}\n';
  await assert.rejects(store.port(input(bad), { argv: ['append', `${bad.length}`] }), /not a id/);
});

test('the program keeps the lines in a file; with no file it ends with the exit status 1', () => {
  const dir = mkdtempSync(join(tmpdir(), 'log-'));
  const env = { ...process.env, WORLD_LOG_FILE: join(dir, 'a', 'log.jsonl') };
  const run = (args, inp = '') => spawnSync('node', ['scripts/log-store.mjs', ...args], { env, input: inp, encoding: 'utf8' });
  try {
    assert.equal(run(['last']).stdout, '0\n');
    const lines = `${line(2)}\n${line(1)}\n`;
    assert.equal(run(['append', `${lines.length}`], lines).stdout, 'ok\n');
    assert.equal(run(['read', '0', '10']).stdout, `${line(1)}\n${line(2)}\n`);
    assert.equal(run(['last']).stdout, '2\n');
    assert.equal(spawnSync('node', ['scripts/log-store.mjs', 'last'], { env: { PATH: process.env.PATH } }).status, 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
