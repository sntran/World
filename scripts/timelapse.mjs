// A video of the time lapse of a construction (plan 0006, D11; R10).
//
//   node scripts/timelapse.mjs URL OUT.mp4 [FPS] [WIDTH] [HEIGHT]
//
// URL is the page of the world that follows a construction
// (review/world.html?follow=...&events=...&still=1, with the camera of
// ?view, ?cam, ?target, ?fov and the days of ?days). The script goes from
// day 0 to the last day of the construction, FPS frames for each second
// (30 by default), each frame `days / FPS` days of the world after the
// one before; so the length of the film is the days of the site over the
// days in one second. ffmpeg makes the video (H.264, yuv420p).
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';

const [url, out, fps = '30', width = '1280', height = '720'] = process.argv.slice(2);
if (!url || !out) {
  console.error('node scripts/timelapse.mjs URL OUT.mp4 [FPS] [WIDTH] [HEIGHT]');
  process.exit(2);
}

const { chromium } = createRequire(import.meta.url)('playwright');
const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
const page = await browser.newPage({ viewport: { width: Number(width), height: Number(height) }, deviceScaleFactor: 1 });
page.on('pageerror', (e) => console.error('page:', e.message));
await page.goto(url.includes('still=') ? url : url + (url.includes('?') ? '&' : '?') + 'still=1');
await page.waitForFunction(() => window.READY === true && window.TIMELAPSE, null, { timeout: 120_000 });
// The view only: no side panel.
await page.addStyleTag({ content: 'body{grid-template-columns:1fr!important;grid-template-rows:1fr!important} header,aside,#lapsebar{display:none!important} main{grid-row:1!important;height:100vh!important}' });
await page.evaluate(() => window.dispatchEvent(new Event('resize')));

const { end, days } = await page.evaluate(() => ({ end: window.TIMELAPSE.end, days: window.TIMELAPSE.days }));
const frames = Math.max(1, Math.ceil((end / days) * Number(fps)));
console.log(`${end.toFixed(1)} days at ${days} days in a second: ${frames} frames, ${(frames / Number(fps)).toFixed(1)} s`);

const ffmpeg = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', fps, '-i', '-', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', out], { stdio: ['pipe', 'inherit', 'inherit'] });
for (let f = 0; f <= frames; f++) {
  await page.evaluate((day) => window.TIMELAPSE.to(day), Math.min((f * days) / Number(fps), end));
  const png = await page.locator('#view').screenshot({ type: 'png', timeout: 120_000 });
  if (!ffmpeg.stdin.write(png)) await new Promise((r) => ffmpeg.stdin.once('drain', r));
}
ffmpeg.stdin.end();
const code = await new Promise((r) => ffmpeg.on('close', r));
await browser.close();
process.exit(code);
