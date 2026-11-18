#!/usr/bin/env node
// The time from an edit of an order to its whole new level, as a project
// gets it (docs/factory.md, "The parts of a model"):
//
//   node scripts/edit-time.mjs BASE HASH LEVEL EDITS
//
// BASE is the factory (https://world.mkfifo.com), HASH an order of POST
// /orders, LEVEL near, mid or far, and EDITS the edits in JSON
// ('[{"set": "options.storey", "to": 3.4}]', or - for no edit: the level
// of the order as it is). The script makes the edit
// (POST /orders/HASH/edits), gets the parts list of the new order at the
// level, then asks for each part at the same time (a construction shift
// builds the large parts at the same time, World.Labour), and asks again
// after each 202. It prints the time of each step and of each part, and
// the time to the last part. WORLD_TOKEN: the token of a project, so
// that the parts that do not fit the edge go to a construction shift;
// WORLD_SHIFT_HOURS: the hours of a shift that the request starts.

const [base, hash, level, edits] = process.argv.slice(2);
if (!base || !hash || !level || !edits) {
  console.error('usage: node scripts/edit-time.mjs BASE HASH LEVEL EDITS');
  process.exit(2);
}

const auth = process.env.WORLD_TOKEN ? { authorization: `Bearer ${process.env.WORLD_TOKEN}` } : {};
if (process.env.WORLD_SHIFT_HOURS) auth['x-world-shift-hours'] = process.env.WORLD_SHIFT_HOURS;
const start = Date.now();
const seconds = () => ((Date.now() - start) / 1000).toFixed(1);
const wait = (s) => new Promise((done) => setTimeout(done, s * 1000));

// A GET until its answer is not 202 (the build goes on after a 202).
async function get(url) {
  for (;;) {
    const r = await fetch(url, { headers: auth });
    if (r.status !== 202) return r;
    await r.arrayBuffer();
    await wait(Number(r.headers.get('retry-after') ?? 15));
  }
}

let order = { hash };
if (edits !== '-') {
  const edit = await fetch(`${base}/orders/${hash}/edits`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...auth },
    body: JSON.stringify({ edits: JSON.parse(edits) }),
  });
  order = await edit.json();
  if (edit.status !== 200) {
    console.error(`the edit: ${edit.status} ${JSON.stringify(order)}`);
    process.exit(1);
  }
  console.log(`${seconds()} s: the edit, the new order ${order.hash}`);
}

const suffix = level === 'near' ? 'elements.json' : `${level}.elements.json`;
const answer = await get(`${base}/o/${order.hash}.${suffix}`);
const list = await answer.json();
if (answer.status !== 200) {
  console.error(`the parts list: ${answer.status} ${JSON.stringify(list)}`);
  process.exit(1);
}
console.log(`${seconds()} s: the parts list, ${list.parts.length} parts`);

const keys = [...new Set(list.parts.map((p) => p.key))];
const results = await Promise.all(keys.map(async (key) => {
  const from = Date.now();
  const r = await get(`${base}/p/${key}.glb`);
  const bytes = (await r.arrayBuffer()).byteLength;
  const part = list.parts.find((p) => p.key === key).part;
  console.log(`${seconds()} s: ${part} ${r.status}, ${bytes} B, ${((Date.now() - from) / 1000).toFixed(1)} s`);
  return r.status;
}));

const bad = results.filter((s) => s !== 200).length;
console.log(`${seconds()} s: the whole ${level} level of ${order.hash}: ${keys.length} parts, ${bad} not built`);
process.exit(bad ? 1 : 0);
