// Headless CI driver for the in-browser WebCip30Wallet gate.
//
// Serves ./build, loads wallet_index.html in headless Chromium (Puppeteer),
// waits for the dart2js harness to publish globalThis.WALLET_RESULT, and exits
// non-zero unless every check passed (FAIL 0, >=1 pass). Proves the scoped web
// CIP-30 wallet derives + signs correctly against frozen native golden values in
// a real browser. Prereqs, run in this dir first:
//   npm install
//   (cd ../../dart && dart compile js web/web_wallet_harness.dart \
//        -o ../tool/web_conformance/build/wallet_harness.js -O2)
//   node build.mjs                # stages build/ (wasm + data.js + wallet_index.html)
// Then: node run-headless-wallet.mjs
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
    let rel = decodeURIComponent(req.url === '/' ? '/wallet_index.html' : req.url);
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

const browser = await puppeteer.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox'],
});

try {
  const page = await browser.newPage();
  page.on('console', (m) => console.log(`[page] ${m.text()}`));
  page.on('pageerror', (e) => console.error(`[page error] ${e.message}`));

  await page.goto(url, { waitUntil: 'load', timeout: 60_000 });
  await page.waitForFunction('globalThis.WALLET_DONE === true', { timeout: 60_000 });

  const result = String(await page.evaluate('String(globalThis.WALLET_RESULT)'));
  console.log('\n=== WALLET_RESULT ===');
  console.log(result);
  console.log('=====================');

  const m = result.match(/PASS (\d+)\s+FAIL (\d+)\s+\/\s+(\d+)/);
  if (!m) fail(`could not parse summary line from harness output:\n${result}`);
  const [, pass, failed, total] = m.map(Number);

  if (failed !== 0) fail(`${failed} wallet check(s) failed in-browser.`);
  if (pass < 1) fail('no checks passed — harness likely did not run.');
  if (pass !== total) fail(`accounting mismatch: PASS ${pass} != TOTAL ${total}.`);

  console.log(`\n✓ in-browser WebCip30Wallet clean: PASS ${pass} FAIL 0 / ${total}`);
} finally {
  await browser.close();
  server.close();
}
