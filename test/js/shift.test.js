// The tests of shift.js: the start of a construction shift, with a fake
// API of GitHub and a fake R2 bucket.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { RETRY, START, STATE, hoursOf, startShift } from '../../shift.js';
import { bucket } from './fakes.js';

const COMMIT = 'a'.repeat(40);
const NOW = Date.parse('2026-11-18T10:00:00Z');

// The API of GitHub: each call, and the status of its answer.
function github(status = 204) {
  const calls = [];
  const fetch = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    return new Response(null, { status });
  };
  return { calls, fetch };
}

test('a shift starts with workflow_dispatch of shift.yml, for the commit of the edge', async () => {
  const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 'github_pat_x' };
  const g = github();
  const log = [];
  assert.equal(await startShift(env, COMMIT, { fetch: g.fetch, now: NOW, log: (l) => log.push(l) }), 'started');
  assert.equal(g.calls.length, 1);
  assert.equal(g.calls[0].url, 'https://api.github.com/repos/sntran/World/actions/workflows/shift.yml/dispatches');
  assert.equal(g.calls[0].init.headers.authorization, 'Bearer github_pat_x');
  assert.deepEqual(g.calls[0].body, { ref: 'main', inputs: { commit: COMMIT, hours: '5.5' } });
  assert.deepEqual(JSON.parse(new TextDecoder().decode(env.ORDERS.items.get(STATE))), { day: '2026-11-18', count: 1, last: NOW });
  assert.match(log[0], /1 of 6 today/);

  // A shift on its way: no second start; after START, a second one.
  assert.equal(await startShift(env, COMMIT, { fetch: g.fetch, now: NOW + START - 1 }), 'starting');
  assert.equal(await startShift(env, COMMIT, { fetch: g.fetch, now: NOW + START, log: () => {} }), 'started');
  assert.equal(g.calls.length, 2);
});

test('the limit of shifts each day, a new day, and the settings of the environment', async () => {
  const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't', WORLD_SHIFTS_A_DAY: '2', WORLD_SHIFT_API: 'http://127.0.0.1:9', WORLD_SHIFT_REPOSITORY: 'o/r', WORLD_SHIFT_REF: 'test' };
  const g = github();
  const quiet = { fetch: g.fetch, log: () => {} };
  assert.equal(await startShift(env, COMMIT, { ...quiet, now: NOW }), 'started');
  assert.equal(await startShift(env, COMMIT, { ...quiet, now: NOW + START }), 'started');
  assert.equal(await startShift(env, COMMIT, { ...quiet, now: NOW + 2 * START }), 'limit');
  // The next day (UTC): the count starts again.
  assert.equal(await startShift(env, COMMIT, { ...quiet, now: NOW + 24 * 3600_000 }), 'started');
  assert.equal(g.calls[0].url, 'http://127.0.0.1:9/repos/o/r/actions/workflows/shift.yml/dispatches');
  assert.equal(g.calls[0].body.ref, 'test');
});

test('the hours of a shift: 0.5 to 5.5, else 5.5', async () => {
  assert.equal(hoursOf('2'), '2');
  assert.equal(hoursOf('0.5'), '0.5');
  for (const bad of [null, '', '0.4', '6', 'x', '1e1', '-1']) assert.equal(hoursOf(bad), '5.5');
  const g = github();
  await startShift({ ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' }, COMMIT, { hours: '1.5', fetch: g.fetch, now: NOW, log: () => {} });
  assert.equal(g.calls[0].body.inputs.hours, '1.5');
});

test('no token: no shift; an answer of GitHub that is not 204; another request that wrote the state first', async () => {
  assert.equal(await startShift({ ORDERS: bucket() }, COMMIT, { now: NOW }), 'no token');
  const log = [];
  const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
  assert.equal(await startShift(env, COMMIT, { fetch: github(403).fetch, now: NOW, log: (l) => log.push(l) }), 'failed');
  assert.match(log[0], /answered 403/);

  // (Another request writes the state between the read and the write of this one.)
  const raced = bucket();
  const put = raced.put;
  raced.put = async (key, value, options) => {
    await put(key, '{"day":"","count":0,"last":0}');
    return put(key, value, options);
  };
  assert.equal(await startShift({ ORDERS: raced, WORLD_SHIFT_TOKEN: 't' }, COMMIT, { fetch: github().fetch, now: NOW }), 'raced');
});

test('a start that fails for a cause that goes away (no answer, 429, 5xx) gives its start back; the next one comes after RETRY', async () => {
  const state = (env) => JSON.parse(new TextDecoder().decode(env.ORDERS.items.get(STATE)));
  for (const fail of [500, 502, 503, 504, 429, 'no answer']) {
    const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't', WORLD_SHIFTS_A_DAY: '1' };
    const log = [];
    const fetch = fail === 'no answer' ? async () => { throw new TypeError('network'); } : github(fail).fetch;
    assert.equal(await startShift(env, COMMIT, { fetch, now: NOW, log: (l) => log.push(l) }), 'unavailable', String(fail));
    assert.match(log[0], new RegExp(`answered ${fail === 'no answer' ? 'nothing' : fail}; the start is given back`));
    // The count of the day as before, and the next start after RETRY (not START).
    assert.deepEqual(state(env), { day: '2026-11-18', count: 0, last: NOW - START + RETRY });
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY - 1 }), 'starting');
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY, log: () => {} }), 'started');
    // (The one start of the day is still there for the start that works.)
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY + START }), 'limit');
  }
});

test('a start that GitHub refuses (401, 403, 404, 422) keeps its start and the wait of START', async () => {
  for (const status of [401, 403, 404, 422, 400]) {
    const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
    const log = [];
    assert.equal(await startShift(env, COMMIT, { fetch: github(status).fetch, now: NOW, log: (l) => log.push(l) }), 'failed', String(status));
    assert.deepEqual(log, [`shift: the start of the workflow answered ${status}`]);
    assert.deepEqual(JSON.parse(new TextDecoder().decode(env.ORDERS.items.get(STATE))), { day: '2026-11-18', count: 1, last: NOW });
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY }), 'starting');
  }
});

test('a start that is given back does not write over the state of another request', async () => {
  const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
  const log = [];
  // (Another request writes the state while GitHub answers 503.)
  const fetch = async () => {
    await env.ORDERS.put(STATE, JSON.stringify({ day: '2026-11-18', count: 4, last: NOW + 5 }));
    return new Response(null, { status: 503 });
  };
  assert.equal(await startShift(env, COMMIT, { fetch, now: NOW, log: (l) => log.push(l) }), 'unavailable');
  assert.match(log[0], /answered 503; another request wrote the state/);
  assert.deepEqual(JSON.parse(new TextDecoder().decode(env.ORDERS.items.get(STATE))), { day: '2026-11-18', count: 4, last: NOW + 5 });
});
