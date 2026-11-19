// The tests of the env that the class Beam of worker.js gives to the VM
// (vm_env.js): the vars, the bindings and the ports, with no secret.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SECRETS, vmEnv } from '../../vm_env.js';

test('the VM gets the vars, the bindings and the ports of the Worker, and none of the three secrets', () => {
  const ORDERS = { get() {} };
  const env = {
    WORLD_SERVER: 'true', DIST_NAME: 'world@127.0.0.1', ORDERS,
    WORLD_SHIFT_TOKEN: 'github_pat_x', WORLD_TOKEN: 't'.repeat(40), WORLD_STORE_TOKEN: 's'.repeat(40),
  };
  const port = { port() {} };
  const copy = vmEnv(env, { ORDER_STORE: port });
  assert.deepEqual(SECRETS, ['WORLD_SHIFT_TOKEN', 'WORLD_TOKEN', 'WORLD_STORE_TOKEN']);
  assert.deepEqual(copy, { WORLD_SERVER: 'true', DIST_NAME: 'world@127.0.0.1', ORDERS, ORDER_STORE: port });
  for (const name of SECRETS) assert.equal(name in copy, false, name);
  // The env of the Worker keeps its secrets (handler.js and shift.js use them).
  assert.equal(env.WORLD_TOKEN, 't'.repeat(40));
  // A port does not put a secret back.
  assert.equal('WORLD_TOKEN' in vmEnv(env, { WORLD_TOKEN: 'x' }), false);
  assert.deepEqual(vmEnv({ A: '1' }), { A: '1' });
});

test('the class Beam of worker.js gives the VM the env of vmEnv', () => {
  // (worker.js imports edge.com as bytes, which Node.js cannot import: the
  // test reads its text. The test with the local edge checks the VM itself.)
  const source = readFileSync(new URL('../../worker.js', import.meta.url), 'utf8');
  assert.match(source, /super\(ctx, vmEnv\(env, \{/);
  assert.doesNotMatch(source, /\.\.\.env/);
});

test('the object of the VM takes only the WebSocket of the distribution on /.tcp/, from any version of the Worker', () => {
  const source = readFileSync(new URL('../../worker.js', import.meta.url), 'utf8');
  assert.match(source, /fetch\(request\) \{\n    if \(new URL\(request\.url\)\.pathname\.startsWith\('\/\.tcp\/'\) && !distribution\(request, this\.env\)\) return new Response\('no such page\\n', \{ status: 404 \}\);\n    return super\.fetch\(request\);/);
});
