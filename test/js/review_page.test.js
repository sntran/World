// The test of the review page (review/index.html) and its light
// (review/scene.js, plan 0004, D7): a model of the catalog loads and is
// drawn; the colors go through tone mapping; each mesh of the model casts
// and takes shadows, and a ground takes them; a copy shows its tint
// (plan 0020). It needs Playwright with Chromium; with no Playwright, the
// test does not run.
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

test('the review page draws a model in the sun: tone mapping, soft shadows, a ground that takes them, the tint of a copy', { skip: !playwright && 'no Playwright' }, async () => {
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

    // The tint of a copy (plan 0020): the meshes of a node with
    // extras.tint get a copy of their material, with the color times the
    // tint; the material of the other copies stays.
    const tints = await page.evaluate(async () => {
      const THREE = await import('three');
      const { light } = await import('/review/scene.js');
      const stage = light(new THREE.WebGLRenderer(), new THREE.Scene());
      const material = new THREE.MeshStandardMaterial({ color: 0xffffff });
      const box = new THREE.BoxGeometry();
      const one = new THREE.Mesh(box, material);
      one.userData.tint = '#ff0000';
      const group = new THREE.Group();
      group.userData.tint = '#ff0000';
      group.add(new THREE.Mesh(box, material));
      const plain = new THREE.Mesh(box, material);
      const root = new THREE.Group();
      root.add(one, group, plain);
      stage.shade(root);
      const red = new THREE.Color('#ff0000');
      return {
        one: one.material.color.equals(red),
        group: group.children[0].material.color.equals(red),
        shared: one.material === group.children[0].material,
        plain: plain.material === material && material.color.getHex() === 0xffffff,
      };
    });
    assert.deepEqual(tints, { one: true, group: true, shared: true, plain: true });
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.close();
  }
});

// The look of each point of a level of a sculpture with no maps (plan
// 0020, step 2): the occlusion in the alpha of COLOR_0 and _FINISH. The
// fixture `fixtures/look/slab.far.glb` is a slab of World at far (the
// drawing of `test/world/sculpt_shade_test.exs` with a lamp of glow 0.8,
// cells of 0.05 m and a budget of 300 triangles, from
// `World.Orders.build(order, "far", "glb")`).
test('the look of each point: opaque with no shader of its own, the occlusion and the glow with the review page, and the night', { skip: !playwright && 'no Playwright' }, async () => {
  const server = await serve();
  const browser = await playwright.chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    const { port } = server.address();
    await page.goto(`http://127.0.0.1:${port}/review/?model=honda_vision_110`);
    await page.waitForFunction(() => window.READY === true, null, { timeout: 120_000 });
    const state = await page.evaluate(async () => {
      const THREE = await import('three');
      const { GLTFLoader } = await import('three/addons/loaders/GLTFLoader.js');
      const { light } = await import('/review/scene.js');
      const load = async () => (await new GLTFLoader().loadAsync('/test/js/fixtures/look/slab.far.glb')).scene;
      // The slab seen from the top, in a picture of 64 × 64 pixels: the most of each channel.
      const shot = (model, setup) => {
        const renderer = new THREE.WebGLRenderer({ preserveDrawingBuffer: true });
        renderer.setSize(64, 64, false);
        const scene = new THREE.Scene();
        scene.background = new THREE.Color(0x00ff00);
        const stage = setup ? setup(renderer, scene) : (scene.add(new THREE.AmbientLight(0xffffff, 2)), null);
        scene.add(model);
        const camera = new THREE.OrthographicCamera(-1.2, 1.2, 1.2, -1.2, 0.1, 10);
        camera.position.set(0, 5, 0);
        camera.up.set(0, 0, -1);
        camera.lookAt(0, 0, 0);
        renderer.render(scene, camera);
        const gl = renderer.getContext();
        const pixels = new Uint8Array(64 * 64 * 4);
        gl.readPixels(0, 0, 64, 64, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        const at = (x, y) => Array.from(pixels.slice(4 * (y * 64 + x), 4 * (y * 64 + x) + 3));
        let brightest = 0;
        for (let i = 0; i < pixels.length; i += 4) brightest = Math.max(brightest, Math.min(pixels[i], pixels[i + 1], pixels[i + 2]));
        return { center: at(32, 32), brightest, error: gl.getError(), stage };
      };

      // With no shader of its own, three.js draws the slab opaque: the green of the background does not show through.
      const plain = await load();
      const mesh = plain.getObjectByProperty('isMesh', true);
      const color = mesh.geometry.getAttribute('color');
      const finish = mesh.geometry.getAttribute('_finish');
      const opaque = shot(plain);

      // With the review page: the material of the look, by day and by night.
      const day = await load();
      const lit = shot(day, (renderer, scene) => {
        const stage = light(renderer, scene);
        stage.shade(day);
        return stage;
      });
      const look = day.getObjectByProperty('isMesh', true).material.userData.look;
      const night = await load();
      const dark = shot(night, (renderer, scene) => {
        const stage = light(renderer, scene);
        stage.shade(night);
        stage.night(true);
        return stage;
      });
      // (The same slab by night with no glow: the plain material.)
      const unlit = await load();
      const none = shot(unlit, (renderer, scene) => {
        const stage = light(renderer, scene);
        stage.night(true);
        return stage;
      });
      return {
        alpha: color.itemSize,
        finish: [finish.itemSize, finish.normalized],
        transparent: mesh.material.transparent,
        opaque: opaque.center,
        errors: [opaque.error, lit.error, dark.error, none.error],
        look,
        sun: dark.stage.sun.intensity,
        glow: dark.brightest,
        noGlow: none.brightest,
      };
    });
    assert.equal(state.alpha, 4);
    assert.deepEqual(state.finish, [3, true]);
    assert.equal(state.transparent, false);
    const [r, g, b] = state.opaque;
    assert.ok(g - Math.max(r, b) < 40, `the slab is opaque: ${state.opaque}`);
    assert.deepEqual(state.errors, [0, 0, 0, 0]);
    assert.deepEqual(state.look, { finish: true, open: true });
    assert.equal(state.sun, 0);
    // By night the lamp glows: a bright pixel, where the slab with no glow has none.
    assert.ok(state.glow > 120 && state.noGlow < 60, JSON.stringify(state));
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    server.close();
  }
});
