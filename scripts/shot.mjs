// A picture of a model on the review page, for a pull request.
//
//   python3 -m http.server 8820 &   (in the root of the repository)
//   node scripts/shot.mjs NAME OUT.png [level] [yaw] [pose] [animation] [t]
//
// FOCUS=x,y,z and ZOOM=4 give a close view of a point (the review page).
//
// The level is "" (near), ".mid" or ".far".
//
// It needs Playwright and a Chromium (CHROMIUM, or the browser of
// Playwright).
import { createRequire } from 'node:module';

// Playwright is not a dependency of the package: use the one of the computer.
const { chromium } = createRequire(import.meta.url)('playwright');

const [name, out, level = '', yaw = '35', pose = '', animation = '', t = '0'] = process.argv.slice(2);
const port = process.env.PORT ?? '8820';
const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'], executablePath: process.env.CHROMIUM });
const page = await browser.newPage({ viewport: { width: 1100, height: 700 } });
page.on('pageerror', (e) => console.log('error', String(e)));
await page.goto(`http://127.0.0.1:${port}/review/?model=${name}&level=${level}&yaw=${yaw}&pose=${pose}&animation=${animation}&t=${t}${process.env.FOCUS ? `&focus=${process.env.FOCUS}&zoom=${process.env.ZOOM ?? 4}` : ''}`);
await page.waitForFunction(() => window.READY === true, null, { timeout: 120000 });
await page.waitForTimeout(500);
await page.screenshot({ path: out });
await browser.close();
