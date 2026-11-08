// The test of the review page (review/index.html) and its light
// (review/scene.js, plan 0004, D7): a model of the catalog loads and is
// drawn; the colors go through tone mapping; each mesh of the model casts
// and takes shadows, and a ground takes them. It needs Playwright with
// Chromium; with no Playwright, the test does not run.
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
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary' };

// A static server of the repository.
function serve() {
  const server = createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
    try {
      const body = await readFile(join(root, path.endsWith('/') ? join(path, 'index.html') : path));
      res.writeHead(200, { 'content-type': types[extname(path.endsWith('/') ? 'index.html' : path)] ?? 'application/octet-stream' });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

test('the review page draws a model in the sun: tone mapping, soft shadows, a ground that takes them', { skip: !playwright && 'no Playwright' }, async () => {
  const server = await serve();
  const browser = await playwright.chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
  try {
    const page = await browser.newPage({ viewport: { width: 800, height: 500 } });
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const { port } = server.address();
    await page.goto(`http://127.0.0.1:${port}/review/?model=honda_vision_110`);
    await page.waitForFunction(() => window.READY === true, null, { timeout: 120_000 });
    const state = await page.evaluate(() => {
      const { renderer, scene, model } = window.REVIEW;
      let meshes = 0;
      let casting = 0;
      model().traverse((o) => {
        if (o.isMesh && o.visible) {
          meshes += 1;
          if (o.castShadow && o.receiveShadow) casting += 1;
        }
      });
      const ground = scene.children.find((o) => o.userData.ground);
      const sun = scene.children.find((o) => o.isDirectionalLight);
      return {
        aces: renderer.toneMapping === 4,
        shadows: renderer.shadowMap.enabled,
        meshes,
        casting,
        ground: Boolean(ground?.receiveShadow),
        sun: Boolean(sun?.castShadow),
        frames: renderer.info.render.frame,
      };
    });
    assert.equal(state.aces, true);
    assert.equal(state.shadows, true);
    assert.ok(state.meshes > 0 && state.casting === state.meshes, JSON.stringify(state));
    assert.equal(state.ground, true);
    assert.equal(state.sun, true);
    assert.ok(state.frames >= 1, 'READY comes after the first frame');
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.close();
  }
});
