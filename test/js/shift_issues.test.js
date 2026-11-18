// The tests of the issues of the construction shifts: the form
// (scripts/shift-form.mjs), and the work of an issue (scripts/
// shift-issues.mjs) with a fake factory and a fake API of GitHub.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { doneComment, ordersOf, parse, sections } from '../../scripts/shift-form.mjs';

const H1 = '0123456789abcdef0123456789abcdef';
const H2 = 'fedcba9876543210fedcba9876543210';
const C = 'c'.repeat(40);
const TOKEN = 'p'.repeat(40);

const form = ({ project = 'vung_tau', orders = H1, levels = ['mid'], hours = '_No response_' } = {}) =>
  [
    '### Project', '', project, '',
    '### Orders', '', orders, '',
    '### Levels', '', ...['near', 'mid', 'far'].map((l) => `- [${levels.includes(l) ? 'X' : ' '}] ${l}`), '',
    '### Hours', '', hours,
  ].join('\n');

test('the sections of an issue form', () => {
  assert.deepEqual(sections('### A\n\nx\n\n### B\r\ny\nz'), { A: 'x', B: 'y\nz' });
  assert.deepEqual(sections(null), {});
});

test('a request from the form: the project, the orders, the levels and the hours', () => {
  assert.deepEqual(parse(form()), { project: 'vung_tau', orders: { hashes: [H1] }, levels: ['mid'], hours: 5.5 });
  assert.deepEqual(parse(form({ orders: `${H1}\n${H2}\n${H1}`, levels: ['near', 'far'], hours: '2' })).orders, { hashes: [H1, H2] });
  assert.deepEqual(parse(form({ hours: '0.5' })).hours, 0.5);
  const link = parse(form({ orders: `https://github.com/sntran/Vung_Tau/blob/${C}/data/world/orders.json` }));
  assert.deepEqual(link.orders, { url: `https://raw.githubusercontent.com/sntran/Vung_Tau/${C}/data/world/orders.json` });
});

test('a request that is not correct gives its errors, and no value of it goes on', () => {
  const bad = parse(form({ project: 'Vũng Tàu; rm -rf /', orders: 'https://github.com/a/b/blob/main/x.json', levels: [], hours: '9' }));
  assert.equal(bad.errors.length, 4);
  assert.equal(parse(form({ orders: `https://github.com/a/b/blob/${C}/../x.json` })).errors.length, 1);
  assert.equal(parse(form({ orders: `${H1}\nnot a hash` })).errors.length, 1);
  assert.equal(parse(form({ orders: Array.from({ length: 201 }, (_, i) => i.toString(16).padStart(32, '0')).join('\n') })).errors.length, 1);
  assert.equal(parse(form({ hours: '1e1' })).errors.length, 1);
  assert.equal(parse(form({ project: '_No response_' })).errors.length, 1);
  assert.equal(parse('').errors.length, 3);
});

test('the orders of orders.json, and the comment of the parts', () => {
  const order = { blueprint: 'building', options: {} };
  assert.deepEqual(ordersOf([{ id: 'a', order }]), [order]);
  assert.deepEqual(ordersOf({ orders: [order] }), [order]);
  assert.deepEqual(ordersOf({ models: [{ order }] }), [order]);
  assert.throws(() => ordersOf({}), /no list/);
  assert.throws(() => ordersOf([{ id: 'a' }]), /no order with a blueprint/);
  assert.throws(() => ordersOf(Array(201).fill(order)), /more than 200/);
  const text = doneComment([{ hash: H1, level: 'mid', url: 'u', parts: [{ part: 'than_0', url: 'p' }] }]);
  assert.match(text, /`0123456789abcdef0123456789abcdef` at mid: u \(1 parts\)\n {2}- than_0: p/);
});

// The factory and GitHub, in the place of fetch: the parts of KEYS are
// built when `built` says so.
function world({ built = () => true, list = 200 } = {}) {
  const github = [];
  const factory = [];
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    if (u.host === 'api.github.com') {
      github.push({ method: init.method, path: u.pathname + u.search, body: init.body && JSON.parse(init.body) });
      if (u.pathname.endsWith('/comments') && init.method === 'GET') {
        return Response.json([
          { user: { login: 'someone' }, body: `<!-- shift-request {"project":"x"} -->` },
          { user: { login: 'github-actions[bot]' }, body: `wait\n\n<!-- shift-request ${JSON.stringify({ project: 'vung_tau', orders: { hashes: [H1] }, levels: ['mid'], hours: 2 })} -->` },
        ]);
      }
      if (u.pathname.endsWith('/issues') && init.method === 'GET') return Response.json([{ number: 7 }, { number: 8 }]);
      if (init.method === 'PATCH') return new Response(null, { status: 204 });
      return Response.json({});
    }
    if (u.host === 'raw.githubusercontent.com') return Response.json([{ id: 'hai_au', order: { blueprint: 'building' } }]);
    // (The ID token of the job, from GitHub Actions.)
    if (u.host === 'oidc.test') return u.searchParams.get('audience') === 'https://world.mkfifo.com' ? Response.json({ value: 'jwt.of.request' }) : new Response('', { status: 400 });
    factory.push({ path: u.pathname, auth: init.headers?.authorization, project: init.headers?.['x-world-project'], hours: init.headers?.['x-world-shift-hours'] });
    if (u.pathname === '/orders') return Response.json({ hash: H2 });
    if (u.pathname.startsWith('/o/')) {
      if (list !== 200) return Response.json({ errors: [] }, { status: list });
      return Response.json({ parts: [{ part: 'than_0', key: 'a'.repeat(32) }, { part: 'nen_0', key: 'b'.repeat(32) }] });
    }
    if (u.pathname.startsWith('/p/')) return new Response('glTF', { status: built(u.pathname) ? 200 : 202 });
    return new Response('', { status: 404 });
  };
  return { fetch, github, factory };
}

async function load(fake) {
  globalThis.fetch = fake.fetch;
  Object.assign(process.env, { WORLD_URL: 'https://world.test', ACTIONS_ID_TOKEN_REQUEST_URL: 'https://oidc.test/token?for=job', ACTIONS_ID_TOKEN_REQUEST_TOKEN: 'r', GH_TOKEN: 'g', REPOSITORY: 'o/r' });
  return import('../../scripts/shift-issues.mjs');
}

test('a request whose parts are built: the issue gets the parts lists and closes', async () => {
  const fake = world();
  const { handle } = await load(fake);
  await handle(5, parse(form()), 'request');
  assert.deepEqual(fake.factory.map((f) => f.path), ['/o/0123456789abcdef0123456789abcdef.mid.elements.json', `/p/${'a'.repeat(32)}.glb`, `/p/${'b'.repeat(32)}.glb`]);
  assert.ok(fake.factory.every((f) => f.auth === 'Bearer jwt.of.request' && f.project === 'vung_tau'));
  assert.equal(fake.factory[1].hours, '5.5');
  assert.equal(fake.github[0].path, '/repos/o/r/issues/5/comments');
  assert.match(fake.github[0].body.body, /The construction shift built each part/);
  assert.deepEqual(fake.github[1], { method: 'PATCH', path: '/repos/o/r/issues/5', body: { state: 'closed', state_reason: 'completed' } });
});

test('a request whose parts wait: the label shift-queued and the request as data; the shift closes the issue later', async () => {
  const fake = world({ built: (p) => p.includes('bbbb') });
  const { handle, main } = await load(fake);
  await handle(6, parse(form({ orders: `https://github.com/sntran/Vung_Tau/blob/${C}/orders.json`, levels: ['near'] })), 'request');
  assert.equal(fake.factory[0].path, '/orders');
  assert.equal(fake.factory[1].path, `/o/${H2}.elements.json`);
  assert.deepEqual(fake.github[0].body, { labels: ['shift-queued'] });
  assert.match(fake.github[1].body.body, /^1 of 2 parts wait for a construction shift/);
  assert.match(fake.github[1].body.body, /<!-- shift-request \{"project":"vung_tau"/);

  // The check of the shift: each queued issue, with the request of the comment of the workflow; its parts are built now.
  const done = world();
  const check = await load(done);
  await check.main('check');
  const paths = done.github.map((g) => `${g.method} ${g.path}`);
  assert.deepEqual(paths.slice(0, 4), ['GET /repos/o/r/issues?labels=shift,shift-queued&state=open&per_page=50', 'GET /repos/o/r/issues/7/comments?per_page=100', 'POST /repos/o/r/issues/7/comments', 'PATCH /repos/o/r/issues/7']);
  assert.equal(done.factory.find((f) => f.path.startsWith('/p/')).hours, '2');
  await assert.rejects(main('other'), /usage/);
});

test('the errors of a request: the form, no token, a refusal of the factory, and an issue with no request', async () => {
  const fake = world({ list: 422 });
  const { handle, requestOf, ask } = await load(fake);
  await handle(9, parse(form({ hours: '8' })), 'request');
  assert.match(fake.github[0].body.body, /The request is not correct:\n\n- The hours/);
  // Outside of a job of GitHub Actions: WORLD_TOKEN, else nothing.
  const job = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  delete process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  await handle(9, parse(form()), 'request');
  assert.match(fake.github[1].body.body, /The job has no ID token of GitHub Actions/);
  process.env.WORLD_TOKEN = TOKEN;
  await handle(9, parse(form()), 'check');
  assert.equal(fake.factory.at(-1).auth, `Bearer ${TOKEN}`);
  delete process.env.WORLD_TOKEN;
  process.env.ACTIONS_ID_TOKEN_REQUEST_URL = job;
  await handle(9, parse(form()), 'request');
  assert.match(fake.github.at(-1).body.body, /The factory refused the request: the parts list .*: 422/);
  assert.equal(await handle(9, parse(form()), 'check'), null);
  assert.equal(requestOf([{ user: { login: 'github-actions[bot]' }, body: 'no mark' }]), null);
  // A part that does not answer in time counts as not built.
  globalThis.fetch = () => Promise.reject(new Error('down'));
  assert.deepEqual(await ask([{ parts: [{ key: 'a' }] }], { authorization: `Bearer ${TOKEN}` }, 5.5), { keys: 1, left: 1 });
});

test('the join of a shift: the ID token of the job to the edge, and the checked values for sh', async () => {
  const { exports, join, idToken } = await import('../../scripts/shift-join.mjs');
  const answer = { node: 'shift_19002_7_4372@127.0.0.1', cookie: 'a'.repeat(43), edge: 'world@127.0.0.1', pass: 'b'.repeat(64) };
  assert.equal(exports(answer), `export WORLD_NODE='${answer.node}'\nexport WORLD_COOKIE='${answer.cookie}'\nexport WORLD_JOIN='world@127.0.0.1'\nexport WORLD_STORE_TOKEN='${answer.pass}'`);
  for (const bad of [{ node: "x'; rm -rf /; '" }, { cookie: 'short' }, { edge: 'a b' }, { pass: 'x' }]) assert.throws(() => exports({ ...answer, ...bad }), /no good/);
  const calls = [];
  const fetcher = async (url, init = {}) => {
    calls.push(`${init.method ?? 'GET'} ${url} ${init.headers?.authorization}`);
    if (String(url).startsWith('https://oidc.test')) return Response.json({ value: 'jwt.of.shift' });
    return String(url).endsWith('/shift/join') ? Response.json(answer) : new Response('', { status: 404 });
  };
  assert.match(await join(fetcher), /export WORLD_NODE='shift_19002_7_4372@127\.0\.0\.1'/);
  assert.deepEqual(calls, ['GET https://oidc.test/token?for=job&audience=https%3A%2F%2Fworld.mkfifo.com bearer r', 'POST https://world.test/shift/join Bearer jwt.of.shift']);
  // A join that the edge refuses, an ID token that GitHub refuses, and no token at all.
  await assert.rejects(join(async (url) => (String(url).startsWith('https://oidc.test') ? Response.json({ value: 'v' }) : new Response('no', { status: 401 }))), /the join: 401 no/);
  await assert.rejects(idToken(async () => new Response('', { status: 403 })), /the ID token of the job: 403/);
  const job = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  delete process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  await assert.rejects(join(fetcher), /no ID token of a job/);
  process.env.WORLD_STORE_TOKEN = 's'.repeat(40);
  await join(fetcher);
  assert.equal(calls.at(-1), `POST https://world.test/shift/join Bearer ${'s'.repeat(40)}`);
  delete process.env.WORLD_STORE_TOKEN;
  process.env.ACTIONS_ID_TOKEN_REQUEST_URL = job;
});
