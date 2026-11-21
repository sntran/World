// The tests of the store of the queue of the parts (labour_store.js): on
// SQLite, as in the Durable Object, and its program on this computer
// (scripts/labour-store.mjs).
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { labourStore, labourTable } from '../../labour_store.js';

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
const C = 'c'.repeat(32);
const D = 'd'.repeat(32);
const NODE = 'shift_444431276051_610_4372@127.0.0.1';
// (A ticket of 19 digits: more than a number of JavaScript holds.)
const BIG = '1795140242123456789';

test('wait keeps the first ticket of a key; give, back and done; all in the order of the queue', async () => {
  const store = labourStore(labourTable(sql()));
  const run = async (...argv) => text(await store.port(null, { argv }));
  assert.equal(await run('all'), '');
  assert.equal(await run('wait', D, BIG), `${BIG}\n`);
  assert.equal(await run('wait', C, '99'), '99\n');
  // The same key again keeps its place.
  assert.equal(await run('wait', D, '5'), `${BIG}\n`);
  assert.equal(await run('all'), `${C} 99 -\n${D} ${BIG} -\n`);
  assert.equal(await run('give', C, NODE), 'ok\n');
  assert.equal(await run('all'), `${C} 99 ${NODE}\n${D} ${BIG} -\n`);
  assert.equal(await run('back', C), 'ok\n');
  assert.equal(await run('all'), `${C} 99 -\n${D} ${BIG} -\n`);
  assert.equal(await run('done', C), 'ok\n');
  assert.equal(await run('all'), `${D} ${BIG} -\n`);
});

test('ask keeps the projects of a part in the order of their first request; done drops them', async () => {
  const store = labourStore(labourTable(sql()));
  const run = async (...argv) => text(await store.port(null, { argv }));
  assert.equal(await run('wait', C, '1'), '1\n');
  assert.equal(await run('projects', C), '');
  assert.equal(await run('ask', C, 'vung_tau'), 'ok\n');
  assert.equal(await run('ask', D, 'tre'), 'ok\n');
  assert.equal(await run('ask', C, 'humans-must-die'), 'ok\n');
  assert.equal(await run('ask', C, 'vung_tau'), 'ok\n');
  assert.equal(await run('projects', C), 'vung_tau\nhumans-must-die\n');
  assert.equal(await run('done', C), 'ok\n');
  assert.equal(await run('projects', C), '');
  assert.equal(await run('projects', D), 'tre\n');
  await assert.rejects(store.port(null, { argv: ['ask', C, 'Vung Tau'] }), /not a project/);
  await assert.rejects(store.port(null, { argv: ['projects', 'x'] }), /not a key/);
});

test('a wrong operation, key, ticket or node is an error', async () => {
  const store = labourStore(labourTable(sql()));
  await assert.rejects(store.port(null, { argv: ['clear'] }), /not an operation of the queue: clear/);
  await assert.rejects(store.port(null, { argv: ['wait', 'x', '1'] }), /not a key/);
  await assert.rejects(store.port(null, { argv: ['wait', C, '-1'] }), /not a ticket/);
  await assert.rejects(store.port(null, { argv: ['wait', C, '1'.repeat(20)] }), /not a ticket/);
  await assert.rejects(store.port(null, { argv: ['give', C, 'nobody'] }), /not a node/);
  await assert.rejects(store.port(null, { argv: ['done', 'x'] }), /not a key/);
  await assert.rejects(store.port(null, { argv: ['back'] }), /not an operation/);
});

test('the program keeps the queue in a file; with no file it ends with the exit status 1', () => {
  const dir = mkdtempSync(join(tmpdir(), 'labour-'));
  const env = { ...process.env, WORLD_LABOUR_FILE: join(dir, 'a', 'labour.json') };
  const run = (...args) => spawnSync('node', ['scripts/labour-store.mjs', ...args], { env, encoding: 'utf8' });
  try {
    assert.equal(run('all').stdout, '');
    assert.equal(run('wait', D, '20').stdout, '20\n');
    assert.equal(run('wait', C, '100').stdout, '100\n');
    assert.equal(run('wait', D, '1').stdout, '20\n');
    assert.equal(run('give', D, NODE).stdout, 'ok\n');
    // (A give or a back of a key that is not there changes nothing.)
    assert.equal(run('give', 'e'.repeat(32), NODE).stdout, 'ok\n');
    assert.equal(run('back', 'e'.repeat(32)).stdout, 'ok\n');
    assert.equal(run('all').stdout, `${D} 20 ${NODE}\n${C} 100 -\n`);
    assert.equal(run('back', D).stdout, 'ok\n');
    assert.equal(run('done', C).stdout, 'ok\n');
    assert.equal(run('all').stdout, `${D} 20 -\n`);
    // (Two tickets of one length: the order of the text; one ticket: the order of the keys.)
    run('wait', C, '21');
    run('wait', 'b'.repeat(32), '21');
    assert.equal(run('all').stdout, `${D} 20 -\n${'b'.repeat(32)} 21 -\n${C} 21 -\n`);
    assert.equal(run('wait', 'x', '1').status, 1);
    // The projects of a part, also in the file; all gives no row of them, and done drops them.
    assert.equal(run('ask', C, 'vung_tau').stdout, 'ok\n');
    assert.equal(run('ask', C, 'tre').stdout, 'ok\n');
    assert.equal(run('ask', C, 'vung_tau').stdout, 'ok\n');
    assert.equal(run('projects', C).stdout, 'vung_tau\ntre\n');
    assert.equal(run('projects', D).stdout, '');
    assert.equal(run('all').stdout, `${D} 20 -\n${'b'.repeat(32)} 21 -\n${C} 21 -\n`);
    run('done', C);
    assert.equal(run('projects', C).stdout, '');
    run('wait', C, '21');
    // Runs at one time take turns: no change goes.
    const many = Array.from({ length: 12 }, (_, i) => i.toString(16).padStart(32, 'f'));
    return Promise.all(many.map((key, i) => new Promise((done) => {
      const child = spawn('node', ['scripts/labour-store.mjs', 'wait', key, String(100 + i)], { env });
      child.on('exit', done);
    }))).then(() => {
      assert.equal(run('all').stdout.split('\n').filter(Boolean).length, 3 + many.length);
      assert.equal(spawnSync('node', ['scripts/labour-store.mjs', 'all'], { env: { PATH: process.env.PATH } }).status, 1);
      rmSync(dir, { recursive: true, force: true });
    });
  } catch (e) {
    rmSync(dir, { recursive: true, force: true });
    throw e;
  }
});
