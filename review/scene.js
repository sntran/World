// The light of the review pages (plan 0004, D7): one module for
// index.html, world.html and replay.html, so that each model shows as a
// person sees it in the sun. The colors of a GLB go through tone mapping
// (ACES), so a light color does not clip to white; a sun casts soft
// shadows; a ground that is not drawn takes them; the sky and the room
// give the light of the shadow side.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

// The sun comes from the front right, high (y is up in three.js).
const SUN = new THREE.Vector3(3, 6, 4).normalize();

// Light a scene: gives `fit(object or box)`, which puts the sun, its
// shadow camera and the ground on the box of a model, and `shade(object)`,
// which has each mesh of an object cast and take shadows, and shows the
// tint of each copy (plan 0020: a node with `extras.tint`).
export function light(renderer, scene) {
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  scene.environment = new THREE.PMREMGenerator(renderer).fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.55;
  scene.add(new THREE.HemisphereLight(0xdde6f0, 0x8a8070, 0.45));

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

  function shade(object) {
    object.traverse((o) => {
      if (o.isMesh && !o.userData.ground) {
        o.castShadow = true;
        o.receiveShadow = true;
      }
      if (o.userData.tint) tint(o, o.userData.tint);
    });
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

  return { sun, ground, fit, shade };
}
