// The tests of the issues of the construction shifts: the form
// (scripts/shift-form.mjs), and the work of an issue (scripts/
// shift-issues.mjs) with a fake factory and a fake API of GitHub.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { doneComment, ordersOf, parse, sections, tokenOf } from '../../scripts/shift-form.mjs';

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

test('the orders of orders.json, the token of a project, and the comment of the parts', () => {
  const order = { blueprint: 'building', options: {} };
  assert.deepEqual(ordersOf([{ id: 'a', order }]), [order]);
  assert.deepEqual(ordersOf({ orders: [order] }), [order]);
  assert.deepEqual(ordersOf({ models: [{ order }] }), [order]);
  assert.throws(() => ordersOf({}), /no list/);
  assert.throws(() => ordersOf([{ id: 'a' }]), /no order with a blueprint/);
  assert.throws(() => ordersOf(Array(201).fill(order)), /more than 200/);
  assert.equal(tokenOf(`a=${'x'.repeat(32)}, vung_tau=${TOKEN}`, 'vung_tau'), TOKEN);
  assert.equal(tokenOf('vung_tau=short', 'vung_tau'), null);
  assert.equal(tokenOf(undefined, 'vung_tau'), null);
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
    factory.push({ path: u.pathname, auth: init.headers?.authorization, hours: init.headers?.['x-world-shift-hours'] });
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
  Object.assign(process.env, { WORLD_URL: 'https://world.test', WORLD_PROJECT_TOKENS: `vung_tau=${TOKEN}`, GH_TOKEN: 'g', REPOSITORY: 'o/r' });
  return import('../../scripts/shift-issues.mjs');
}

test('a request whose parts are built: the issue gets the parts lists and closes', async () => {
  const fake = world();
  const { handle } = await load(fake);
  await handle(5, parse(form()), 'request');
  assert.deepEqual(fake.factory.map((f) => f.path), ['/o/0123456789abcdef0123456789abcdef.mid.elements.json', `/p/${'a'.repeat(32)}.glb`, `/p/${'b'.repeat(32)}.glb`]);
  assert.ok(fake.factory.every((f) => f.auth === `Bearer ${TOKEN}`));
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
  await handle(9, parse(form({ project: 'other' })), 'request');
  assert.match(fake.github[1].body.body, /The project other has no token/);
  await handle(9, parse(form()), 'request');
  assert.match(fake.github[2].body.body, /The factory refused the request: the parts list .*: 422/);
  assert.equal(await handle(9, parse(form()), 'check'), null);
  assert.equal(requestOf([{ user: { login: 'github-actions[bot]' }, body: 'no mark' }]), null);
  // A part that does not answer in time counts as not built.
  globalThis.fetch = () => Promise.reject(new Error('down'));
  assert.deepEqual(await ask([{ parts: [{ key: 'a' }] }], TOKEN, 5.5), { keys: 1, left: 1 });
});
