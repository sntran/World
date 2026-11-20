// The start of a construction shift (docs/factory.md, "Construction
// shifts"): the workflow .github/workflows/shift.yml of the repository,
// on a runner of GitHub Actions. The VM of the edge marks an answer of a
// part with "x-world-shift: wanted" (World.Shift.wanted?/1): parts of
// projects wait, and no node of a shift takes them, or the shift ends in
// less than 15 minutes. handler.js then calls startShift(), for a request
// of a project only: a request with no token does not use the starts of
// the day.
//
// The limits:
//
// - The secret WORLD_SHIFT_TOKEN: a fine-grained token with actions:
//   write on the repository only. With no token, no shift starts.
// - A shift that started is on its way for START ms (the runner, the
//   cache and the start of the node): no second start in that time.
// - At most WORLD_SHIFTS_A_DAY starts each day (UTC), 6 by default.
// - One shift at a time: the concurrency group of the workflow. A start
//   while a shift runs waits for its end, and takes the new parts then.
// - A start that fails for a cause that goes away (no answer, 429, or 5xx:
//   GitHub is down or busy) can still start the workflow. So the start
//   looks at the runs of shift.yml that GitHub made since the start
//   (workflow_dispatch, with the commit in their name), after SEEN ms. A
//   run is there: the start stays used (a second start would wait in the
//   queue for a whole shift). No run: the start of the day goes back, and
//   the next start can come after RETRY ms. The runs do not answer: the
//   start stays used, as a refused start. A start that GitHub refuses
//   (401 or 403: the token; 404 or 422: the workflow or its inputs; any
//   other answer) keeps its start and the wait of START: a new try fails
//   in the same way until the owner corrects it, so it does not use the
//   starts of the day or the API of GitHub.
//
// The state is one object of R2, shifts/state.json ({ day, count, last }),
// written only if no other request wrote it first (its ETag).

export const STATE = 'shifts/state.json';

// The hours of a shift: a number from 0.5 to 5.5, else 5.5.
export function hoursOf(text) {
  const n = Number(text);
  return /^\d+(\.\d+)?$/.test(String(text ?? '')) && n >= 0.5 && n <= 5.5 ? String(n) : '5.5';
}

export const START = 20 * 60_000;
export const RETRY = 60_000;
export const SEEN = 5_000;

// An answer of GitHub (or null: no answer) for which the start is given
// back.
const passing = (r) => r === null || r.status === 429 || r.status >= 500;

// True when GitHub made a run of shift.yml (workflow_dispatch) for the
// commit since `since` (ms), false when it made none, null when the runs
// do not answer.
async function dispatched(api, repository, headers, commit, since, fetch) {
  const created = encodeURIComponent(`>=${new Date(since).toISOString()}`);
  const r = await fetch(`${api}/repos/${repository}/actions/workflows/shift.yml/runs?event=workflow_dispatch&created=${created}&per_page=100`, { headers }).catch(() => null);
  if (!r || r.status !== 200) return null;
  const body = await r.json().catch(() => null);
  if (!Array.isArray(body?.workflow_runs)) return null;
  return body.workflow_runs.some((run) => String(run.display_title ?? '').includes(commit));
}

// The result: 'started', or why no shift starts ('no token', 'starting',
// 'limit', 'raced', 'failed': GitHub refused the start, or did not answer
// and its runs did not answer, 'unavailable': GitHub did not start it, and
// the start is given back). hours: the length of the shift that a project
// asks for (0.5 to 5.5; 5.5 by default). wait(ms): the wait before the
// look at the runs (a timer by default).
export async function startShift(env, commit, { hours = null, fetch = globalThis.fetch, now = Date.now(), log = console.log, wait = (ms) => new Promise((done) => setTimeout(done, ms)) } = {}) {
  const token = env.WORLD_SHIFT_TOKEN;
  if (typeof token !== 'string' || token === '') return 'no token';
  const limit = Number(env.WORLD_SHIFTS_A_DAY ?? '6');
  const object = await env.ORDERS.get(STATE);
  const state = object ? await object.json() : { day: '', count: 0, last: 0 };
  const day = new Date(now).toISOString().slice(0, 10);
  const count = state.day === day ? state.count : 0;
  if (now - state.last < START) return 'starting';
  if (count >= limit) return 'limit';

  const only = object ? { etagMatches: object.etag } : { etagDoesNotMatch: '*' };
  const put = await env.ORDERS.put(STATE, JSON.stringify({ day, count: count + 1, last: now }), {
    onlyIf: only,
    httpMetadata: { contentType: 'application/json' },
  });
  if (!put) return 'raced';

  const api = env.WORLD_SHIFT_API ?? 'https://api.github.com';
  const repository = env.WORLD_SHIFT_REPOSITORY ?? 'sntran/World';
  const headers = {
    authorization: `Bearer ${token}`,
    accept: 'application/vnd.github+json',
    'user-agent': 'world-factory',
    'x-github-api-version': '2022-11-28',
  };
  const r = await fetch(`${api}/repos/${repository}/actions/workflows/shift.yml/dispatches`, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: JSON.stringify({ ref: env.WORLD_SHIFT_REF ?? 'main', inputs: { commit, hours: hoursOf(hours) } }),
  }).catch(() => null);
  const answer = r ? r.status : 'nothing';
  if (passing(r)) {
    // (GitHub can take a start and still give no answer or a 5xx: its run
    // comes some seconds later. A minute of the clocks of GitHub and of
    // the Worker.)
    await wait(SEEN);
    const seen = await dispatched(api, repository, headers, commit, now - 60_000, fetch);
    if (seen === true) {
      log(`shift: the start of the workflow answered ${answer}, but GitHub made its run (${count + 1} of ${limit} today)`);
      return 'started';
    }
    if (seen === null) {
      log(`shift: the start of the workflow answered ${answer}, and the runs of the workflow did not answer: the start stays used`);
      return 'failed';
    }
    // (The state before this start, if no other request wrote it since:
    // the count of the day, and a time so that the next start can come
    // after RETRY.)
    const back = await env.ORDERS.put(STATE, JSON.stringify({ day, count, last: now - START + RETRY }), {
      onlyIf: { etagMatches: put.etag },
      httpMetadata: { contentType: 'application/json' },
    });
    log(`shift: the start of the workflow answered ${answer}, and GitHub made no run; ${back ? 'the start is given back' : 'another request wrote the state'}`);
    return 'unavailable';
  }
  if (r.status !== 204) {
    log(`shift: the start of the workflow answered ${r.status}`);
    return 'failed';
  }
  log(`shift: started for the commit ${commit} (${count + 1} of ${limit} today)`);
  return 'started';
}
