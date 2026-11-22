// The record of the starts and the ends of the VM (isolates.js).
import assert from 'node:assert/strict';
import test from 'node:test';
import { PREFIX, causeOf, isolates, noteEnd, noteStart, stoppedAnswer } from '../../isolates.js';
import { bucket } from './fakes.js';

test('the word of the cause of an error of the runtime', () => {
  assert.equal(causeOf(new Error("Durable Object's isolate exceeded its memory limit and was reset.")), 'memory');
  assert.equal(causeOf(new Error('Durable Object exceeded its CPU time limit and was reset.')), 'cpu');
  assert.equal(causeOf(new Error('Durable Object reset because its code was updated.')), 'deploy');
  assert.equal(causeOf(new Error('The Durable Object was reset.')), 'reset');
  assert.equal(causeOf(new Error('Network connection lost.')), 'connection');
  assert.equal(causeOf(new Error('something else')), 'other');
  assert.equal(causeOf(null), 'other');
});

test('the answer of beam.com for a VM that stopped itself, and no other answer', async () => {
  const text = (body, status = 503, type = 'text/plain') => new Response(body, { status, headers: { 'content-type': type, 'retry-after': '1' } });
  const stopped = text('The app stopped. Try again.\n');
  assert.equal(await stoppedAnswer(stopped), true);
  // (The answer goes out as it is.)
  assert.equal(await stopped.text(), 'The app stopped. Try again.\n');
  assert.equal(await stoppedAnswer(text('down')), false);
  assert.equal(await stoppedAnswer(text('{"errors": []}', 503, 'application/json')), false);
  assert.equal(await stoppedAnswer(text('The app stopped. Try again.\n', 200)), false);
  assert.equal(await stoppedAnswer(undefined), false);
  const orders = bucket();
  await noteEnd(orders, 'stopped', Date.parse('2026-11-22T01:53:20Z'));
  assert.deepEqual([...orders.items.keys()], ['isolates/2026-11-22T01:53:20.000Z.end.stopped']);
});

test('the record: each start of a VM, and the cause of the end before each start after the first', async () => {
  const orders = bucket();
  const at = (s) => Date.parse(`2026-11-21T${s}Z`);
  const now = at('12:00:00');
  // (An event of 8 days before is out of the record.)
  await noteStart(orders, 'old', now - 8 * 86_400_000);
  await noteStart(orders, 'a'.repeat(40), at('08:00:00'));
  // Two requests that failed at one end: the cause of the last one.
  await noteEnd(orders, new Error('connection lost'), at('08:10:00'));
  await noteEnd(orders, new Error('exceeded its memory limit'), at('08:10:01'));
  await noteStart(orders, 'a'.repeat(40), at('08:10:05'));
  // No failed request, and another commit: a deploy; the same commit: an idle end.
  await noteStart(orders, 'b'.repeat(40), at('09:00:00'));
  await noteStart(orders, 'b'.repeat(40), at('10:00:00'));
  // A failed request after the last start, and a key that is not an event.
  await noteEnd(orders, new Error('cpu time'), at('11:00:00'));
  await orders.put(`${PREFIX}note.txt`, 'x');
  await orders.put('parts/x.glb', 'glTF');

  const r = await isolates(orders, now);
  assert.equal(r.since, '2026-11-14T12:00:00.000Z');
  assert.deepEqual(r.starts.map((s) => s.commit), ['aaaaaaaaaaaa', 'aaaaaaaaaaaa', 'bbbbbbbbbbbb', 'bbbbbbbbbbbb']);
  assert.deepEqual(r.ends, [
    { before: '2026-11-21T08:10:05.000Z', cause: 'memory', failed: 2, at: '2026-11-21T08:10:01.000Z' },
    { before: '2026-11-21T09:00:00.000Z', cause: 'deploy', failed: 0 },
    { before: '2026-11-21T10:00:00.000Z', cause: 'idle', failed: 0 },
  ]);
  assert.deepEqual(r.causes, { memory: 1, deploy: 1, idle: 1 });
  assert.deepEqual(r.failed, [{ at: '2026-11-21T11:00:00.000Z', cause: 'cpu' }]);
  // (Each event is a key with no content.)
  for (const [key, bytes] of orders.items) if (key.startsWith(PREFIX) && !key.endsWith('.txt')) assert.equal(bytes.byteLength, 0);

  // Many pages of the list; a start with no commit.
  const many = bucket();
  for (let i = 0; i < 1001; i++) await noteStart(many, undefined, at('08:00:00') + i * 1000);
  const all = await isolates(many, now);
  assert.equal(all.starts.length, 50);
  assert.equal(all.starts[0].commit, 'unknown');
  assert.equal(all.ends.length, 50);
  assert.deepEqual(all.causes, { idle: 1000 });
});
