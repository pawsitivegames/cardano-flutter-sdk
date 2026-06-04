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
| `CmlWebBackend` | CML-via-JS-interop backend. **Scaffold — browser-verify pending.** |
| `test/conformance/golden_cbor.json` | The frozen golden vectors (24 as of v0.10.0-dev). |
| `test/conformance_test.dart` | CI gate: asserts native still reproduces every vector + COSE sigs verify. |
| `test/conformance/generate_golden.dart` | Regenerates the golden file from native (run **only on purpose**). |

> **What the CI gate proves today vs. tomorrow.** The native backend *generated*
> these vectors, so `conformance_test.dart` is currently a **native
> self-consistency / CSL-drift** gate: it catches a CSL upgrade silently changing
> canonical bytes. It is **not yet** a cross-backend equivalence result — that
> only exists once `CmlWebBackend` is driven through these identical vectors in a
> real browser (an unchecked item below). "Conformance suite in place" means the
> contract is frozen and the runner is shared, not that two backends are proven
> equal.

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
npm i @dcspark/cardano-multiplatform-lib-browser
# web/index.html: import * as CML from '.../cml_browser.js'; globalThis.CML = CML;
```

> ⚠️ **Do not call `RustLib.init()` on web.** `flutter_rust_bridge` generated a
> WASM web stub (`dart/lib/src/frb_generated.web.dart`) that expects a
> `wasm_bindgen`-compiled Rust module — i.e. the Rust→WASM tunnel the project
> bans and never builds. On web, `RustLib.init()` would fail looking for that
> module. The web backend path is `CmlWebBackend` (pure JS interop to CML); it
> must not depend on the FRB bridge. A follow-up will configure codegen to stop
> emitting the web target so this dead artifact can be removed.

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
- [ ] More divergence-prone vectors: Plutus bignum >2^64 (needs a BigInt FFI;
      current `plutusDataInt` is i64-bound), non-base address types (enterprise/
      reward/script-cred), nested Plutus, COSE protected-header ordering
- [ ] CML mapping completed for every scoped op (constr/list, value, witness, COSE)
- [ ] `CmlWebBackend` passes the **full** golden suite in a real browser
- [ ] Scoped CIP-30 methods run in a desktop browser build of the example
- [ ] **Cross-wallet check vs Lace/Eternl** (a real wallet-signed message verifies
      under native `verifyMessage` — runnable today, no web needed)
- [ ] macOS desktop packaging (universal dylib + podspec + entitlements)

## macOS / desktop note

macOS plugin scaffolding (universal `lipo` arm64+x86_64 dylib, podspec framework
embedding, entitlements, codesign) is part of Phase 6 but is tracked separately:
several example-app plugins (Ledger BLE, WebRTC, secure storage, in-app WebView)
are mobile-only, so a desktop build target needs a trimmed example. Until that
lands, the CI `macos-build` job stays informational (see `.github/workflows/ci.yml`).
