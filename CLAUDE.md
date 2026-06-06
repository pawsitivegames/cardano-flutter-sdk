# Cardano Flutter SDK — Project Memory

> This file is read by Claude Code at the start of every session. Keep it under 200 lines.

## Project overview

A production-grade, open-source Flutter SDK for the Cardano blockchain. Architecture: thin Dart API → `flutter_rust_bridge` → Rust wrapper crate → `cardano-multiplatform-lib` (CML). Targets iOS, Android, macOS, Linux, Windows via Rust FFI; web via direct JS interop to CML's npm package (not via Rust FFI).

**Why CML over CSL:** CML is co-maintained by Emurgo + dcSpark, more actively released (last update April 2025 vs CSL's August 2025), uses the same CDDL-spec generation approach, and has better CBOR preservation. Architect the Rust wrapper to make the backend swappable (CSL/CML/Pallas) via feature flags or trait abstractions — Pallas v1.0 may become the strategic long-term choice.

**Why FFI:** Generated from Cardano's official CDDL spec. By wrapping in Rust and exposing via FFI, we get correctness for free and protocol upgrades flow downstream automatically rather than requiring SDK rewrites.

**The plan:** see `docs/PLAN.md` (single source of truth). Critical review of stack choices in `.claude/goals/CRITICAL_REVIEW.md`.

## Architecture & code map

The layering is: **`example/` (Flutter app) → `dart/` (public API) → FFI
(flutter_rust_bridge) → `rust/` (wrapper crate) → CSL/CML**. Network/chain data
is fetched in Dart over REST (Blockfrost), *not* through FFI — the FFI surface is
deliberately minimal (signing/serialization only).

**The core pattern:** most `rust/src/<x>.rs` modules have a generated Dart twin
`dart/lib/src/<x>.dart`. Edit the Rust, run `flutter_rust_bridge_codegen generate`,
and the Dart twin + `frb_generated.dart` are regenerated — **never hand-edit
generated files**. Twin modules: `address`, `cip30`, `coin_selection`, `error`,
`hardware`, `message`, `metadata`, `minting`, `plutus`, `seed`, `sign`, `staking`,
`tx`, `wallet`.

Dart-only code (no Rust twin), hand-written:
- `wrappers.dart` — ergonomic helpers over the generated API (e.g. `utxoToTxInput`).
- `providers/` — chain-data fetchers (Blockfrost) over REST.
- `hd/` — CIP-1852 HD discovery / gap scan.
- `cip45/` — CIP-45 protocol core (transport lives in `example/`, not the package).
- `conformance/` — the CSL↔CML byte-parity suite. `conformance_contract.dart` is the
  **platform-agnostic** interface + `runConformanceCase` dispatcher (no FFI, no
  `dart:js_interop`); `conformance.dart` adds `NativeConformanceBackend` (CSL/FFI);
  `cml_web_backend.dart` is `CmlWebBackend` (CML via JS interop, web-only, **not**
  barrel-exported). The split is what lets the web backend compile under dart2js.
- `web/web_cip30_wallet.dart` — `WebCip30Wallet`, the scoped web CIP-30 wallet
  (CML-JS derivation/`signData` + Blockfrost REST). Web-only (`dart:js_interop`).

**Two entrypoints:** `cardano_flutter_rs.dart` is the **native** barrel (pulls in
`dart:ffi`); `cardano_flutter_rs_web.dart` is the **web** entrypoint — re-exports
only web-safe pieces (`WebCip30Wallet`, `CmlWebBackend`, the contract, providers),
never the FFI chain, so it compiles under dart2js. The public API is whatever they
re-export. Web example target: `example/lib/main_web.dart` (`flutter build web -t
lib/main_web.dart`); host WASM/bridge in `example/web/index.html`.

## Current state

**Heading toward `0.12.0` RC.** Feature-complete on iOS (verified on iPhone 13);
macOS packaged & verified; web shipped as a scoped second backend (CML-JS,
in-browser conformance-gated 32/32) with a `WebCip30Wallet` public web API
(`cardano_flutter_rs_web.dart`) and an example web build. Bare `1.0.0` is gated on
**Android physical-device** verification; hardware wallets stay `@experimental`
(→ v1.1.0).

- **Phase-by-phase history:** [`CHANGELOG.md`](CHANGELOG.md).
- **Roadmap, next steps, version gates:** [`docs/PLAN.md`](docs/PLAN.md) — the single
  source of truth. Per-phase verification reports + design docs live in `docs/`.
- **Known-pending (honest):** Lace/Eternl cross-wallet check (verify harness +
  fixture in place — `docs/cross-wallet-verify.md` — awaiting a captured real
  signature); macOS example **send-tx** run on testnet; **Ledger on-device TX
  signing** (`signTransaction` intentionally throws — `docs/hardware-wallets.md`);
  **Android physical-device + Play Store** acceptance (emulator-only is *not*
  "verified on device").

### Key implementation facts (durable — not history)

- **Active backend is CSL**, not CML: Phases 1–5 ship on `cardano-serialization-lib`
  v15.0.3. CML is the **web** backend and the long-term swap target. CSL↔CML
  byte-parity is frozen by the conformance suite (see Architecture below) — never
  change canonical-bytes behavior without regenerating golden vectors *on purpose*.
- **iOS binary:** dynamic framework at `dart/ios/Libs/cardano_flutter_rs.framework`.
- **Live integration tests** read `BLOCKFROST_PROJECT_ID` from the env.
- **Plutus cost models:** `build_script_tx` uses hardcoded Conway V1/V2/V3 cost
  models (copied from CSL source, since `TxBuilderConstants` is `pub(crate)`).
  `script_data_hash` is correct for node validation.


## Tech stack (planned versions; verify against latest at install time)

- **Rust:** stable, edition 2021
- **`cardano-multiplatform-lib` (CML):** `6.2.x` or latest (primary backend)
- **`cardano-serialization-lib` (CSL):** optional feature flag for compatibility
- **`pallas` (txpipe):** v1.0+; planned migration target before v1.0
- **`flutter_rust_bridge`:** `2.12.x` or latest 2.x (pin exact version; breaking changes occur)
- **Flutter:** `>=3.19.0`
- **Dart:** `>=3.3.0 <4.0.0`
- **Android NDK:** r28+ (required for 16KB page size compatibility, mandatory since Nov 2025)
- **Android AGP:** 8.7.3+ (required for 16KB page size)
- **Provider APIs:** Blockfrost (primary), Maestro, Koios (added later)

## Repository conventions

- All Rust code lives in `rust/` with `cardano_flutter_rs` as the crate name.
- All Dart code lives in `dart/` with `cardano_flutter_rs` as the package name (avoids collision with Vespr's `cardano_flutter_sdk` on pub.dev; signals the Rust/FFI architecture).
- Generated bindings (`dart/lib/src/frb_generated.dart` + the per-module twins, e.g. `address.dart`) — **never edit by hand**; re-run codegen.
- The reference Flutter app lives in `example/` and depends on the local `dart/` package via path.
- Use MIT license throughout (matches CML/CSL upstream).
- Semantic versioning. Pre-1.0 = `0.x.y`. **`1.0.0` = safe to recommend for
  production mainnet usage on every platform it claims to support.** Concretely
  (post critic review, 2026-06-03): a *platform* must be verified before 1.0 claims
  it — Android verified on at least an emulator for the `0.12.0` RC, and on a
  physical device (+ Play Store build acceptance) before bare `1.0.0`. A *peripheral*
  (hardware wallets) may ship `@experimental` and be promoted post-1.0 (v1.1.0).
  Never use "verified on device" for emulator-only results. The README/pub.dev page
  carries a platform-support matrix so the version string never implies uniform
  readiness. (Rationale + full gates: `docs/PLAN.md` → "Roadmap restructure v2".)

## Style rules

- **Rust:** `cargo fmt` and `cargo clippy --all-targets -- -D warnings` must pass.
- **Dart:** follow `flutter_lints`. Public APIs need dartdoc comments with example usage.
- **Async:** Dart side uses `Future`/`Stream` exclusively. Rust side uses `tokio` only where network I/O is involved; signing/serialization stays sync.
- **Errors:** never panic in Rust public API. Use `thiserror`-derived error types; map to Dart exceptions via `flutter_rust_bridge`.
- **Tests:** every public function needs at least one test. Cardano testnet preview is the integration target — test mnemonics in `tests/fixtures/`.

## Build / test / lint commands

```bash
# Generate Dart bindings from Rust
flutter_rust_bridge_codegen generate

# Run Rust tests — all, one module, or one test by name
cd rust && cargo test
cd rust && cargo test address::            # one module
cd rust && cargo test test_compute_policy_id   # one test by name

# Run Dart tests (requires the dylib in rust/target/release — see below)
cd dart && flutter test
cd dart && flutter test test/conformance_test.dart   # one file
cd dart && flutter test --name "verify"              # tests matching a name

# Web conformance gate (in-browser, CML-JS backend) — see tool/web_conformance/README.md
cd dart && dart compile js web/conformance_harness.dart -o ../tool/web_conformance/build/harness.js -O2
cd tool/web_conformance && node build.mjs && node run-headless.mjs   # → PASS n FAIL 0

# Lint everything
cd rust && cargo clippy --all-targets -- -D warnings && cd ../dart && flutter analyze

# Deploy to connected iOS device (background-friendly)
cd example && flutter run -d <device-id>
```

**One-time macOS setup for `flutter test`:** the widget tests load the Rust FFI bridge.
The generated FRB loader (`frb_generated.dart` → `defaultExternalLibraryLoaderConfig`)
resolves the lib from **`rust/target/release/`** with stem `cardano_flutter_rs` — i.e.
`flutter test` opens `rust/target/release/libcardano_flutter_rs.dylib`, NOT the engine
Frameworks dir. So after any Rust change + `flutter_rust_bridge_codegen generate`, put a
**current** dylib there or tests fail with a content-hash mismatch:
```bash
cd rust && cargo build --lib            # or: cargo build --release --lib
cp target/debug/libcardano_flutter_rs.dylib target/release/libcardano_flutter_rs.dylib
```
> The dylib's embedded FRB content hash must equal `frb_generated.dart`'s
> `rustContentHash`. A debug build copied to `target/release/` is fine for tests
> (same ABI); just make sure it was compiled *after* the latest codegen.
>
> *(Legacy: older setups instead copied the dylib into the Flutter engine's
> `…/artifacts/engine/darwin-x64/Frameworks/cardano_flutter_rs.framework/`. The
> `target/release/` path above is what the current loader actually uses.)*

## Important external references

- **CML repo (primary):** https://github.com/dcSpark/cardano-multiplatform-lib
- **CSL repo (compat backend):** https://github.com/Emurgo/cardano-serialization-lib
- **Pallas repo (migration target):** https://github.com/txpipe/pallas
- **flutter_rust_bridge:** https://cjycode.com/flutter_rust_bridge
- **Android 16KB page size docs:** https://developer.android.com/guide/practices/page-sizes
- **Cardano developer portal:** https://developers.cardano.org
- **Blockfrost API:** https://blockfrost.io
- **CIP-30 (dApp connector):** https://cips.cardano.org/cip/CIP-30
- **CIP-45 (mobile WalletConnect):** https://cips.cardano.org/cip/CIP-45
- **CIP-1852 (HD derivation):** https://cips.cardano.org/cip/CIP-1852
- **Reference: CardanoKit (Swift, same architecture pattern):** https://github.com/TokeoPay/CardanoKit
- **Reference: Vespr's Dart SDK (pure-Dart competitor):** https://github.com/vespr-wallet/cardano_dart_sdk

## Project context

This is an **independent, self-funded, open-source project**. No external funders, no milestone deadlines, no votes to win. The driver is pure technical merit and long-term value to the Cardano mobile ecosystem.

What this means in practice:
1. **Quality over speed.** No artificial timeline pressure. Ship Phase N when it's actually production-ready.
2. **Scope is yours to set.** Build what serves the SDK's mission, not what fits an external funding category.
3. **Differentiation is technical.** Win by being the most correct, well-tested, well-documented SDK — not by being first or loudest.
4. **Coordination is optional.** Reach out to TokeoPay (CardanoKit) or Vespr if technical collaboration helps; otherwise focus on shipping.
5. **Sustainability via utility.** If real dApps adopt the SDK, contributors appear and maintain it organically. No grant dependency.

## Things NOT to do

- Do not reimplement Cardano cryptography in pure Dart. Use CML (or CSL/Pallas) via FFI.
- Do not put on-chain data through the Rust layer if it can be fetched in Dart via REST. Keep the FFI surface minimal.
- Do not wrap every CML type for v0.1. Wrap only what the example app needs.
- Do not skip tests against testnet preview before a CML/CSL major-version bump.
- Do not edit `frb_generated.dart` or the generated per-module twins by hand — re-run codegen.
- Do not tunnel Rust through frb-WASM for web. Use CML's official npm package via Dart JS interop instead.
- Do not skip Android 16KB page size verification — it's mandatory for Play Store since Nov 2025.
- Do not hardcode a single backend. Use feature flags / trait abstractions so CSL/CML/Pallas can be swapped.

## Communication style preferences for Claude Code

- Be concise. Skip preamble.
- When proposing a change, show the diff or the exact file contents you'd write.
- Push back on bad ideas. Don't agree to architectural choices that violate the project plan without flagging it.
- If a CSL API has changed since the project plan was written, surface the discrepancy rather than working around it.
