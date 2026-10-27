// The Khronos glTF validator on each GLB of a directory. It stops with an
// error when a file has an error or a warning.
//
//   node scripts/validate.mjs priv/models
import { validateBytes } from 'gltf-validator';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2] ?? 'priv/models';
const files = readdirSync(dir).filter((f) => f.endsWith('.glb')).sort();
let bad = 0;
let triangles = 0;

for (const file of files) {
  const report = await validateBytes(new Uint8Array(readFileSync(join(dir, file))));
  const { numErrors, numWarnings, messages } = report.issues;
  triangles += report.info.totalTriangleCount ?? 0;
  if (numErrors + numWarnings > 0) {
    bad += 1;
    console.log(`${file}: ${numErrors} errors, ${numWarnings} warnings`);
    for (const m of messages.slice(0, 5)) console.log(`  ${m.code}: ${m.message} (${m.pointer ?? ''})`);
  }
}

console.log(`${files.length} files, ${bad} with errors or warnings, ${triangles} triangles`);
if (files.length === 0 || bad > 0) process.exit(1);
