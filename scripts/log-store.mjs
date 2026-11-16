#!/usr/bin/env node
// The store of the log of the node on this computer: the port program of
// World.Log.Store in development and in the tests. It runs the code of
// the Worker (log_store.js) with a file of lines in place of the SQLite
// of the Durable Object: WORLD_LOG_FILE.
//
//   WORLD_LOG_FILE=tmp/log.jsonl scripts/log-store.mjs read 0 100
import { appendFile, mkdir, readFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { Readable } from 'node:stream';
import { logStore } from '../log_store.js';

const write = (part) => new Promise((resolve) => process.stdout.write(part, resolve));

const file = process.env.WORLD_LOG_FILE;

// The lines of the file, each with its id, in the order of the ids.
const rows = async () => {
  const text = await readFile(file, 'utf8').catch(() => '');
  const lines = text.split('\n').filter(Boolean);
  return lines.map((line) => ({ id: JSON.parse(line).id, line })).sort((a, b) => a.id - b.id);
};

const table = {
  async append(list) {
    await mkdir(dirname(file), { recursive: true });
    await appendFile(file, list.map((r) => `${r.line}\n`).join(''));
  },
  async after(id, limit) {
    return (await rows()).filter((r) => r.id > id).slice(0, limit).map((r) => r.line);
  },
  async last() {
    return (await rows()).reduce((n, r) => Math.max(n, r.id), 0);
  },
};

// An error ends the port with the exit status 1, as at the edge.
process.stdout.on('error', () => process.exit(1));
try {
  if (!file) throw new Error('no WORLD_LOG_FILE');
  const result = await logStore(table).port(Readable.toWeb(process.stdin), { argv: process.argv.slice(2) });
  for await (const part of result) await write(part);
  process.exit(0);
} catch {
  process.exit(1);
}
