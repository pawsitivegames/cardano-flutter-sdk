# In-browser conformance harness (Phase 6 web gate)

Runs the **Dart `CmlWebBackend`** — compiled with `dart compile js` — through the
shared `runConformanceCase` runner and all frozen golden vectors
(`dart/test/conformance/golden_cbor.json`), live against the **CML +
cardano-message-signing browser WASM builds**, in a real browser.

This is the gate that the Node spike (`tool/cml_conformance_spike/`) could not
close: the spike proved the *libraries* agree; this proves **this Dart
JS-interop binding + the actual browser WASM build** reproduce the frozen CSL
bytes. Expected result: **`PASS 32 FAIL 0`**.

## Run

```bash
# 1. Compile the Dart harness entrypoint to JS (from the dart/ package):
cd dart
dart compile js web/conformance_harness.dart -o ../tool/web_conformance/build/harness.js -O2

# 2. Stage CML/MS WASM + golden data + the loader page:
cd ../tool/web_conformance
npm install
node build.mjs

# 3a. Headless (what CI runs) — drives the page in headless Chromium and exits
#     non-zero on any divergence:
node run-headless.mjs   # → "✓ in-browser conformance clean: PASS 32 FAIL 0 …"

# 3b. Or serve and open in a real browser to inspect manually:
node serve.mjs          # http://localhost:8099
```

Open the URL; the page prints `PASS 32 FAIL 0` (green) when the backend
reproduces every vector. For automated/headless checks, `run-headless.mjs`
(Puppeteer) waits for `globalThis.HARNESS_DONE`, parses
`globalThis.CONFORMANCE_RESULT`, and fails on any `FAIL` or accounting mismatch.

## WebCip30Wallet gate (scoped web CIP-30)

A second harness proves the **scoped web wallet** (`WebCip30Wallet`, the public
web API in `cardano_flutter_rs_web.dart`) derives + signs correctly in a real
browser. It drives the wallet's offline ops — key/address derivation, CIP-30
address encodings, reward address, `signTx`, `signData`→`verifyData` (accept +
tamper-reject). Address and `signData` results are checked against frozen
**native CSL** golden values; `signTx` is checked against a CML-generated full
transaction fixture because this scoped web backend signs CML-parseable
transaction CBOR. Network ops
(`getUtxos`/`getBalance`) are excluded here to keep the gate deterministic and
key-free (`getBalance` value-CBOR assembly is covered by the conformance gate,
`getUtxos` now serializes provider UTxOs through CML-JS, and the REST provider is
covered by the native live tests).

```bash
# (after `npm install` in this dir)
cd dart
dart compile js web/web_wallet_harness.dart -o ../tool/web_conformance/build/wallet_harness.js -O2
cd ../tool/web_conformance
node build.mjs
node run-headless-wallet.mjs   # → "✓ in-browser WebCip30Wallet clean: PASS 13 FAIL 0 / 13"
```

## CI

The `web-conformance` job in `.github/workflows/ci.yml` runs the conformance gate
(steps 1–3a) **and** the WebCip30Wallet gate on every PR (headless Chromium via
Puppeteer) and **gates** the build — a CML↔CSL byte divergence in the web backend,
or a derivation/signing regression in the scoped wallet, now fails CI rather than
only showing up in a manual run.

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
| `dart/web/conformance_harness.dart` | Conformance Dart entrypoint (compiled to `build/harness.js`) |
| `dart/web/web_wallet_harness.dart` | WebCip30Wallet Dart entrypoint (compiled to `build/wallet_harness.js`) |
| `build.mjs` | Stages `build/`: copies WASM, embeds golden + entropy bridge, copies both pages |
| `index.html` / `wallet_index.html` | Instantiate the WASM, run a harness, render the result |
| `run-headless.mjs` / `run-headless-wallet.mjs` | Puppeteer CI drivers for the two gates |
| `serve.mjs` | Static server with correct wasm/js MIME types |

`build/` and `node_modules/` are git-ignored — regenerate with the steps above.

## Note on `deriveKeys`

CML has no BIP-39 mnemonic parser, and project policy keeps mnemonic crypto out
of Dart, so `CmlWebBackend.deriveKeys` delegates `mnemonic → entropy` to a
host-provided `globalThis.CFL_mnemonicToEntropy`. `build.mjs` pins that bridge to
the single test mnemonic so the CML BIP-32 derivation path runs in-browser; the
part under test is CML's derivation, not the wordlist lookup. The primary web key
path (`deriveAddress` from an account xprv) needs no bridge.
