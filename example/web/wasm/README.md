# Web backend WASM (staged from npm)

The scoped web build loads CML + cardano-message-signing as JS/WASM via Dart JS
interop (web has no Rust FFI — Rust→WASM is banned by project policy). These four
files are **staged copies** of the official npm browser builds; they are
git-ignored (large binaries) and must be present before `flutter build web`.

| File | Source npm package |
|------|--------------------|
| `cml_bg.js` / `cml_bg.wasm` | `@dcspark/cardano-multiplatform-lib-browser` (`cardano_multiplatform_lib_bg.{js,wasm}`) |
| `ms_bg.js` / `ms_bg.wasm` | `@emurgo/cardano-message-signing-browser` (`cardano_message_signing_bg.{js,wasm}`) |

These are the **same** WASM cores that the in-browser conformance gate
(`tool/web_conformance/`) drives the 28/28 golden suite against, so the demo runs
on a backend that is byte-verified against native CSL.

## Stage them

The conformance tool already vendors them. Easiest:

```bash
# from repo root, after `cd tool/web_conformance && npm install && node build.mjs`
cp tool/web_conformance/build/{cml_bg.js,cml_bg.wasm,ms_bg.js,ms_bg.wasm} \
   example/web/wasm/
```

Or copy straight from `tool/web_conformance/node_modules/` (see the table above
for the in-package filenames).
