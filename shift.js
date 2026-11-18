// The start of a construction shift (docs/factory.md, "Construction
// shifts"): the workflow .github/workflows/shift.yml of the repository,
// on a runner of GitHub Actions. The VM of the edge marks an answer of a
// part with "x-world-shift: wanted" (World.Shift.wanted?/1): parts of
// projects wait, and no node of a shift takes them, or the shift ends in
// less than 15 minutes. handler.js then calls startShift().
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

// The result: 'started', or why no shift starts ('no token', 'starting',
// 'limit', 'raced', 'failed'). hours: the length of the shift that a
// project asks for (0.5 to 5.5; 5.5 by default).
export async function startShift(env, commit, { hours = null, fetch = globalThis.fetch, now = Date.now(), log = console.log } = {}) {
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
  const r = await fetch(`${api}/repos/${repository}/actions/workflows/shift.yml/dispatches`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/vnd.github+json',
      'content-type': 'application/json',
      'user-agent': 'world-factory',
      'x-github-api-version': '2022-11-28',
    },
    body: JSON.stringify({ ref: env.WORLD_SHIFT_REF ?? 'main', inputs: { commit, hours: hoursOf(hours) } }),
  });
  if (r.status !== 204) {
    log(`shift: the start of the workflow answered ${r.status}`);
    return 'failed';
  }
  log(`shift: started for the commit ${commit} (${count + 1} of ${limit} today)`);
  return 'started';
}
