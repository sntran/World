#!/usr/bin/env node
// The store of the passes of the construction shifts on this computer
// (shift_store.js), with a file of JSON: WORLD_SHIFT_FILE. The edge has
// the SQLite of its Durable Object in place of the file. With no file, the
// program ends with the exit status 1.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { Readable } from 'node:stream';
import { shiftStore } from '../shift_store.js';

const write = (part) => new Promise((resolve) => process.stdout.write(part, resolve));

const file = process.env.WORLD_SHIFT_FILE;

const rows = async () => JSON.parse(await readFile(file, 'utf8').catch(() => '{}'));

const save = async (map) => {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(map));
};

const table = {
  async put(row) {
    await save({ ...(await rows()), [row.pass]: row });
  },
  async drop(pass) {
    const map = await rows();
    delete map[pass];
    await save(map);
  },
  async all() {
    return Object.values(await rows()).sort((a, b) => a.at - b.at || (a.pass < b.pass ? -1 : 1));
  },
};

process.stdout.on('error', () => process.exit(1));
try {
  if (!file) throw new Error('no WORLD_SHIFT_FILE');
  const result = await shiftStore(table).port(Readable.toWeb(process.stdin), { argv: process.argv.slice(2) });
  for await (const part of result) await write(part);
  process.exit(0);
} catch {
  process.exit(1);
}
