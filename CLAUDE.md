# Cardano Flutter SDK — Project Memory

> This file is read by Claude Code at the start of every session. Keep it under 200 lines.

## Project overview

A production-grade, open-source Flutter SDK for the Cardano blockchain. Architecture: thin Dart API → `flutter_rust_bridge` → Rust wrapper crate → `cardano-multiplatform-lib` (CML). Targets iOS, Android, macOS, Linux, Windows via Rust FFI; web via direct JS interop to CML's npm package (not via Rust FFI).

**Why CML over CSL:** CML is co-maintained by Emurgo + dcSpark, more actively released (last update April 2025 vs CSL's August 2025), uses the same CDDL-spec generation approach, and has better CBOR preservation. Architect the Rust wrapper to make the backend swappable (CSL/CML/Pallas) via feature flags or trait abstractions — Pallas v1.0 may become the strategic long-term choice.

**Why FFI:** Generated from Cardano's official CDDL spec. By wrapping in Rust and exposing via FFI, we get correctness for free and protocol upgrades flow downstream automatically rather than requiring SDK rewrites.

**The plan:** see `docs/PLAN.md` (single source of truth). Critical review of stack choices in `.claude/goals/CRITICAL_REVIEW.md`.

## Current state

**Phase 3: Complete & Verified** ✅ *(2026-05-26)*

Native token minting, Plutus data encoding, and CIP-25/68 NFT metadata shipped:
- Native script policies: `makePubkeyScript`, `makeTimelockExpiryScript`, `computePolicyId`
- Mint/burn transactions: `buildMintTx`, `signMintTransaction`
- CIP-25 metadata (label 721): `buildCip25Metadata`
- CIP-68 datum: `buildCip68Datum`
- PlutusData helpers: `plutusDataInt/Bytes/Constr/List`, `validatePlutusData`
- Plutus V2/V3 tx: `buildScriptTx` (collateral, redeemers, script-data-hash)
- `KeyDerivationResult.paymentKeyHash` (Blake2b-224, 28 bytes)
- Example app: **NFT Mint screen** (end-to-end CIP-25 mint demo)
- **Test suite:** Rust 55/55 · Dart 93/93 · clippy clean · flutter analyze clean
- iOS arm64 device + arm64-sim frameworks updated (2.8 MB each)

**Phase 2 (also complete, 2026-05-25):** TX Builder, Coin Selection, Blockfrost, Signing
- Real-device verification: iPhone 13, iOS 26.5, all green

Decisions made:
- **Package name:** `cardano_flutter_rs` (pub.dev) + crate name `cardano_flutter_rs` (crates.io)
- **Active backend:** **CSL** (`cardano-serialization-lib` v15.0.3) — Phases 1–3 on CSL.
- **FFI:** flutter_rust_bridge v2.12 (pinned)
- **iOS binary:** dynamic framework (`dart/ios/Libs/cardano_flutter_rs.framework`)
- **Platform strategy:** Native via Rust FFI; web via JS interop (future)
- **Independent project, no Catalyst funding** — self-funded, quality-driven
- **Env var:** `BLOCKFROST_PROJECT_ID` (for live integration tests in CI)
- **Phase 3 known limit:** `build_script_tx` uses empty Costmdls (CSL v15 hides vasil cost models); Plutus txs fail node validation until resolved.

When you start a session, the next phase is:
- **Phase 2.5 (planned):** Better confirmation polling, multi-asset coin selection, edge case fixes
- **Phase 4:** Staking operations, hardware wallets (Ledger/Trezor), CIP-30

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
- Generated bindings go in `dart/lib/src/bridge_generated.dart` — **never edit by hand**.
- The reference Flutter app lives in `example/` and depends on the local `dart/` package via path.
- Use MIT license throughout (matches CML/CSL upstream).
- Semantic versioning. Pre-1.0 = `0.x.y`. v1.0 = first version that's safe to recommend for production mainnet usage (definition is technical readiness, not feature checklist).

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

# Run Rust tests (55 tests)
cd rust && cargo test

# Run Dart tests (requires macOS framework — see below)
cd dart && flutter test

# Lint everything
cd rust && cargo clippy --all-targets -- -D warnings && cd ../dart && flutter analyze

# Deploy to connected iOS device (background-friendly)
cd example && flutter run -d <device-id>
```

**One-time macOS setup for `flutter test`:** the widget tests load the Rust FFI bridge.
Build the debug dylib and install it where Flutter's test runner searches:
```bash
cd rust && cargo build --lib
FLUTTER_FRAMEWORKS="/opt/homebrew/Caskroom/flutter/$(flutter --version | head -1 | awk '{print $2}')/flutter/bin/cache/artifacts/engine/darwin-x64/Frameworks"
mkdir -p "$FLUTTER_FRAMEWORKS/cardano_flutter_rs.framework"
cp target/debug/libcardano_flutter_rs.dylib "$FLUTTER_FRAMEWORKS/cardano_flutter_rs.framework/cardano_flutter_rs"
install_name_tool -id "@rpath/cardano_flutter_rs.framework/cardano_flutter_rs" "$FLUTTER_FRAMEWORKS/cardano_flutter_rs.framework/cardano_flutter_rs"
```

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
- Do not edit `bridge_generated.dart` by hand — re-run codegen.
- Do not tunnel Rust through frb-WASM for web. Use CML's official npm package via Dart JS interop instead.
- Do not skip Android 16KB page size verification — it's mandatory for Play Store since Nov 2025.
- Do not hardcode a single backend. Use feature flags / trait abstractions so CSL/CML/Pallas can be swapped.

## Communication style preferences for Claude Code

- Be concise. Skip preamble.
- When proposing a change, show the diff or the exact file contents you'd write.
- Push back on bad ideas. Don't agree to architectural choices that violate the project plan without flagging it.
- If a CSL API has changed since the project plan was written, surface the discrepancy rather than working around it.
