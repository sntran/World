#!/usr/bin/env node
// A shift on this computer (docs/factory.md, "Construction shifts"): a
// server in the place of the API of GitHub for a local edge (wrangler
// dev with --var WORLD_SHIFT_API:http://127.0.0.1:PORT). Each start of
// the workflow shift.yml runs scripts/shift.sh here, with the inputs of
// the start, in the place of a runner:
//
//   node scripts/shift-local.mjs PORT
//
// The shift gets this environment, with WORLD_URL (the local edge) and
// WORLD_STORE_TOKEN (the token of the store of the test, which also
// joins the shift: there is no ID token here). Its files (the
// log shift-N.log, the summary) go to RUNNER_TEMP (the current folder by
// default).
import { spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { createServer } from 'node:http';
import { join } from 'node:path';

const port = Number(process.argv[2] ?? 8790);
const temp = process.env.RUNNER_TEMP ?? process.cwd();
let n = 0;

createServer((req, res) => {
  let body = '';
  req.on('data', (d) => (body += d));
  req.on('end', () => {
    if (req.method !== 'POST' || !/\/actions\/workflows\/shift\.yml\/dispatches$/.test(req.url)) {
      res.writeHead(404).end();
      return;
    }
    const { inputs } = JSON.parse(body);
    const hours = Number(inputs.hours ?? '5.5');
    const minutes = Math.max(Math.min(hours * 60, 330), 30) - 15;
    n += 1;
    const log = createWriteStream(join(temp, `shift-${n}.log`));
    const env = { ...process.env, WORLD_SHIFT_UNTIL: String(Math.floor(Date.now() / 1000) + minutes * 60), WORLD_SHIFT_IDLE: process.env.WORLD_SHIFT_IDLE ?? '60', RUNNER_TEMP: temp };
    const shift = spawn('sh', ['scripts/shift.sh'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    shift.stdout.pipe(log);
    shift.stderr.pipe(log);
    console.log(`${new Date().toISOString()} shift ${n}: started for ${inputs.commit}, ${minutes} minutes`);
    shift.on('exit', (code) => console.log(`${new Date().toISOString()} shift ${n}: ended with ${code}`));
    res.writeHead(204).end();
  });
}).listen(port, '127.0.0.1', () => console.log(`the API of GitHub for shifts on 127.0.0.1:${port}`));
