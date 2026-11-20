// The tests of shift.js: the start of a construction shift, with a fake
// API of GitHub and a fake R2 bucket.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { RETRY, SEEN, START, STATE, hoursOf, startShift } from '../../shift.js';
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

// The API of GitHub for a start that fails: the dispatch answers
// `dispatch` (a status, or 'no answer'), and the list of the runs answers
// `runsStatus` with `runs`. The looks at the runs are in `looks`.
function failing(dispatch, { runs = [], runsStatus = 200 } = {}) {
  const looks = [];
  const fetch = async (url) => {
    if (url.includes('/actions/workflows/shift.yml/runs?')) {
      looks.push(url);
      if (runsStatus === 'no answer') throw new TypeError('network');
      return Response.json({ workflow_runs: runs }, { status: runsStatus });
    }
    if (dispatch === 'no answer') throw new TypeError('network');
    return new Response(null, { status: dispatch });
  };
  return { fetch, looks };
}

const run = (commit) => ({ id: 1, event: 'workflow_dispatch', display_title: `Construction shift for ${commit}` });
const state = (env) => JSON.parse(new TextDecoder().decode(env.ORDERS.items.get(STATE)));

test('a start that fails for a cause that goes away (no answer, 429, 5xx), with no run of GitHub, gives its start back; the next one comes after RETRY', async () => {
  for (const fail of [500, 502, 503, 504, 429, 'no answer']) {
    const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't', WORLD_SHIFTS_A_DAY: '1' };
    const log = [];
    const waits = [];
    // (A run of another commit is not the run of this start.)
    const g = failing(fail, { runs: [run('b'.repeat(40))] });
    assert.equal(await startShift(env, COMMIT, { fetch: g.fetch, now: NOW, log: (l) => log.push(l), wait: async (ms) => waits.push(ms) }), 'unavailable', String(fail));
    assert.match(log[0], new RegExp(`answered ${fail === 'no answer' ? 'nothing' : fail}, and GitHub made no run; the start is given back`));
    // One look at the runs of the dispatches since a minute before the start, after SEEN.
    assert.deepEqual(waits, [SEEN]);
    assert.equal(g.looks.length, 1);
    assert.match(g.looks[0], /\/repos\/sntran\/World\/actions\/workflows\/shift\.yml\/runs\?event=workflow_dispatch&created=%3E%3D2026-11-18T09%3A59%3A00\.000Z/);
    // The count of the day as before, and the next start after RETRY (not START).
    assert.deepEqual(state(env), { day: '2026-11-18', count: 0, last: NOW - START + RETRY });
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY - 1 }), 'starting');
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY, log: () => {} }), 'started');
    // (The one start of the day is still there for the start that works.)
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY + START }), 'limit');
  }
});

test('a start that fails for a cause that goes away, but GitHub made its run, stays used', async () => {
  for (const fail of [503, 429, 'no answer']) {
    const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
    const log = [];
    const g = failing(fail, { runs: [run('b'.repeat(40)), run(COMMIT)] });
    assert.equal(await startShift(env, COMMIT, { fetch: g.fetch, now: NOW, log: (l) => log.push(l), wait: async () => {} }), 'started', String(fail));
    assert.match(log[0], /but GitHub made its run \(1 of 6 today\)/);
    assert.deepEqual(state(env), { day: '2026-11-18', count: 1, last: NOW });
    // No second start before START.
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY }), 'starting');
  }
});

test('a start that fails for a cause that goes away, and the runs of GitHub do not answer, stays used', async () => {
  for (const [runsStatus, runs] of [[503, []], [404, []], ['no answer', []], [200, null]]) {
    const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
    const log = [];
    const g = failing(502, { runs, runsStatus });
    assert.equal(await startShift(env, COMMIT, { fetch: g.fetch, now: NOW, log: (l) => log.push(l), wait: async () => {} }), 'failed', String(runsStatus));
    assert.match(log[0], /answered 502, and the runs of the workflow did not answer: the start stays used/);
    assert.deepEqual(state(env), { day: '2026-11-18', count: 1, last: NOW });
  }
  // (A body that is not JSON.)
  const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
  const fetch = async (url) => (url.includes('/runs?') ? new Response('<html>', { status: 200 }) : new Response(null, { status: 500 }));
  assert.equal(await startShift(env, COMMIT, { fetch, now: NOW, log: () => {}, wait: async () => {} }), 'failed');
});

test('the wait before the look at the runs is a timer by default', async () => {
  const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
  const timers = [];
  const real = globalThis.setTimeout;
  globalThis.setTimeout = (fn, ms) => {
    timers.push(ms);
    return real(fn, 0);
  };
  try {
    assert.equal(await startShift(env, COMMIT, { fetch: failing(503).fetch, now: NOW, log: () => {} }), 'unavailable');
  } finally {
    globalThis.setTimeout = real;
  }
  assert.deepEqual(timers, [SEEN]);
});

test('a start that GitHub refuses (401, 403, 404, 422) keeps its start and the wait of START', async () => {
  for (const status of [401, 403, 404, 422, 400]) {
    const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
    const log = [];
    const g = failing(status);
    assert.equal(await startShift(env, COMMIT, { fetch: g.fetch, now: NOW, log: (l) => log.push(l) }), 'failed', String(status));
    assert.deepEqual(log, [`shift: the start of the workflow answered ${status}`]);
    // (No look at the runs: GitHub refused the start.)
    assert.deepEqual(g.looks, []);
    assert.deepEqual(state(env), { day: '2026-11-18', count: 1, last: NOW });
    assert.equal(await startShift(env, COMMIT, { fetch: github().fetch, now: NOW + RETRY }), 'starting');
  }
});

test('a start that is given back does not write over the state of another request', async () => {
  const env = { ORDERS: bucket(), WORLD_SHIFT_TOKEN: 't' };
  const log = [];
  // (Another request writes the state while GitHub answers 503.)
  const g = failing(503);
  const fetch = async (url, init) => {
    if (!url.includes('/runs?')) await env.ORDERS.put(STATE, JSON.stringify({ day: '2026-11-18', count: 4, last: NOW + 5 }));
    return g.fetch(url, init);
  };
  assert.equal(await startShift(env, COMMIT, { fetch, now: NOW, log: (l) => log.push(l), wait: async () => {} }), 'unavailable');
  assert.match(log[0], /answered 503, and GitHub made no run; another request wrote the state/);
  assert.deepEqual(state(env), { day: '2026-11-18', count: 4, last: NOW + 5 });
});
