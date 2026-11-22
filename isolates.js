// The record of the starts and of the ends of the VM (docs/factory.md,
// "The memory of the VM"), with no dashboard: the time and the cause of
// each end of the isolate of the Durable Object Beam (worker.js).
//
// - A new VM: the constructor of Beam writes the key
//   isolates/TIME.start.COMMIT (noteStart).
// - A request to the VM that fails because its isolate ended (the runtime
//   gives an error in place of the answer): handler.js writes the key
//   isolates/TIME.end.CAUSE (noteEnd), with one word for the cause from
//   the message of the error: memory, cpu, deploy, reset, connection or
//   other.
// - A request to the VM that gets the answer of beam.com for a VM that
//   stopped itself (stoppedAnswer): the cause stopped. beam.com gives that
//   answer, 503 with no error, to each open request when the VM stops (an
//   allocation that failed in the memory of WebAssembly, most often), and
//   to each request while its object starts again.
//
// Each event is a key of R2 with no content, so GET /census reads only a
// list. No header, no body, no IP address and no token goes into the
// record: only the time, the kind of the event, the word of the cause and
// the commit of the Worker.
export const PREFIX = 'isolates/';

const DAY = 86_400_000;

// The causes, from the messages of the runtime of Durable Objects.
const CAUSES = [
  ['memory', /memory limit|exceeded its memory|out of memory/i],
  ['cpu', /cpu time|exceeded its cpu|cpu limit/i],
  ['deploy', /code (was|has been) updated|new version/i],
  ['reset', /reset|evicted|overloaded/i],
  ['connection', /connection|disconnected/i],
];

// The answer of beam.com when the VM stopped itself (runtime/worker.js,
// stopped(); runtime/cloudflare/durable.js, the reset of the object).
const STOPPED = /^The app stopped\./;

// True for that answer. It reads the body of a copy, so the answer goes
// out as it is.
export async function stoppedAnswer(response) {
  if (response?.status !== 503 || !String(response.headers.get('content-type') ?? '').startsWith('text/plain')) return false;
  return STOPPED.test(await response.clone().text().catch(() => ''));
}

// The word of the cause of an error of a request to the VM.
export function causeOf(error) {
  const message = String(error?.message ?? '');
  for (const [cause, pattern] of CAUSES) if (pattern.test(message)) return cause;
  return 'other';
}

const time = (now) => new Date(now).toISOString();

// A new VM, at the commit of its Worker.
export function noteStart(bucket, commit, now = Date.now()) {
  return bucket.put(`${PREFIX}${time(now)}.start.${String(commit ?? 'unknown').slice(0, 12)}`, '');
}

// A request to the VM that failed with `error`, or that got the answer
// of a VM that stopped itself (`error` is then the word stopped).
export function noteEnd(bucket, error, now = Date.now()) {
  return bucket.put(`${PREFIX}${time(now)}.end.${error === 'stopped' ? 'stopped' : causeOf(error)}`, '');
}

// The events of a key, or null for another key.
function event(key) {
  const m = /^isolates\/(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z)\.(start|end)\.([A-Za-z0-9]+)$/.exec(key);
  return m && { at: m[1], kind: m[2], word: m[3] };
}

// The record of the last `days` days, for the census: each start of a VM,
// and for each start after the first, the end of the VM before it, with
// its cause: the cause of the last failed request between the two starts;
// else `deploy` when the commit changed; else `idle` (the isolate ended
// with no request in flight: no cause to see).
export async function isolates(bucket, now = Date.now(), days = 7) {
  const events = [];
  let cursor;
  do {
    const page = await bucket.list({ prefix: PREFIX, startAfter: `${PREFIX}${time(now - days * DAY)}`, cursor, limit: 1000 });
    for (const o of page.objects) {
      const e = event(o.key);
      if (e) events.push(e);
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor && events.length < 5000);
  events.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0));

  const starts = events.filter((e) => e.kind === 'start');
  const ends = [];
  for (let i = 1; i < starts.length; i++) {
    const [before, start] = [starts[i - 1], starts[i]];
    const failed = events.filter((e) => e.kind === 'end' && e.at > before.at && e.at <= start.at);
    const cause = failed.length ? failed[failed.length - 1].word : before.word !== start.word ? 'deploy' : 'idle';
    ends.push({ before: start.at, cause, failed: failed.length, ...(failed.length ? { at: failed[failed.length - 1].at } : {}) });
  }
  const causes = {};
  for (const e of ends) causes[e.cause] = (causes[e.cause] ?? 0) + 1;
  // (The failed requests after the last start: a VM that did not start again yet, or that went on.)
  const last = starts.at(-1)?.at ?? '';
  const after = events.filter((e) => e.kind === 'end' && e.at > last).map((e) => ({ at: e.at, cause: e.word }));
  return {
    since: time(now - days * DAY),
    starts: starts.map((s) => ({ at: s.at, commit: s.word })).slice(-50),
    ends: ends.slice(-50),
    causes,
    failed: after.slice(-50),
  };
}
