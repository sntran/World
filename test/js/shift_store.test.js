// The tests of the store of the passes of the shifts (shift_store.js): on
// SQLite, as in the Durable Object, and its program on this computer
// (scripts/shift-store.mjs).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { shiftStore, shiftTable } from '../../shift_store.js';

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

const text = (body) => new Response(body).text();
const PASS = 'a'.repeat(64);
const OTHER = 'b'.repeat(64);
const NODE = 'shift_444431276051_610_4372@127.0.0.1';
const COOKIE = 'C'.repeat(43);

test('put keeps a pass with its node, its cookie and its time; all gives them; drop forgets one', async () => {
  const store = shiftStore(shiftTable(sql()));
  const run = async (...argv) => text(await store.port(null, { argv }));
  assert.equal(await run('all'), '');
  assert.equal(await run('put', OTHER, NODE, COOKIE, '20'), 'ok\n');
  assert.equal(await run('put', PASS, NODE, COOKIE, '10'), 'ok\n');
  assert.equal(await run('all'), `${PASS} ${NODE} ${COOKIE} 10\n${OTHER} ${NODE} ${COOKIE} 20\n`);
  // The same pass again takes the place of the row.
  await run('put', PASS, NODE, COOKIE, '30');
  assert.equal(await run('all'), `${OTHER} ${NODE} ${COOKIE} 20\n${PASS} ${NODE} ${COOKIE} 30\n`);
  assert.equal(await run('drop', OTHER), 'ok\n');
  assert.equal(await run('all'), `${PASS} ${NODE} ${COOKIE} 30\n`);
});

test('a wrong operation, pass, node, cookie or time is an error', async () => {
  const store = shiftStore(shiftTable(sql()));
  await assert.rejects(store.port(null, { argv: ['clear'] }), /not an operation of the passes: clear/);
  await assert.rejects(store.port(null, { argv: ['put', 'x', NODE, COOKIE, '1'] }), /not a pass/);
  await assert.rejects(store.port(null, { argv: ['put', PASS, 'world@127.0.0.1', COOKIE, '1'] }), /not a node/);
  await assert.rejects(store.port(null, { argv: ['put', PASS, NODE, 'short', '1'] }), /not a cookie/);
  await assert.rejects(store.port(null, { argv: ['put', PASS, NODE, COOKIE, '-1'] }), /not a at/);
  await assert.rejects(store.port(null, { argv: ['drop', 'x'] }), /not a pass/);
});

test('the program keeps the passes in a file; with no file it ends with the exit status 1', () => {
  const dir = mkdtempSync(join(tmpdir(), 'shift-'));
  const env = { ...process.env, WORLD_SHIFT_FILE: join(dir, 'a', 'passes.json') };
  const run = (...args) => spawnSync('node', ['scripts/shift-store.mjs', ...args], { env, encoding: 'utf8' });
  try {
    assert.equal(run('all').stdout, '');
    assert.equal(run('put', OTHER, NODE, COOKIE, '20').stdout, 'ok\n');
    assert.equal(run('put', PASS, NODE, COOKIE, '10').stdout, 'ok\n');
    assert.equal(run('all').stdout, `${PASS} ${NODE} ${COOKIE} 10\n${OTHER} ${NODE} ${COOKIE} 20\n`);
    assert.equal(run('drop', PASS).stdout, 'ok\n');
    assert.equal(run('all').stdout, `${OTHER} ${NODE} ${COOKIE} 20\n`);
    assert.equal(run('put', 'x', NODE, COOKIE, '1').status, 1);
    assert.equal(spawnSync('node', ['scripts/shift-store.mjs', 'all'], { env: { PATH: process.env.PATH } }).status, 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
