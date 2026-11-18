#!/usr/bin/env node
// The link of a native node to the node of the edge (docs/factory.md,
// "The labour of native nodes"): each connection to a local port becomes
// a WebSocket (TLS) to /.tcp/4370 of the Worker, with the token of the
// link. The native node connects to the node of the edge through it
// (world@127.0.0.1, World.Epmd: the port 4370 of 127.0.0.1), so no node
// has an open port.
//
//   WORLD_LINK_TOKEN=... node scripts/link.mjs 4370 wss://world.mkfifo.com/.tcp/4370
import net from 'node:net';
import { WebSocket } from 'ws';

const [localPort, url] = process.argv.slice(2);
const token = process.env.WORLD_LINK_TOKEN;
if (!localPort || !url || !token) {
  console.error('usage: WORLD_LINK_TOKEN=TOKEN node scripts/link.mjs LOCAL_PORT WSS_URL');
  process.exit(2);
}

net.createServer((sock) => {
  sock.pause();
  sock.setNoDelay(true);
  const ws = new WebSocket(url, { headers: { authorization: `Bearer ${token}` } });
  ws.binaryType = 'nodebuffer';
  ws.on('open', () => {
    sock.on('data', (d) => ws.send(d, { binary: true }));
    sock.resume();
  });
  ws.on('message', (d) => sock.write(d));
  ws.on('close', () => sock.end());
  ws.on('error', (e) => {
    console.error(`link: ${e.message}`);
    sock.destroy();
  });
  sock.on('close', () => ws.close());
  sock.on('error', () => ws.close());
}).listen(Number(localPort), '127.0.0.1', () => console.error(`link: 127.0.0.1:${localPort} -> ${url}`));
