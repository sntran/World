#!/usr/bin/env node
// The issues of the construction shifts (docs/factory.md, "Construction
// shifts"):
//
//   node scripts/shift-issues.mjs request   the issue ISSUE with its BODY
//                                           (.github/workflows/shift-request.yml)
//   node scripts/shift-issues.mjs check     each queued issue (the shift,
//                                           .github/workflows/shift.yml)
//
// request reads the form (shift-form.mjs), gets the parts lists of its
// orders from the factory for its project (the ID token of the job, and
// the name of the project in x-world-project: no secret), and asks once
// for each part: a part of a project that the edge cannot build waits in
// its queue, and the edge starts a shift or gives the part to the shift
// that runs. When each part is built, the issue gets the parts lists and
// closes. Else the issue gets the label shift-queued and a comment with
// the request as checked data; check reads that comment (not the text of
// the issue, which its author can change), asks again, and closes the
// issue when its parts are built.
//
// The environment: WORLD_URL (the factory for the requests of the job:
// https://world.mkfifo.workers.dev in the workflows), WORLD_PUBLIC_URL
// (the factory in the comments, https://world.mkfifo.com), the ID token of
// the job (permissions: id-token: write; else WORLD_TOKEN, outside of
// GitHub Actions), GH_TOKEN, REPOSITORY (OWNER/NAME), ISSUE and BODY
// (request).
import { doneComment, ordersOf, parse } from './shift-form.mjs';
import { idToken } from './shift-join.mjs';

const env = process.env;
const base = env.WORLD_URL ?? 'https://world.mkfifo.com';
const shown = env.WORLD_PUBLIC_URL ?? 'https://world.mkfifo.com';
const api = env.GITHUB_API_URL ?? 'https://api.github.com';
const MARK = 'shift-request';
const sleep = (s) => new Promise((done) => setTimeout(done, s * 1000));

async function github(method, path, body) {
  const r = await fetch(`${api}/repos/${env.REPOSITORY}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${env.GH_TOKEN}`,
      accept: 'application/vnd.github+json',
      'content-type': 'application/json',
      'user-agent': 'world-shift',
    },
    body: body && JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`GitHub ${method} ${path}: ${r.status}`);
  return r.status === 204 ? null : r.json();
}

const comment = (issue, text) => github('POST', `/issues/${issue}/comments`, { body: text });

// A GET of the factory as the project (`auth`: its headers), again after
// each 202 for at most `most` seconds.
async function get(url, auth, most = 1200) {
  const end = Date.now() + most * 1000;
  for (;;) {
    const r = await fetch(url, { headers: auth });
    if (r.status !== 202 || Date.now() > end) return r;
    await r.arrayBuffer();
    await sleep(Number(r.headers.get('retry-after') ?? 15));
  }
}

// The parts lists of a request: [{ hash, level, url, parts: [{ part, key, url }] }].
export async function listsOf(request, auth) {
  let hashes = request.orders.hashes;
  if (!hashes) {
    const r = await fetch(request.orders.url);
    if (!r.ok) throw new Error(`orders.json: ${r.status}`);
    hashes = [];
    for (const order of ordersOf(await r.json())) {
      const p = await fetch(`${base}/orders`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...auth },
        body: JSON.stringify(order),
      });
      const answer = await p.json();
      if (p.status !== 200) throw new Error(`an order of orders.json: ${p.status} ${JSON.stringify(answer.errors ?? answer)}`);
      hashes.push(answer.hash);
    }
  }
  const lists = [];
  for (const hash of hashes) {
    for (const level of request.levels) {
      const file = `/o/${hash}.${level === 'near' ? '' : `${level}.`}elements.json`;
      const r = await get(`${base}${file}`, auth);
      if (r.status !== 200) throw new Error(`the parts list ${base}${file}: ${r.status}`);
      const { parts } = await r.json();
      lists.push({ hash, level, url: `${shown}${file}`, parts: parts.map((p) => ({ part: p.part, key: p.key, url: `${shown}/p/${p.key}.glb` })) });
    }
  }
  return lists;
}

// One request for each part, 8 at a time, each for at most 10 s (the
// part goes on in the queue of the edge): the parts, and those that are
// not built yet. The hours of the request go to the start of a shift.
export async function ask(lists, auth, hours) {
  const keys = [...new Set(lists.flatMap((l) => l.parts.map((p) => p.key)))];
  let left = 0;
  const one = async (key) => {
    const stop = new AbortController();
    const timer = setTimeout(() => stop.abort(), 10_000);
    try {
      const r = await fetch(`${base}/p/${key}.glb`, { headers: { ...auth, 'x-world-shift-hours': String(hours) }, signal: stop.signal });
      await r.arrayBuffer();
      if (r.status !== 200) left++;
    } catch {
      left++;
    } finally {
      clearTimeout(timer);
    }
  };
  for (let i = 0; i < keys.length; i += 8) await Promise.all(keys.slice(i, i + 8).map(one));
  return { keys: keys.length, left };
}

// The work of one issue. mode: 'request' (the first look) or 'check'.
export async function handle(issue, request, mode) {
  if (request.errors) return comment(issue, ['The request is not correct:', '', ...request.errors.map((e) => `- ${e}`)].join('\n'));
  const bearer = (await idToken()) ?? env.WORLD_TOKEN;
  if (!bearer) return comment(issue, 'The job has no ID token of GitHub Actions (permissions: id-token: write), and no WORLD_TOKEN.');
  const auth = { authorization: `Bearer ${bearer}`, 'x-world-project': request.project };
  let lists;
  try {
    lists = await listsOf(request, auth);
  } catch (e) {
    return mode === 'request' ? comment(issue, `The factory refused the request: ${e.message}`) : null;
  }
  const { keys, left } = await ask(lists, auth, request.hours);
  if (left === 0) {
    await comment(issue, doneComment(lists));
    return github('PATCH', `/issues/${issue}`, { state: 'closed', state_reason: 'completed' });
  }
  if (mode !== 'request') return null;
  await github('POST', `/issues/${issue}/labels`, { labels: ['shift-queued'] });
  return comment(
    issue,
    `${left} of ${keys} parts wait for a construction shift. A shift starts now, or the shift that runs takes them. This issue closes when they are built.\n\n<!-- ${MARK} ${JSON.stringify(request)} -->`,
  );
}

// The checked request in the last comment of the workflow on an issue.
export function requestOf(comments) {
  const pattern = new RegExp(`<!-- ${MARK} (\\{.*\\}) -->`);
  for (const c of [...comments].reverse()) {
    if (c.user?.login !== 'github-actions[bot]') continue;
    const m = pattern.exec(c.body ?? '');
    if (m) return JSON.parse(m[1]);
  }
  return null;
}

export async function main(mode) {
  if (mode === 'request') return handle(env.ISSUE, parse(env.BODY), 'request');
  if (mode !== 'check') throw new Error('usage: node scripts/shift-issues.mjs request|check');
  const issues = await github('GET', '/issues?labels=shift,shift-queued&state=open&per_page=50');
  for (const issue of issues) {
    const request = requestOf(await github('GET', `/issues/${issue.number}/comments?per_page=100`));
    if (request) await handle(issue.number, request, 'check');
  }
  return null;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main(process.argv[2]).catch((e) => {
    console.error(`shift-issues: ${e.message}`);
    process.exit(1);
  });
}
