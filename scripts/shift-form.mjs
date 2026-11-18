// The issue form "A construction shift" (.github/ISSUE_TEMPLATE/
// construction_shift.yml) as data, and the comment of an issue whose
// parts are built (docs/factory.md, "Construction shifts"). The text of
// an issue is input of a user: it gives only checked values, and no part
// of it goes into a shell command.

const PROJECT = /^[a-z0-9_-]{1,40}$/;
const HASH = /^[0-9a-f]{32}$/;
const ORDERS = /^https:\/\/github\.com\/([A-Za-z0-9_.-]{1,100})\/([A-Za-z0-9_.-]{1,100})\/blob\/([0-9a-f]{40})\/((?:[A-Za-z0-9_-][A-Za-z0-9_.-]*\/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*\.json)$/;
const LEVELS = ['near', 'mid', 'far'];
export const MOST_ORDERS = 200;

// The sections of the body of an issue form: "### Label", then its value.
export function sections(body) {
  const out = {};
  let name = null;
  for (const line of String(body ?? '').split(/\r?\n/)) {
    const head = /^###\s+(.+?)\s*$/.exec(line);
    if (head) {
      name = head[1];
      out[name] = [];
    } else if (name) out[name].push(line);
  }
  for (const k of Object.keys(out)) out[k] = out[k].join('\n').trim();
  return out;
}

// The request of an issue: { project, orders: { url } | { hashes }, levels,
// hours }, or { errors }.
export function parse(body) {
  const s = sections(body);
  const errors = [];
  const none = (v) => v === undefined || v === '' || v === '_No response_';

  const project = s.Project;
  if (none(project) || !PROJECT.test(project)) errors.push('The project: letters a to z, digits, _ and -, 40 at most.');

  let orders = null;
  const lines = none(s.Orders) ? [] : s.Orders.split('\n').map((l) => l.trim()).filter(Boolean);
  if (lines.length === 1 && ORDERS.test(lines[0])) {
    const [, owner, repository, commit, path] = ORDERS.exec(lines[0]);
    orders = { url: `https://raw.githubusercontent.com/${owner}/${repository}/${commit}/${path}` };
  } else if (lines.length > 0 && lines.length <= MOST_ORDERS && lines.every((l) => HASH.test(l))) {
    orders = { hashes: [...new Set(lines)] };
  } else {
    errors.push(`The orders: one link to orders.json at a commit (https://github.com/OWNER/REPOSITORY/blob/COMMIT/PATH.json, with the 40 digits of the commit), or 1 to ${MOST_ORDERS} hashes of orders, one on each line.`);
  }

  const levels = LEVELS.filter((l) => new RegExp(`^- \\[[xX]\\] ${l}\\b`, 'm').test(s.Levels ?? ''));
  if (levels.length === 0) errors.push('The levels: near, mid or far, one or more.');

  let hours = 5.5;
  if (!none(s.Hours)) {
    hours = Number(s.Hours);
    if (!/^\d+(\.\d+)?$/.test(s.Hours) || hours < 0.5 || hours > 5.5) errors.push('The hours: a number from 0.5 to 5.5.');
  }

  return errors.length ? { errors } : { project, orders, levels, hours };
}

// The orders of a file orders.json of a project: a list, or an object
// with a list "orders" or "models". Each entry is an order, or an object
// with the order in "order" (Vũng Tàu, plan 0023, R1).
export function ordersOf(json) {
  const list = Array.isArray(json) ? json : (json?.orders ?? json?.models);
  if (!Array.isArray(list) || list.length === 0) throw new Error('orders.json has no list of orders');
  if (list.length > MOST_ORDERS) throw new Error(`orders.json has more than ${MOST_ORDERS} orders`);
  return list.map((entry) => {
    const order = entry?.order ?? entry;
    if (typeof order?.blueprint !== 'string') throw new Error('an entry of orders.json has no order with a blueprint');
    return order;
  });
}

// The token of a project in NAME=TOKEN,NAME=TOKEN (the secret
// WORLD_PROJECT_TOKENS), or null.
export function tokenOf(tokens, project) {
  for (const entry of String(tokens ?? '').split(',')) {
    const [name, token] = entry.trim().split('=', 2);
    if (name === project && (token ?? '').length >= 32) return token;
  }
  return null;
}

// The comment of an issue whose parts are built: each parts list, with
// its URL and the URL of each part.
export function doneComment(lists) {
  const lines = ['The construction shift built each part. The parts lists:', ''];
  for (const l of lists) {
    lines.push(`- \`${l.hash}\` at ${l.level}: ${l.url} (${l.parts.length} parts)`);
    for (const p of l.parts) lines.push(`  - ${p.part}: ${p.url}`);
  }
  return lines.join('\n');
}
