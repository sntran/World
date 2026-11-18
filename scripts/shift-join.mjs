#!/usr/bin/env node
// The join of a construction shift (docs/factory.md, "Construction
// shifts"): the runner sends the ID token of its job to WORLD_URL/shift/
// join, and the edge gives the name of its node, a cookie for that node
// only, the name of the node of the edge, and the pass of the shift for
// the store of the Worker. The output is for sh (scripts/shift.sh):
//
//   eval "$(node scripts/shift-join.mjs)"
//
// Each value is checked before it goes out. With no ID token (a shift on
// this computer, for a test), WORLD_STORE_TOKEN is the bearer.

const env = process.env;

// The ID token of the job of GitHub Actions (permissions: id-token:
// write), for the audience of the factory, or null outside of a job.
export async function idToken(fetcher = fetch) {
  const url = env.ACTIONS_ID_TOKEN_REQUEST_URL;
  const token = env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
  if (!url || !token) return null;
  const audience = env.WORLD_AUDIENCE ?? 'https://world.mkfifo.com';
  const r = await fetcher(`${url}&audience=${encodeURIComponent(audience)}`, { headers: { authorization: `bearer ${token}` } });
  if (!r.ok) throw new Error(`the ID token of the job: ${r.status}`);
  return (await r.json()).value;
}

const CHECKS = {
  node: /^shift_[A-Za-z0-9]*_\d+_\d+@127\.0\.0\.1$/,
  cookie: /^[A-Za-z0-9_-]{43}$/,
  edge: /^[a-z0-9_]+@[a-z0-9.-]+$/,
  pass: /^[0-9a-f]{64}$/,
};

// The lines for sh, from the answer of the join.
export function exports(answer) {
  for (const [name, pattern] of Object.entries(CHECKS)) {
    if (!pattern.test(String(answer?.[name] ?? ''))) throw new Error(`the join gave no good ${name}`);
  }
  return [
    `export WORLD_NODE='${answer.node}'`,
    `export WORLD_COOKIE='${answer.cookie}'`,
    `export WORLD_JOIN='${answer.edge}'`,
    `export WORLD_STORE_TOKEN='${answer.pass}'`,
  ].join('\n');
}

export async function join(fetcher = fetch) {
  const bearer = (await idToken(fetcher)) ?? env.WORLD_STORE_TOKEN;
  if (!bearer) throw new Error('no ID token of a job, and no WORLD_STORE_TOKEN');
  const r = await fetcher(`${env.WORLD_URL ?? 'https://world.mkfifo.com'}/shift/join`, { method: 'POST', headers: { authorization: `Bearer ${bearer}` } });
  if (r.status !== 200) throw new Error(`the join: ${r.status} ${await r.text()}`);
  return exports(await r.json());
}

if (import.meta.url === `file://${process.argv[1]}`) {
  join()
    .then((lines) => console.log(lines))
    .catch((e) => {
      console.error(`shift-join: ${e.message}`);
      process.exit(1);
    });
}
