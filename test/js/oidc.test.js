// The tests of oidc.js: the ID tokens of GitHub Actions, signed here
// with a test key (RS256), and the keys of GitHub from a fake fetch.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { AUDIENCE, ISSUER, JWKS, forget, verify, who } from '../../oidc.js';

const OWNER = '973206';
const NOW = Date.parse('2026-11-18T10:00:00Z');
const seconds = NOW / 1000;

const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const other = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'key-1', use: 'sig' };

const b64 = (bytes) => Buffer.from(bytes).toString('base64url');
const part = (object) => b64(new TextEncoder().encode(JSON.stringify(object)));

// A token of GitHub Actions: these claims over the claims of a shift.
export async function token(claims = {}, { key = pair.privateKey, kid = 'key-1', alg = 'RS256' } = {}) {
  const body = {
    iss: ISSUER,
    aud: AUDIENCE,
    exp: seconds + 300,
    nbf: seconds - 10,
    repository: 'sntran/World',
    repository_owner: 'sntran',
    repository_owner_id: OWNER,
    job_workflow_ref: 'sntran/World/.github/workflows/shift.yml@refs/heads/main',
    run_id: '19000000001',
    run_attempt: '1',
    ...claims,
  };
  const head = `${part({ alg, kid, typ: 'JWT' })}.${part(body)}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(head));
  return `${head}.${b64(new Uint8Array(signature))}`;
}

// The keys of GitHub, and the count of their fetches.
function github(keys = [jwk]) {
  const calls = [];
  const fetch = async (url) => {
    calls.push(url);
    return keys ? Response.json({ keys }) : new Response('', { status: 500 });
  };
  return { calls, fetch };
}

test('a good token of a shift: its claims, with the keys of GitHub in a cache', async () => {
  forget();
  const g = github();
  const claims = await verify(await token(), { fetch: g.fetch, now: NOW });
  assert.equal(claims.repository, 'sntran/World');
  assert.deepEqual(who(claims, { WORLD_OWNER_ID: OWNER }), { kind: 'shift' });
  await verify(await token(), { fetch: g.fetch, now: NOW + 1000 });
  assert.deepEqual(g.calls, [JWKS]);
  // After an hour, the keys come again; an audience in a list.
  await verify(await token({ aud: ['x', AUDIENCE] }), { fetch: g.fetch, now: NOW + 3600_000 });
  assert.equal(g.calls.length, 2);
});

test('the job of an issue, and a project: a job of a repository of the owner, by the number of the account', async () => {
  const env = { WORLD_OWNER_ID: OWNER };
  assert.deepEqual(who({ repository: 'sntran/World', repository_owner_id: OWNER, job_workflow_ref: 'sntran/World/.github/workflows/shift-request.yml@refs/heads/main' }, env), { kind: 'request' });
  assert.deepEqual(who({ repository: 'sntran/Vung_Tau', repository_owner_id: OWNER, job_workflow_ref: 'sntran/Vung_Tau/.github/workflows/world.yml@refs/heads/main' }, env), { kind: 'project', project: 'vung_tau' });
  // Another owner with the same name: not the number of the account.
  assert.equal(who({ repository: 'sntran/Vung_Tau', repository_owner: 'sntran', repository_owner_id: '1' }, env), null);
  assert.equal(who({ repository: 'sntran/World', repository_owner_id: OWNER }, {}), null);
  assert.equal(who(null, env), null);
  assert.equal(who({ repository: 'sntran/x y', repository_owner_id: OWNER }, env), null);
});

test('another repository, another workflow, or another branch is not a shift', async () => {
  forget();
  const env = { WORLD_OWNER_ID: OWNER };
  const g = github();
  const check = async (claims) => who(await verify(await token(claims), { fetch: g.fetch, now: NOW }), env);
  // A workflow of World that is not shift.yml, or shift.yml of a branch: a project "world", not a shift.
  assert.equal((await check({ job_workflow_ref: 'sntran/World/.github/workflows/ci.yml@refs/heads/main' })).kind, 'project');
  assert.equal((await check({ job_workflow_ref: 'sntran/World/.github/workflows/shift.yml@refs/heads/feature' })).kind, 'project');
  // The whole ref: a branch whose name starts with main is not main.
  for (const ref of ['shift.yml@refs/heads/main-test', 'shift.yml@refs/heads/main/x', 'shift-request.yml@refs/heads/main2', 'shift.yml@refs/heads/mainx']) {
    assert.equal((await check({ job_workflow_ref: `sntran/World/.github/workflows/${ref}` })).kind, 'project', ref);
  }
  // A fork with another owner: nobody.
  assert.equal(await check({ repository: 'someone/World', repository_owner_id: '42', job_workflow_ref: 'someone/World/.github/workflows/shift.yml@refs/heads/main' }), null);
});

test('another audience, another issuer, an old token, a token of the future, a bad signature, and a token that is not a token', async () => {
  forget();
  const g = github();
  const v = async (t, now = NOW) => verify(t, { fetch: g.fetch, now });
  assert.equal(await v(await token({ aud: 'https://other.example' })), null);
  assert.equal(await v(await token({ iss: 'https://example.com' })), null);
  assert.equal(await v(await token({ exp: seconds - 61 })), null);
  assert.equal(await v(await token({ exp: undefined })), null);
  assert.equal(await v(await token({ nbf: seconds + 61 })), null);
  assert.equal(await v(await token({}, { key: other.privateKey })), null);
  // (Another algorithm, a key that GitHub does not have, and text that is not a JWT.)
  assert.equal(await v(await token({}, { alg: 'HS256' })), null);
  assert.equal(await v(await token({}, { kid: 'key-9' }), NOW + 120_000), null);
  assert.equal(await v('a.b'), null);
  assert.equal(await v('a.b.c'), null);
  assert.equal(await v(undefined), null);
  // The keys of GitHub do not come: no token is good.
  forget();
  assert.equal(await verify(await token(), { fetch: github(null).fetch, now: NOW }), null);
});
