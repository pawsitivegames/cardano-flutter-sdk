# Web Backend & Cross-Backend Conformance — Design (Phase 6)

> Status: v0.10.0 target. Web support is a **second serialization backend**, not
> a recompile. This document defines the architecture, the deliberately reduced
> RC scope, and the golden-CBOR conformance suite that gates it.

## Why web is different

Every other platform (iOS, Android, macOS, Linux, Windows) runs the Rust wrapper
over **CSL** through `flutter_rust_bridge` FFI. The web has **no Rust FFI**, and
the project bans the Rust→WASM tunnel (`CLAUDE.md` → "Things NOT to do"). So on
web the same Dart API must be satisfied by a different engine:

```
native (io)   Dart API ──FFI──▶ Rust wrapper ──▶ CSL
web           Dart API ──JS interop──▶ CML (browser npm)
```

CML is a **different library** from CSL. Even though both are generated from
Cardano's CDDL spec, "they should produce the same bytes" is an assumption that
must be **proven**, not trusted — a one-byte divergence in a witness set or
address is a consensus/interop bug. That proof is the conformance suite.

## Scope for the RC (deliberately reduced)

Per `docs/PLAN.md` (Roadmap restructure v2, point 3), the web backend is scoped
**down** for the `0.12.0` RC to a read + connect subset:

**In scope (web):**
- Address derivation (key → base address; CIP-1852)
- Balance / UTxO **read** (the Blockfrost provider is already pure-Dart REST and
  works on web today — no backend work needed)
- Serialization needed for **CIP-30 connect**: `Value`/`PlutusData`/address CBOR,
  witness assembly, COSE `signData`/`verifyData`

**Out of scope (web, deferred to a later web-parity track):**
- Full transaction building (fee estimation + coin selection against CML)
- Minting / Plutus script execution tx assembly
- Hardware-wallet transports

## The conformance suite (the gate)

The contract lives in `dart/lib/src/conformance/conformance.dart` and is shipped
as part of the package so it can run **in a browser** against the live CML
backend, not just in CI against native.

Pieces:

| Artifact | Role |
|----------|------|
| `ConformanceBackend` | The deterministic op subset both backends implement. Every method is a pure function of its inputs (Ed25519 signing included — it is deterministic), so two conformant backends agree byte-for-byte. |
| `ConformanceCase` | One `(op, input, expected)` golden vector. |
| `runConformanceCase(backend, case)` | Backend-agnostic dispatch — the native test and an in-browser CML run drive the **same** cases through the **same** runner. |
| `NativeConformanceBackend` | CSL/FFI reference backend. Produced the golden file; conformant by construction. |
| `CmlWebBackend` | CML-via-JS-interop backend. **All scoped ops mapped (incl. `verifyData`); passes the full golden suite (32/32) in a real browser** (`tool/web_conformance/`). |
| `conformance_contract.dart` | The **platform-agnostic** core (interface + `ConformanceCase` + `runConformanceCase`). No FFI, no `dart:js_interop` — compiles on native AND web. Both backends and the in-browser harness import this. |
| `test/conformance/golden_cbor.json` | The frozen golden vectors (32 as of v0.10.0-dev). |
| `test/conformance_test.dart` | CI gate: asserts native still reproduces every vector + COSE sigs verify. |
| `test/conformance/generate_golden.dart` | Regenerates the golden file from native (run **only on purpose**). |

> **What each gate proves.** The native backend *generated* these vectors, so
> `conformance_test.dart` (CI) is a **native self-consistency / CSL-drift** gate:
> it catches a CSL upgrade silently changing canonical bytes. **Cross-backend
> equivalence** is now also established: `CmlWebBackend`, dart2js-compiled, was
> driven through these identical vectors against the live CML browser WASM and
> reproduced all 32 byte-for-byte (`tool/web_conformance/`, `PASS 32 FAIL 0`).
> That in-browser run is now an **automated CI gate** (`web-conformance` job in
> `.github/workflows/ci.yml`): it compiles the harness with `dart compile js`,
> stages the browser WASM, and runs `CmlWebBackend` through every vector in
> **headless Chromium** (Puppeteer), failing the build on any byte divergence.
> CI thus guards both CSL drift (native `conformance_test.dart`) and CML parity
> (this in-browser job). The same run is reproducible locally via
> `node run-headless.mjs` (see `tool/web_conformance/`).

### Library-equivalence proof (CML ↔ CSL, byte-for-byte)

Before writing the JS-interop wiring, the core assumption — *CML produces the
same canonical bytes as CSL* — was proven with a Node spike
(`tool/cml_conformance_spike/`, `node harness.mjs` → **`PASS 24 FAIL 0`**). It
drives the **same** 24 golden vectors through CML 6.2.0 +
`cardano-message-signing` 1.1.0 (the nodejs builds, whose WASM core is identical
to the browser bundles the Dart backend binds) and asserts byte-equality with
the frozen CSL output. The CIP-30 `signData` vector matched **including the
deterministic `COSE_Sign1` signature** — the interop-critical path.

Two CML↔CSL encoding divergences surfaced and are now baked into `CmlWebBackend`
(do not "simplify" them away):

| Op | CML default | CSL-matching call |
|----|-------------|-------------------|
| Plutus constr / list | definite-length arrays (`d87981…`, `82…`) | `to_cardano_node_format()` → indefinite (`d8799f…ff`, `9f…ff`) |
| `Value` multi-asset | insertion order | `to_canonical_cbor_hex()` → length-then-lexicographic key sort |

The spike also caught a bug in the original scaffold: it called
`new CML.BaseAddress(...)` where wasm-bindgen requires the static
`BaseAddress.new(...)`, and used plain `to_cbor_hex()` for Plutus (definite —
would have diverged). Both are fixed in the current backend.

**What this proves vs. doesn't.** It proves the *libraries* agree, so the
remaining `CmlWebBackend` gate is no longer "do CML and CSL match?" (yes) but
the narrower, lower-risk "does this Dart JS-interop binding + the browser WASM
build reproduce the same call results?" — still an in-browser Flutter run, just
de-risked to a mechanical check.

### Excluded on purpose: legacy CIP-8 `signMessage`

`rust/src/message.rs`'s `sign_message` does **not** emit a spec `COSE_Sign1`
(it serializes a custom `{public_key, signature, message}` CBOR map), so it is
deliberately **kept out of the golden contract** — freezing it would certify a
non-interoperable encoding as canonical. COSE conformance is covered only by the
CIP-30 `signData` path (`rust/src/cip30.rs`), which is built on Emurgo's reference
`cardano-message-signing` library. `message.rs` is slated for deprecation in
favour of `cip30_sign_data` (tracked for the Phase 7 security review).

### Categories covered

`address` (key derivation, base-address build, bech32→hex), `value` (ADA-only +
multi-asset CBOR), `plutus` (int/bytes/constr/list + nesting), `witness`
(vkey witness-set assembly), `cose` (CIP-30 `signData` + CIP-8 `signMessage`).

### Drift policy

If `conformance_test.dart` fails on native, a CSL upgrade changed canonical bytes
— treat as a **potential interop hazard**. Investigate before regenerating;
regeneration is a deliberate, reviewed act, never a reflex to a red test.

## Wiring the CML backend in a web app

The host web app loads the CML browser build and exposes it on `globalThis.CML`
(e.g. an ESM shim in `web/index.html`), then imports
`src/conformance/cml_web_backend.dart` directly (it is **not** exported from the
package barrel, so native builds never link `dart:js_interop`):

```
npm i @dcspark/cardano-multiplatform-lib-browser \
      @emurgo/cardano-message-signing-browser bip39
# web/index.html (ESM shim):
#   import * as CML from '.../cml_browser.js';  globalThis.CML = CML;  // serialization
#   import * as MS  from '.../ms_browser.js';   globalThis.MS  = MS;   // COSE signData
#   import * as bip39 from 'bip39';
#   globalThis.CFL_mnemonicToEntropy = (m) => bip39.mnemonicToEntropy(m); // optional
```

`globalThis.MS` backs the COSE `signData` path; `globalThis.CFL_mnemonicToEntropy`
is an **optional** BIP-39 bridge used only by `deriveKeys`'s mnemonic path (CML
has no mnemonic parser, and project policy keeps mnemonic crypto out of Dart).
The primary web key path — `deriveAddress` from an account xprv — needs neither.

> ⚠️ **Do not call `RustLib.init()` on web.** The web backend path is
> `CmlWebBackend` (pure JS interop to CML); it must not depend on the FRB bridge.
> `flutter_rust_bridge.yaml` now sets **`web: false`** (= the `--no-web` codegen
> flag), so codegen no longer emits the WASM web stub
> (`dart/lib/src/frb_generated.web.dart`) that bound a `wasm_bindgen`-compiled
> Rust module — i.e. the Rust→WASM tunnel the project bans and never builds. That
> dead artifact is removed. FRB still emits a residual conditional import in the
> generated `frb_generated.dart`
> (`import 'frb_generated.io.dart' if (dart.library.js_interop) 'frb_generated.web.dart'`);
> on every native platform this resolves to the `io` variant, which is the only
> branch ever compiled — the SDK's FFI surface does not target web. A real web
> build never goes through `RustLib`; it uses `CmlWebBackend` directly.

Then in a browser test harness:

```dart
final backend = CmlWebBackend();
for (final c in parseConformanceCases(goldenJson)) {
  assert(runConformanceCase(backend, c) == c.expected); // must hold
}
```

## Verification (Phase 6 gate)

- [x] Conformance harness + 24 golden vectors frozen from native CSL (incl. a
      canonical-ordering stress vector with out-of-order multi-asset + multi-witness)
- [x] CI gate (native self-consistency / CSL-drift): native reproduces every
      vector byte-for-byte; runs as a named CI step on PRs to any branch
- [x] COSE `signData` golden vectors verify under native `verifyData`
- [x] CML-JS backend **scaffold** with honest browser-verify-pending stubs
- [x] CML mapping completed for every scoped op (address, value, plutus
      constr/list/int/bytes, witness, COSE `signData`, key derivation) — see
      `cml_web_backend.dart`
- [x] **Library-equivalence proven under Node**: CML reproduces all 24 CSL
      golden vectors byte-for-byte (`tool/cml_conformance_spike/`, `PASS 24`),
      incl. the deterministic COSE `signData` signature
- [x] **`CmlWebBackend` passes the FULL golden suite (32/32) in a real browser**
      — dart2js-compiled, driven against the live CML + message-signing browser
      WASM builds (`tool/web_conformance/`, `PASS 32 FAIL 0`). This verifies the
      Dart JS-interop binding + the browser WASM, not just library equivalence.
- [x] **dart2js int-precision fix:** the in-browser run caught that Plutus i64
      integers (e.g. `0x112210f47de98115`) were silently rounded — on web a Dart
      `int` is a float64, so a JSON-number `n` loses precision at parse time.
      Fixed by making `ConformanceBackend.plutusDataInt` take a **`BigInt`** and
      storing `n` as a decimal **string** in the golden (the web path builds via
      `BigInteger.from_str`, never touching a lossy int). Native unaffected.
- [x] **In-browser run wired into CI as a headless gate** (`web-conformance` job):
      `dart compile js` → stage WASM → run `CmlWebBackend` through every vector in
      headless Chromium (Puppeteer), failing the build on any divergence. Reproduce
      locally with `node tool/web_conformance/run-headless.mjs`.
- [x] More divergence-prone vectors added (golden now **32**, all reproduced
      in-browser): **non-base address types** (enterprise / reward / script-cred
      base via `addressToHex`) and **nested Plutus** (`constr[list[constr,int],
      bytes]`, exercising recursive Cardano-node indefinite arrays). COSE
      protected-header ordering is already pinned by the `signData` vector (full
      `COSE_Sign1` bytes must match). *Still open:* Plutus bignum **>2^64** —
      needs a BigInt FFI on the native side; i64 is exact on both backends today.
- [x] `CmlWebBackend.verifyData` mapped (COSE parse + Ed25519 verify +
      identity-binding) and gated by 4 golden `verifyData` vectors (accept,
      pure-signature accept, wrong-payload reject, wrong-address reject) — runs
      in-browser as part of the 32/32 suite. Legacy `signMessageCose` left
      intentionally unmapped (excluded from contract).
- [x] **Scoped CIP-30 runs in a desktop browser build of the example.** A second
      package entrypoint `cardano_flutter_rs_web.dart` exposes `WebCip30Wallet`
      (CML-JS + Blockfrost REST); `example/lib/main_web.dart` + `example/web/`
      build & run it in Chrome (`flutter build web -t lib/main_web.dart`). The
      wallet's derivation + `signData`→`verifyData` are gated in-browser against
      the native golden values (`web_wallet_harness.dart`, **PASS 10**, wired into
      the `web-conformance` CI job alongside the conformance gate).
- [ ] **Cross-wallet check vs Lace/Eternl** — verify-side harness + fixture +
      capture guide are in place (`test/cross_wallet_verify_test.dart`,
      `test/fixtures/cross_wallet_signatures.json`, `docs/cross-wallet-verify.md`);
      the test skips until a real wallet signature is pasted in. **Awaiting a
      captured signature** (the only remaining manual step — no web/hardware needed).
- [x] macOS desktop packaging (universal dylib + podspec + entitlements) — done
      and verified, see `docs/macos-packaging.md`.

## macOS / desktop note

macOS desktop packaging is **done and verified** — see `docs/macos-packaging.md`.
Summary: `dart/macos/` is a real FFI plugin (podspec + symbol-forcing stub) that
vendors a universal (arm64 + x86_64) `cardano_flutter_rs.framework` built by
`dart/macos/build_macos_framework.sh`; `example/macos/` is scaffolded with App
Sandbox + `network.client` entitlements. The `macos-build` CI job is now a **hard
gate**: it rebuilds the framework, does a release `flutter build macos` (compile +
link + codesign + entitlements), and runs an integration test inside the built
`.app` that loads the embedded framework via the FRB loader and exercises FFI.

The "trimmed example" worry turned out moot: all seven example plugins (Ledger BLE,
WebRTC, secure storage, in-app WebView, QR scanner, app_links, permission_handler)
ship macOS implementations, so the full example builds and runs on macOS unchanged.
