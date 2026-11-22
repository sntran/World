// The tests of wrangler.jsonc: a Preview of a branch has a bucket of its
// own and no secret of the site (docs/factory.md, "The setup on
// Cloudflare").
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SECRETS } from '../../vm_env.js';

// (The comments of wrangler.jsonc are whole lines.)
const config = JSON.parse(
  readFileSync(new URL('../../wrangler.jsonc', import.meta.url), 'utf8')
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n'),
);

test('a Preview uses the bucket world-previews, not a bucket of the site', () => {
  const site = config.r2_buckets.map((b) => b.bucket_name);
  const previews = config.previews.r2_buckets.map((b) => b.bucket_name);
  assert.deepEqual(site, ['world']);
  assert.deepEqual(previews, ['world-previews']);
  for (const name of previews) assert.equal(site.includes(name), false, name);
  // The same binding, so the code is the same.
  assert.deepEqual(config.previews.r2_buckets.map((b) => b.binding), config.r2_buckets.map((b) => b.binding));
});

test('wrangler.jsonc gives no secret, to the site or to a Preview', () => {
  for (const vars of [config.vars, config.previews.vars]) {
    for (const name of SECRETS) assert.equal(name in vars, false, name);
  }
});
