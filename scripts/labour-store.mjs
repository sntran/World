#!/usr/bin/env node
// The store of the queue of the parts of the construction shifts on this
// computer (labour_store.js), with a file of JSON: WORLD_LABOUR_FILE. The
// edge has the SQLite of its Durable Object in place of the file. With no
// file, the program ends with the exit status 1. Two runs at one time
// take turns (a directory FILE.lock: mkdir is atomic), so no run writes
// over the change of another run.
import { mkdir, readFile, rmdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { Readable } from 'node:stream';
import { labourStore } from '../labour_store.js';

const write = (part) => new Promise((resolve) => process.stdout.write(part, resolve));

const file = process.env.WORLD_LABOUR_FILE;

const rows = async () => JSON.parse(await readFile(file, 'utf8').catch(() => '{}'));

const save = async (map) => {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(map));
};

const table = {
  async wait(key, ticket) {
    const map = await rows();
    map[key] ??= { key, ticket, node: null };
    await save(map);
    return map[key].ticket;
  },
  async give(key, node) {
    const map = await rows();
    if (map[key]) map[key].node = node;
    await save(map);
  },
  async back(key) {
    const map = await rows();
    if (map[key]) map[key].node = null;
    await save(map);
  },
  async done(key) {
    const map = await rows();
    delete map[key];
    delete map[`projects/${key}`];
    await save(map);
  },
  async ask(key, project) {
    const map = await rows();
    const list = (map[`projects/${key}`] ??= []);
    if (!list.includes(project)) list.push(project);
    await save(map);
  },
  async projects(key) {
    return (await rows())[`projects/${key}`] ?? [];
  },
  async all() {
    const order = (a, b) => a.ticket.length - b.ticket.length || (a.ticket < b.ticket ? -1 : a.ticket > b.ticket ? 1 : a.key < b.key ? -1 : 1);
    return Object.entries(await rows()).filter(([k]) => !k.startsWith('projects/')).map(([, row]) => row).sort(order);
  },
};

// The lock of the file, for at most 10 s.
async function locked(fun) {
  await mkdir(dirname(file), { recursive: true });
  const lock = `${file}.lock`;
  for (let i = 0; ; i++) {
    try {
      await mkdir(lock);
      break;
    } catch (e) {
      if (e.code !== 'EEXIST' || i >= 2000) throw e;
      await new Promise((done) => setTimeout(done, 5));
    }
  }
  try {
    return await fun();
  } finally {
    await rmdir(lock);
  }
}

process.stdout.on('error', () => process.exit(1));
try {
  if (!file) throw new Error('no WORLD_LABOUR_FILE');
  const text = await locked(async () => {
    const result = await labourStore(table).port(Readable.toWeb(process.stdin), { argv: process.argv.slice(2) });
    return new Response(result).text();
  });
  await write(text);
  process.exit(0);
} catch {
  process.exit(1);
}
