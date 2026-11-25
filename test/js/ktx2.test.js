// The test of the images of KTX2 of World (plan 0020, R16): a file of
// `World.KTX2` read back with the transcoder of Basis Universal that
// three.js has (the KTX2Loader of an app uses it). The fixture
// `fixtures/ktx2/glow.ktx2` is `World.KTX2.from_png/1` of
// `fixtures/ktx2/glow.png` (a square of 128 texels of a glow image of a
// bake), and `fixtures/ktx2/alpha.ktx2` of `fixtures/ktx2/alpha.png` (a
// square of 64 texels with an alpha); `test/world/ktx2_test.exs` checks
// that World writes the same bytes.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname } from 'node:path';
import { test } from 'node:test';
import { inflateSync } from 'node:zlib';

const require = createRequire(import.meta.url);
const fixture = (name) => readFileSync(new URL(`fixtures/ktx2/${name}`, import.meta.url));

// The texels of a PNG of 8 bits for each channel (RGB or RGBA), as RGBA.
function png(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let [w, h, channels, at] = [0, 0, 0, 8];
  const data = [];
  while (at < bytes.length) {
    const len = view.getUint32(at);
    const type = String.fromCharCode(...bytes.subarray(at + 4, at + 8));
    const body = bytes.subarray(at + 8, at + 8 + len);
    if (type === 'IHDR') [w, h, channels] = [view.getUint32(at + 8), view.getUint32(at + 12), { 2: 3, 6: 4 }[body[9]]];
    if (type === 'IDAT') data.push(body);
    at += 12 + len;
  }
  const raw = inflateSync(Buffer.concat(data));
  const stride = w * channels;
  const out = new Uint8Array(w * h * 4);
  let prior = new Uint8Array(stride);
  for (let y = 0; y < h; y += 1) {
    const filter = raw[y * (stride + 1)];
    const row = Uint8Array.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i += 1) {
      const [a, b, c] = [i >= channels ? row[i - channels] : 0, prior[i], i >= channels ? prior[i - channels] : 0];
      const p = a + b - c;
      const paeth = Math.abs(p - a) <= Math.abs(p - b) && Math.abs(p - a) <= Math.abs(p - c) ? a : Math.abs(p - b) <= Math.abs(p - c) ? b : c;
      row[i] = (row[i] + [0, a, b, (a + b) >> 1, paeth][filter]) & 255;
    }
    for (let x = 0; x < w; x += 1)
      for (let k = 0; k < 4; k += 1) out[(y * w + x) * 4 + k] = k < channels ? row[x * channels + k] : 255;
    prior = row;
  }
  return { w, h, texels: out };
}

// The transcoder of Basis Universal of three.js. (It is a script for a worker, as the KTX2Loader of
// three.js loads it: its text, run as a function.)
async function transcoder() {
  const path = require.resolve('three/examples/jsm/libs/basis/basis_transcoder.js');
  const source = readFileSync(path, 'utf8');
  const BASIS = new Function('require', '__filename', '__dirname', `${source}\nreturn BASIS;`)(require, path, dirname(path));
  const basis = await BASIS({ wasmBinary: readFileSync(require.resolve('three/examples/jsm/libs/basis/basis_transcoder.wasm')) });
  basis.initializeBasis();
  return basis;
}

// The PSNR of the channels `channels` of the level 0 of a file, transcoded to RGBA, against the PNG.
function check(basis, name, { alpha, levels, least }) {
  const image = png(fixture(`${name}.png`));
  const file = new basis.KTX2File(new Uint8Array(fixture(`${name}.ktx2`)));
  try {
    assert.ok(file.isValid());
    assert.equal(file.isUASTC(), true);
    assert.deepEqual([file.getWidth(), file.getHeight(), file.getLevels(), file.getHasAlpha()], [image.w, image.h, levels, alpha]);
    assert.ok(file.startTranscoding());
    // The formats of the GPUs: RGBA (no GPU format), ETC1, ETC2, BC1, BC3, BC7, ASTC.
    for (const format of [13, 0, 1, 2, 3, 6, 10]) {
      for (let level = 0; level < file.getLevels(); level += 1) {
        const out = new Uint8Array(file.getImageTranscodedSizeInBytes(level, 0, 0, format));
        assert.ok(file.transcodeImage(out, level, 0, 0, format, 0, -1, -1), `format ${format}, level ${level}`);
      }
    }
    const out = new Uint8Array(file.getImageTranscodedSizeInBytes(0, 0, 0, 13));
    file.transcodeImage(out, 0, 0, 0, 13, 0, -1, -1);
    const channels = alpha ? 4 : 3;
    let error = 0;
    for (let i = 0; i < out.length; i += 4) for (let c = 0; c < channels; c += 1) error += (out[i + c] - image.texels[i + c]) ** 2;
    const psnr = 10 * Math.log10((255 * 255 * channels * image.w * image.h) / error);
    assert.ok(psnr > least, `PSNR ${psnr.toFixed(2)} dB`);
  } finally {
    file.close();
    file.delete();
  }
}

test('a file of KTX2 of World: the transcoder of Basis reads each level, to each format, near the image', async () => {
  const basis = await transcoder();
  // The glow image of a bake (blocks of one color, mode 8, and of RGB, mode 5): a PSNR of more than 35 dB.
  check(basis, 'glow', { alpha: false, levels: 8, least: 35 });
  // An image with an alpha (blocks of RGBA, mode 14): a PSNR of more than 30 dB on the four channels.
  check(basis, 'alpha', { alpha: true, levels: 7, least: 30 });
});
