// The test of the world page (review/world.html) with a recorded stream of
// a construction (test/js/fixtures/world, from the people of the node):
// the page draws each element at its place, and counts the tasks. It
// needs Playwright with Chromium; with no Playwright, the test does not run.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { extname, join, normalize } from 'node:path';
import { test } from 'node:test';

let playwright = null;
try {
  playwright = createRequire(import.meta.url)('playwright');
} catch {
  playwright = null;
}

const root = new URL('../..', import.meta.url).pathname;
const types = { '.html': 'text/html', '.js': 'text/javascript', '.glb': 'model/gltf-binary', '.jsonl': 'application/x-ndjson' };

// A static server of the repository.
function serve() {
  const server = createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
    try {
      const body = await readFile(join(root, path));
      res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

test('the world page draws the map of the yard: the places, the lots at their places, the trucks', { skip: !playwright && 'no Playwright' }, async () => {
  const server = await serve();
  const browser = await playwright.chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const { port } = server.address();
    const yard = '/test/js/fixtures/yard';
    await page.goto(`http://127.0.0.1:${port}/review/world.html?events=${yard}/events.jsonl&places=${yard}/places.json&files=${yard}`);
    await page.waitForFunction(() => window.READY === true, null, { timeout: 60_000 });
    // Each place is open at the end of the first start.
    const states = await page.locator('#places tr').evaluateAll((rows) => rows.map((r) => [r.cells[0].textContent, r.cells[2].textContent]));
    assert.deepEqual(states, [['gate', 'open'], ['warehouse', 'open'], ['vehicles', 'open'], ['workshop', 'open'], ['site', 'open']]);
    // Each construction is on a lot at its place; the scooter at the factory of the vehicles.
    const lots = await page.evaluate(() => Object.fromEntries([...window.WORLD.builds.values()].map((b) => [b.id, [Math.round(b.group.position.x), Math.round(b.group.position.z)]])));
    const near = (id, x, y) => Math.abs(lots[id][0] - x) <= 30 && Math.abs(lots[id][1] + y) <= 30;
    assert.ok(near('b1-mid', 0, 0) && near('b2-mid', 160, 0) && near('s1-far', 160, 0), JSON.stringify(lots));
    const trucks = await page.evaluate(() => [...window.WORLD.trucks.keys()].sort());
    assert.deepEqual(trucks, ['rented_1', 'rented_2', 'rented_3', 'truck_1', 'truck_2']);
    assert.match(await page.locator('#counts').textContent(), /5 trucks/);
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.close();
  }
});

test('the world page draws the hill of Núi Nhỏ from the game, the sea, and a lot at the height of its ground', { skip: !playwright && 'no Playwright' }, async () => {
  const server = await serve();
  const browser = await playwright.chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const { port } = server.address();
    const hill = '/test/js/fixtures/hill';
    await page.goto(`http://127.0.0.1:${port}/review/world.html?events=${hill}/events.jsonl&places=${hill}/places.json&files=${hill}`);
    await page.waitForFunction(() => window.READY === true, null, { timeout: 60_000 });
    // The ground of the place: a mesh of the GLB, with a half turn; its top is the top of the hill.
    const ground = await page.evaluate(() => {
      const g = window.WORLD.places.get('nui_nho').ground;
      g.updateWorldMatrix(true, true);
      const meshes = [];
      g.traverse((o) => { if (o.isMesh) meshes.push(o); });
      // A Box3 of the three.js of the page: the class of the box of a geometry.
      const Box3 = meshes[0].geometry.boundingBox.constructor;
      const box = new Box3().setFromObject(g);
      return { meshes: meshes.length, turn: g.rotation.y, top: box.max.y, low: box.min.y };
    });
    assert.equal(ground.meshes, 1);
    assert.ok(Math.abs(ground.turn - Math.PI) < 1e-9);
    assert.ok(ground.top > 140 && ground.top < 180 && ground.low < 0, JSON.stringify(ground));
    // Each statue on its lot: the point of the game on the yard, at the height of its ground, its front to the south.
    const lots = await page.evaluate(() => Object.fromEntries([...window.WORLD.builds.values()].map((b) => [b.id, [b.group.position.x, b.group.position.y, b.group.position.z, b.group.rotation.y, b.group.getObjectByName('lot').visible]])));
    const [x, y, z, turn, plane] = lots['s1-far'];
    assert.ok(Math.abs(x - 700) < 0.01 && Math.abs(y - 138.32) < 0.01 && Math.abs(z + 800) < 0.01 && Math.abs(turn) < 1e-9 && !plane, JSON.stringify(lots));
    // The cape: 83.32 m to the west and 668.3 m to the south of the top.
    assert.ok(Math.abs(lots['s2-far'][0] - 616.68) < 0.01 && Math.abs(lots['s2-far'][2] + 131.7) < 0.01 && Math.abs(lots['s2-far'][1] - 1.34) < 0.01, JSON.stringify(lots));
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.close();
  }
});

test('the time lapse of the statue on the hill: the clock of its log, the scaffold and the people at a pour, the camera', { skip: !playwright && 'no Playwright' }, async () => {
  const dir = '/test/js/fixtures/timelapse';
  const events = (await readFile(join(root, dir.slice(1), 'events.jsonl'), 'utf8')).split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const id = events.find((e) => e.order !== 'yard').order;
  const t0 = events.find((e) => e.order === id).at;
  const day = (e) => (e.at - t0) / 86400000;
  const pour = events.find((e) => e.kind === 'task_started' && e.data.task === 'pour_3');
  const end = day(events.filter((e) => e.order === id).at(-1));
  const server = await serve();
  const browser = await playwright.chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const { port } = server.address();
    await page.goto(`http://127.0.0.1:${port}/review/world.html?follow=1&still=1&days=5&view=front&events=${dir}/events.jsonl&places=${dir}/places.json&files=${dir}&worker=${dir}/worker.glb`);
    await page.waitForFunction(() => window.READY === true, null, { timeout: 60_000 });
    // The length of the film: the days of the site over the days in one second.
    assert.ok(Math.abs((await page.evaluate(() => window.TIMELAPSE.end)) - end) < 1e-6);
    assert.equal(await page.evaluate(() => window.TIMELAPSE.days), 5);
    // Day 0: the lot on the top of the hill, nothing built.
    const first = await page.evaluate(() => [...window.WORLD.builds.values()].map((b) => [b.group.position.y, Object.keys(b.parts).length]));
    assert.ok(Math.abs(first[0][0] - 138.32) < 0.01 && first[0][1] === 0, JSON.stringify(first));
    // The day of the pour of the third band: the scaffold and the forms of
    // the band stand, the people work on the lot, the base is there.
    await page.evaluate((d) => window.TIMELAPSE.to(d), day(pour) + 0.01);
    const state = await page.evaluate((order) => {
      const b = window.WORLD.builds.get(order);
      const near = [...window.WORLD.people.values()].filter((p) => p.build === b && p.figure.position.distanceTo(b.group.position) < 40);
      return { parts: Object.keys(b.parts).sort(), people: near.length, clips: near.map((p) => p.clip), label: document.getElementById('lapse').textContent };
    }, id);
    for (const part of ['be', 'scaffold_3', 'form_3', 'pour_2']) assert.ok(state.parts.includes(part), JSON.stringify(state));
    assert.ok(!state.parts.includes('form_1'), 'the forms of the first band are off');
    assert.ok(state.people >= 1, JSON.stringify(state));
    assert.match(state.label, /^Day \d+ · build · pour_3/);
    // The people move all the time, as in a time lapse of a site: over 2 s
    // of the film they walk round their places and do the work of their
    // trades at the stops.
    const moves = await page.evaluate(async ({ order, from }) => {
      const b = window.WORLD.builds.get(order);
      const near = () => [...window.WORLD.people.values()].filter((p) => p.build === b && p.figure.visible);
      const before = new Map(near().map((p) => [p.name, p.figure.position.clone()]));
      const clips = new Set();
      for (let k = 1; k <= 20; k++) {
        await window.TIMELAPSE.at(from + k * 0.1);
        for (const p of near()) clips.add(p.clip);
      }
      const moved = near().filter((p) => before.has(p.name) && before.get(p.name).distanceTo(p.figure.position) > 0.5);
      return { clips: [...clips], moved: moved.length, people: before.size };
    }, { order: id, from: await page.evaluate((d) => window.TIMELAPSE.filmAt(d), day(pour) + 0.01) });
    const work = ['carry', 'set_panel', 'pour', 'trowel', 'hammer', 'climb', 'guide'];
    assert.ok(moves.moved >= 1 && moves.clips.includes('walk') && moves.clips.some((c) => work.includes(c)), JSON.stringify(moves));
    // The camera of the URL: the front of the statue, from the south of the lot.
    const cam = await page.evaluate((order) => {
      const b = window.WORLD.builds.get(order);
      return [b.group.position.z, document.querySelector('canvas').toDataURL().length];
    }, id);
    assert.ok(cam[1] > 1000);
    // The end: the statue stands, the scaffold and the forms are down.
    await page.evaluate((d) => window.TIMELAPSE.to(d), end);
    const last = await page.evaluate((order) => Object.keys(window.WORLD.builds.get(order).parts).sort(), id);
    assert.ok(last.includes('tuong_chua_kito_vua') && !last.some((p) => /^(scaffold|form|pour)_/.test(p)), JSON.stringify(last));
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.close();
  }
});

test('the world page draws the elements of a construction as they come', { skip: !playwright && 'no Playwright' }, async () => {
  const events = (await readFile(join(root, 'test/js/fixtures/world/events.jsonl'), 'utf8')).split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const elements = events.filter((e) => e.kind === 'element').length;
  const tasks = events.find((e) => e.kind === 'plan_made').data.tasks.length;
  const server = await serve();
  const browser = await playwright.chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const { port } = server.address();
    await page.goto(`http://127.0.0.1:${port}/review/world.html?events=/test/js/fixtures/world/events.jsonl&files=/test/js/fixtures/world`);
    await page.waitForFunction(() => window.READY === true, null, { timeout: 60_000 });
    const state = await page.locator('#builds td').nth(1).textContent();
    assert.equal(state, `${tasks} of ${tasks} tasks, ${elements} elements, done`);
    // Each element is in the scene of its lot, with the ground of the lot.
    const shown = await page.evaluate(() => [...window.WORLD.builds.values()].map((b) => b.group.children.length - 1));
    assert.deepEqual(shown, [elements]);
    const people = await page.locator('#people tr').count();
    assert.ok(people >= 1 && people <= 2);
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.close();
  }
});
