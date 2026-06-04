# In-browser conformance harness (Phase 6 web gate)

Runs the **Dart `CmlWebBackend`** — compiled with `dart compile js` — through the
shared `runConformanceCase` runner and all frozen golden vectors
(`dart/test/conformance/golden_cbor.json`), live against the **CML +
cardano-message-signing browser WASM builds**, in a real browser.

This is the gate that the Node spike (`tool/cml_conformance_spike/`) could not
close: the spike proved the *libraries* agree; this proves **this Dart
JS-interop binding + the actual browser WASM build** reproduce the frozen CSL
bytes. Expected result: **`PASS 24 FAIL 0`**.

## Run

```bash
# 1. Compile the Dart harness entrypoint to JS (from the dart/ package):
cd dart
dart compile js web/conformance_harness.dart -o ../tool/web_conformance/build/harness.js -O2

# 2. Stage CML/MS WASM + golden data + the loader page:
cd ../tool/web_conformance
npm install
node build.mjs

# 3. Serve and open:
node serve.mjs          # http://localhost:8099
```

Open the URL; the page prints `PASS 24 FAIL 0` (green) when the backend
reproduces every vector. For automated/headless checks, read
`globalThis.CONFORMANCE_RESULT` after `globalThis.HARNESS_DONE` is true.

## How the WASM is wired (no bundler)

The `@dcspark/...-browser` / `@emurgo/...-browser` packages are wasm-bindgen
**bundler-target** ESM (`import * as wasm from "*.wasm"`). Instead of pulling in
webpack/Vite, `index.html` does the standard manual instantiation: import the
`_bg.js`, `fetch` + `WebAssembly.instantiate` the `.wasm` with the `_bg.js`
namespace as its import object, call `__wbg_set_wasm`, and expose the result on
`globalThis.CML` / `globalThis.MS` — exactly what the Dart interop binds.

## Files

| File | Role |
|------|------|
| `dart/web/conformance_harness.dart` | Dart entrypoint (compiled to `build/harness.js`) |
| `build.mjs` | Stages `build/`: copies WASM, embeds golden + entropy bridge, copies the page |
| `index.html` | Instantiates the WASM, runs the harness, renders the result |
| `serve.mjs` | Static server with correct wasm/js MIME types |

`build/` and `node_modules/` are git-ignored — regenerate with the steps above.

## Note on `deriveKeys`

CML has no BIP-39 mnemonic parser, and project policy keeps mnemonic crypto out
of Dart, so `CmlWebBackend.deriveKeys` delegates `mnemonic → entropy` to a
host-provided `globalThis.CFL_mnemonicToEntropy`. `build.mjs` pins that bridge to
the single test mnemonic so the CML BIP-32 derivation path runs in-browser; the
part under test is CML's derivation, not the wordlist lookup. The primary web key
path (`deriveAddress` from an account xprv) needs no bridge.
