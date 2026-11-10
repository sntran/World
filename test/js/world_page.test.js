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
