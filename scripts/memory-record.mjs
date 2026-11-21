#!/usr/bin/env node
// A record of the memory of the VM of the edge (docs/factory.md, "The
// memory of the VM"): GET BASE/census each SECONDS seconds for MINUTES
// minutes, one line of CSV for each look, and at the end the least, the
// most and the change of each value, and the biggest processes.
//
//   node scripts/memory-record.mjs BASE SECONDS MINUTES OUT.csv
//
// BASE is the factory (https://world.mkfifo.workers.dev). A start of the
// VM shows as a drop of the memory of WebAssembly (it never gets smaller
// in one VM). The look itself keeps the VM awake.
import { appendFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const COLUMNS = ['time', 'wasm_size', 'wasm_used', 'processes', 'process_bytes', 'binaries', 'ets', 'persistent_terms', 'top', 'top_bytes'];

const MB = (bytes) => (bytes == null ? '' : (bytes / 1e6).toFixed(1));

// The line of a look, from the census.
export function row(time, census) {
  const m = census.memory ?? {};
  const top = m.top?.[0] ?? {};
  return [time.toISOString(), MB(m.wasm?.size), MB(m.wasm?.used), m.processes?.count ?? '', MB(m.processes?.bytes), MB(m.binaries), MB(m.ets), MB(m.persistent_terms), JSON.stringify(top.name ?? ''), MB(top.bytes)];
}

// The least, the most, the first and the last value of each column, the
// starts of the VM (the size of WebAssembly gets smaller), and the
// processes that were the biggest at a look.
export function summary(rows, tops) {
  const out = [];
  for (const [i, name] of COLUMNS.entries()) {
    if (['time', 'top'].includes(name)) continue;
    const values = rows.map((r) => r[i]).filter((v) => v !== '').map(Number);
    if (values.length === 0) continue;
    out.push({ value: name, least: Math.min(...values), most: Math.max(...values), first: values[0], last: values.at(-1) });
  }
  const sizes = rows.map((r) => Number(r[1]));
  const starts = rows.filter((r, i) => i > 0 && sizes[i] < sizes[i - 1]).map((r) => r[0]);
  const biggest = [...tops.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([name, bytes]) => ({ name, most: MB(bytes) }));
  return { looks: rows.length, values: out, starts, biggest };
}

export async function record(base, seconds, minutes, out, { fetch: fetcher = fetch, now = () => new Date(), wait = (ms) => new Promise((done) => setTimeout(done, ms)), log = console.log } = {}) {
  await writeFile(out, `${COLUMNS.join(',')}\n`);
  const rows = [];
  const tops = new Map();
  const end = now().getTime() + minutes * 60_000;
  while (now().getTime() < end) {
    const r = await fetcher(`${base}/census`).catch(() => null);
    const census = r?.ok ? await r.json().catch(() => null) : null;
    if (census?.memory) {
      const line = row(now(), census);
      rows.push(line);
      for (const p of census.memory.top ?? []) tops.set(p.name, Math.max(tops.get(p.name) ?? 0, p.bytes));
      await appendFile(out, `${line.join(',')}\n`);
    } else log(`memory: no census at ${now().toISOString()} (${r?.status ?? 'no answer'})`);
    await wait(seconds * 1000);
  }
  return summary(rows, tops);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const [base, seconds, minutes, out] = process.argv.slice(2);
  if (!base || !(Number(seconds) > 0) || !(Number(minutes) > 0) || !out) {
    console.error('usage: node scripts/memory-record.mjs BASE SECONDS MINUTES OUT.csv');
    process.exit(2);
  }
  console.log(JSON.stringify(await record(base, Number(seconds), Number(minutes), out), null, 1));
}
