// Minimal static server for ./build with correct wasm/js MIME types.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { join, extname } from 'node:path';

const TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.wasm': 'application/wasm',
};
const PORT = Number(process.env.PORT) || 8099;

createServer((req, res) => {
  const rel = decodeURIComponent(req.url === '/' ? '/index.html' : req.url);
  const fp = join(import.meta.dirname, 'build', rel);
  try {
    const body = readFileSync(fp);
    res.setHeader('content-type', TYPES[extname(fp)] || 'application/octet-stream');
    res.end(body);
  } catch {
    res.statusCode = 404;
    res.end('404');
  }
}).listen(PORT, () => console.log(`serving build/ at http://localhost:${PORT}`));
