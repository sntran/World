// The light of the review pages (plan 0004, D7): one module for
// index.html, world.html and replay.html, so that each model shows as a
// person sees it in the sun. The colors of a GLB go through tone mapping
// (ACES), so a light color does not clip to white; a sun casts soft
// shadows; a ground that is not drawn takes them; the sky and the room
// give the light of the shadow side.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { KTX2Loader } from 'three/addons/loaders/KTX2Loader.js';

// The transcoder of Basis Universal of the three.js of the pages, for the
// images of KTX2 (plan 0020, D14: `images: "ktx2"`).
export const TRANSCODER = 'https://cdn.jsdelivr.net/npm/three@0.169.0/examples/jsm/libs/basis/';

// A loader of GLB files that reads the images of KTX2 too (it transcodes
// them to a format of the GPU of the renderer).
export function loader(renderer) {
  return new GLTFLoader().setKTX2Loader(new KTX2Loader().setTranscoderPath(TRANSCODER).detectSupport(renderer));
}

// The part of the glow of a model by day (the light of the room behind a
// window, by day: a little lighter than a dark window).
export const DAY_GLOW = 0.1;

// The sun comes from the front right, high (y is up in three.js).
const SUN = new THREE.Vector3(3, 6, 4).normalize();

// Light a scene: gives `fit(object or box)`, which puts the sun, its
// shadow camera and the ground on the box of a model; `shade(object)`,
// which has each mesh of an object cast and take shadows, and shows the
// tint of each copy (plan 0020: a node with `extras.tint`) and the look of
// each point (plan 0020, D5 and D6: the occlusion in the alpha of
// COLOR_0, the roughness and the metal of _FINISH, and the light of
// _LIGHT), as a game draws them; and `night(on)`, the light of the night:
// no sun, a dark sky, so the glow of a model shows.
export function light(renderer, scene) {
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.55;
  const sky = new THREE.HemisphereLight(0xdde6f0, 0x8a8070, 0.45);
  scene.add(sky);

  const sun = new THREE.DirectionalLight(0xfff3e2, 2.4);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.radius = 4;
  scene.add(sun, sun.target);

  const ground = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.ShadowMaterial({ opacity: 0.28 }));
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  ground.userData.ground = true;
  scene.add(ground);

  // The glow by day and at night (plan 0020, step 3): a project makes
  // the light of a model weaker by day, as a game does. A lit window by
  // day looks almost as dark as the windows next to it.
  const glow = { value: DAY_GLOW };
  const glowing = new Set();

  function shade(object) {
    object.traverse((o) => {
      if (o.isMesh && !o.userData.ground) {
        o.castShadow = true;
        o.receiveShadow = true;
      }
      if (o.userData.tint) tint(o, o.userData.tint);
      if (o.isMesh) look(o);
      if (o.isMesh && o.material.emissiveMap) {
        o.material.userData.glow ??= o.material.emissiveIntensity;
        o.material.emissiveIntensity = o.material.userData.glow * glow.value;
        glowing.add(o.material);
      }
    });
  }

  // The look of each point of a mesh (a level of a sculpture with no
  // maps): the alpha of COLOR_0 is how open the point is, so it takes the
  // light of the sky and of the room (as the occlusion of a map), not the
  // sun; _FINISH has the roughness and the metal of the point, and
  // _LIGHT its light (in linear light, as an emission: not the color of the
  // point times a glow). In a copy of the material: one copy for each
  // material and attributes.
  const looks = new Map();
  function look(mesh) {
    const finish = Boolean(mesh.geometry.getAttribute('_finish'));
    const lit = Boolean(mesh.geometry.getAttribute('_light'));
    const color = mesh.geometry.getAttribute('color');
    const open = Boolean(color && color.itemSize === 4 && mesh.material.vertexColors);
    if (!finish && !open) return;
    const key = `${mesh.material.uuid} ${finish} ${lit} ${open}`;
    if (!looks.has(key)) looks.set(key, looked(mesh.material, finish, lit, open));
    mesh.material = looks.get(key);
  }

  function looked(base, finish, lit, open) {
    const material = base.clone();
    material.userData.look = { finish, lit, open };
    material.customProgramCacheKey = () => `look ${finish} ${lit} ${open}`;
    material.onBeforeCompile = (shader) => {
      if (finish) {
        shader.vertexShader = shader.vertexShader
          .replace('#include <color_pars_vertex>', 'attribute vec2 _finish;\nvarying vec2 vFinish;\n#include <color_pars_vertex>')
          .replace('#include <color_vertex>', '#include <color_vertex>\nvFinish = _finish;');
        shader.fragmentShader = shader.fragmentShader
          .replace('#include <color_pars_fragment>', 'varying vec2 vFinish;\n#include <color_pars_fragment>')
          .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = vFinish.r;')
          .replace('#include <metalnessmap_fragment>', '#include <metalnessmap_fragment>\nmetalnessFactor = vFinish.g;');
      }
      if (lit) {
        shader.vertexShader = shader.vertexShader
          .replace('#include <color_pars_vertex>', 'attribute vec3 _light;\nvarying vec3 vLight;\n#include <color_pars_vertex>')
          .replace('#include <color_vertex>', '#include <color_vertex>\nvLight = _light;');
        shader.fragmentShader = shader.fragmentShader
          .replace('#include <color_pars_fragment>', 'varying vec3 vLight;\n#include <color_pars_fragment>')
          .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\ntotalEmissiveRadiance += vLight * glowScale;');
        shader.fragmentShader = 'uniform float glowScale;\n' + shader.fragmentShader;
        shader.uniforms.glowScale = glow;
      }
      if (open) {
        shader.fragmentShader = shader.fragmentShader.replace(
          '#include <aomap_fragment>',
          '#include <aomap_fragment>\nreflectedLight.indirectDiffuse *= vColor.a;\nreflectedLight.indirectSpecular *= vColor.a;'
        );
      }
    };
    return material;
  }

  // The light of the day, or of the night: no sun, and a dark sky and
  // room, so a model shows its glow (and the lights of its maps).
  function night(on) {
    sun.intensity = on ? 0.0 : 2.4;
    sky.intensity = on ? 0.05 : 0.45;
    scene.environmentIntensity = on ? 0.04 : 0.55;
    glow.value = on ? 1.0 : DAY_GLOW;
    for (const m of glowing) m.emissiveIntensity = m.userData.glow * glow.value;
  }

  // The tint multiplies the color of each mesh of the node (the node, or
  // the meshes of its primitives), in a copy of its material: one copy
  // for each material and tint. (three.js draws the `_COLOR_0` of the
  // instances itself.)
  const tinted = new Map();
  function tint(node, hex) {
    for (const mesh of node.isMesh ? [node] : node.children.filter((c) => c.isMesh)) {
      const key = `${mesh.material.uuid} ${hex}`;
      if (!tinted.has(key)) {
        const material = mesh.material.clone();
        material.color.multiply(new THREE.Color(hex));
        tinted.set(key, material);
      }
      mesh.material = tinted.get(key);
    }
  }

  function fit(what) {
    const box = what.isBox3 ? what : new THREE.Box3().setFromObject(what);
    if (box.isEmpty()) return;
    const center = box.getCenter(new THREE.Vector3());
    const r = Math.max(box.getSize(new THREE.Vector3()).length() / 2, 0.1);
    sun.position.copy(center).addScaledVector(SUN, 3 * r);
    sun.target.position.copy(center);
    const cam = sun.shadow.camera;
    cam.left = cam.bottom = -1.1 * r;
    cam.right = cam.top = 1.1 * r;
    cam.near = 0.5 * r;
    cam.far = 5.5 * r;
    cam.updateProjectionMatrix();
    // The bias scales with the size of a texel of the shadow map.
    sun.shadow.bias = -0.0004;
    sun.shadow.normalBias = (2.2 * r / sun.shadow.mapSize.x) * 1.5;
    ground.position.set(center.x, box.min.y - 0.001 * r, center.z);
    ground.scale.setScalar(8 * r);
  }

  return { sun, ground, fit, shade, night, glow };
}
