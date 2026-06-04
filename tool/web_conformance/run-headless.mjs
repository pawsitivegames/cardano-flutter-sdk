// Headless CI driver for the in-browser conformance gate.
//
// Serves ./build, loads index.html in headless Chromium (Puppeteer), waits for
// the dart2js harness to publish globalThis.CONFORMANCE_RESULT, and exits non-zero
// unless the run is clean (FAIL 0, every non-skipped vector passed, >=1 pass).
//
// This is what turns the manual browser gate (open the page, read the green line)
// into an automated one. Prereqs, run in this dir first:
//   npm install                                   # pulls CML/MS WASM + puppeteer
//   (cd ../../dart && dart compile js web/conformance_harness.dart \
//        -o ../tool/web_conformance/build/harness.js -O2)
//   node build.mjs                                # stages build/
// Then: node run-headless.mjs
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { join, extname } from 'node:path';
import puppeteer from 'puppeteer';

const TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.wasm': 'application/wasm',
};

const buildDir = join(import.meta.dirname, 'build');

function startServer() {
  const server = createServer((req, res) => {
    const rel = decodeURIComponent(req.url === '/' ? '/index.html' : req.url);
    try {
      const body = readFileSync(join(buildDir, rel));
      res.setHeader('content-type', TYPES[extname(rel)] || 'application/octet-stream');
      res.end(body);
    } catch {
      res.statusCode = 404;
      res.end('404');
    }
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

function fail(msg) {
  console.error(`\n✗ ${msg}`);
  process.exit(1);
}

const server = await startServer();
const { port } = server.address();
const url = `http://127.0.0.1:${port}/`;

// --no-sandbox is required to run Chromium as root in CI containers.
const browser = await puppeteer.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox'],
});

try {
  const page = await browser.newPage();
  // Surface page console + errors so a harness crash is visible in CI logs.
  page.on('console', (m) => console.log(`[page] ${m.text()}`));
  page.on('pageerror', (e) => console.error(`[page error] ${e.message}`));

  await page.goto(url, { waitUntil: 'load', timeout: 60_000 });
  await page.waitForFunction('globalThis.HARNESS_DONE === true', { timeout: 60_000 });

  const result = String(await page.evaluate('String(globalThis.CONFORMANCE_RESULT)'));
  console.log('\n=== CONFORMANCE_RESULT ===');
  console.log(result);
  console.log('==========================');

  const m = result.match(/PASS (\d+)\s+FAIL (\d+)\s+SKIP (\d+)\s+\/\s+(\d+)/);
  if (!m) fail(`could not parse summary line from harness output:\n${result}`);
  const [, pass, failed, skip, total] = m.map(Number);

  if (failed !== 0) fail(`${failed} vector(s) failed in-browser.`);
  if (pass < 1) fail('no vectors passed — harness likely did not run the suite.');
  if (pass + skip !== total) {
    fail(`accounting mismatch: PASS ${pass} + SKIP ${skip} != TOTAL ${total}.`);
  }

  console.log(`\n✓ in-browser conformance clean: PASS ${pass} FAIL 0 SKIP ${skip} / ${total}`);
} finally {
  await browser.close();
  server.close();
}
