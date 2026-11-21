// The record of the memory of the VM (scripts/memory-record.mjs), with a
// fake census.
import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { COLUMNS, record, row, summary } from '../../scripts/memory-record.mjs';

const census = (size, used, top) => ({
  people: [],
  memory: { wasm: { size: size * 1e6, used: used * 1e6 }, processes: { count: 300, bytes: 20e6 }, binaries: 5e6, ets: 1e6, persistent_terms: 2e6, top: [{ name: top, bytes: 9e6 }, { name: ':code_server', bytes: 1e6 }], tables: [] },
});

test('a line of the record, from the census', () => {
  assert.deepEqual(row(new Date(0), census(60, 40, ':log')), ['1970-01-01T00:00:00.000Z', '60.0', '40.0', 300, '20.0', '5.0', '1.0', '2.0', '":log"', '9.0']);
  // (A VM that does not run in WebAssembly.)
  assert.equal(row(new Date(0), { memory: { processes: { count: 1, bytes: 1 } } })[1], '');
});

test('the record looks each SECONDS for MINUTES, writes the CSV, and gives the least, the most, the starts of the VM and the biggest processes', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'memory-'));
  const out = join(dir, 'memory.csv');
  let t = 0;
  const answers = [census(60, 40, ':log'), census(80, 70, ':log'), null, census(30, 25, ':files'), census(31, 26, ':files')];
  const fetcher = async (url) => {
    assert.equal(url, 'https://w/census');
    const a = answers.shift();
    return a ? Response.json(a) : new Response('down', { status: 503 });
  };
  const logs = [];
  const result = await record('https://w', 10, 50 / 60, out, { fetch: fetcher, now: () => new Date(t), wait: async (ms) => (t += ms), log: (l) => logs.push(l) });
  assert.equal(result.looks, 4);
  assert.deepEqual(result.values.find((v) => v.value === 'wasm_size'), { value: 'wasm_size', least: 30, most: 80, first: 60, last: 31 });
  assert.deepEqual(result.starts, ['1970-01-01T00:00:30.000Z']);
  assert.deepEqual(result.biggest.map((b) => b.name), [':log', ':files', ':code_server']);
  assert.match(logs[0], /no census at 1970-01-01T00:00:20.000Z \(503\)/);
  const csv = (await readFile(out, 'utf8')).trim().split('\n');
  assert.equal(csv[0], COLUMNS.join(','));
  assert.equal(csv.length, 5);
  assert.deepEqual(summary([], new Map()), { looks: 0, values: [], starts: [], biggest: [] });
});
