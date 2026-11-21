// The ID tokens of GitHub Actions (OIDC) for the Worker (docs/factory.md,
// "The secrets"). A job with "permissions: id-token: write" asks GitHub
// for a token with the audience of the factory; the token is a JWT that
// GitHub signs (RS256). The Worker checks:
//
// - the signature, with the keys of GitHub (JWKS), which it keeps for an
//   hour, and gets again for a key that it does not know;
// - iss (GitHub), aud (the factory), exp and nbf (with 60 s of leeway);
// - the claims of the caller (who()): a shift (shift.yml of the repository
//   of World on main), the job of an issue (shift-request.yml), the check
//   of the bucket (bucket-check.yml), or a project (a job of a repository
//   of my account: repository_owner_id, the number of the account, not
//   only its name).

export const ISSUER = 'https://token.actions.githubusercontent.com';
export const JWKS = `${ISSUER}/.well-known/jwks`;
export const AUDIENCE = 'https://world.mkfifo.com';
const HOUR = 3600_000;
const LEEWAY = 60;

let cache = { keys: null, at: 0 };

// (For the tests: the cache of the keys starts again.)
export function forget() {
  cache = { keys: null, at: 0 };
}

const text = (bytes) => new TextDecoder().decode(bytes);

function base64url(s) {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4));
  return Uint8Array.from(b, (c) => c.charCodeAt(0));
}

async function keys(fetcher, now, fresh) {
  if (!fresh && cache.keys && now - cache.at < HOUR) return cache.keys;
  const r = await fetcher(JWKS);
  if (!r.ok) throw new Error(`the keys of GitHub: ${r.status}`);
  cache = { keys: (await r.json()).keys ?? [], at: now };
  return cache.keys;
}

// The claims of a good token, or null. options: fetch (for the keys),
// now (ms), audience.
export async function verify(token, { fetch: fetcher = globalThis.fetch, now = Date.now(), audience = AUDIENCE } = {}) {
  try {
    const [h, p, s] = String(token ?? '').split('.');
    if (!h || !p || !s) return null;
    const header = JSON.parse(text(base64url(h)));
    if (header.alg !== 'RS256' || typeof header.kid !== 'string') return null;
    let jwk = (await keys(fetcher, now, false)).find((k) => k.kid === header.kid);
    // (A key that the cache does not have: GitHub can have a new key. Once a minute at most.)
    if (!jwk && now - cache.at > 60_000) jwk = (await keys(fetcher, now, true)).find((k) => k.kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey('jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true }, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const good = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, base64url(s), new TextEncoder().encode(`${h}.${p}`));
    if (!good) return null;
    const claims = JSON.parse(text(base64url(p)));
    const seconds = now / 1000;
    const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (claims.iss !== ISSUER || !aud.includes(audience)) return null;
    if (typeof claims.exp !== 'number' || claims.exp + LEEWAY < seconds) return null;
    if (typeof claims.nbf === 'number' && claims.nbf - LEEWAY > seconds) return null;
    return claims;
  } catch {
    return null;
  }
}

// Who a job is, from its claims: { kind: 'shift' | 'request' | 'check' |
// 'project', project } or null. env: WORLD_OWNER_ID (the number of my
// account), WORLD_SHIFT_REPOSITORY (sntran/World).
export function who(claims, env) {
  if (!claims || String(claims.repository_owner_id ?? '') !== String(env.WORLD_OWNER_ID ?? '-')) return null;
  const repository = env.WORLD_SHIFT_REPOSITORY ?? 'sntran/World';
  const ref = String(claims.job_workflow_ref ?? '');
  // (The whole ref: a branch main-test is not main.)
  if (claims.repository === repository) {
    if (ref === `${repository}/.github/workflows/shift.yml@refs/heads/main`) return { kind: 'shift' };
    if (ref === `${repository}/.github/workflows/shift-request.yml@refs/heads/main`) return { kind: 'request' };
    if (ref === `${repository}/.github/workflows/bucket-check.yml@refs/heads/main`) return { kind: 'check' };
  }
  const name = String(claims.repository ?? '').split('/')[1]?.toLowerCase() ?? '';
  return /^[a-z0-9_.-]{1,100}$/.test(name) ? { kind: 'project', project: name } : null;
}
