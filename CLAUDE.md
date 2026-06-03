# Cardano Flutter SDK — Project Memory

> This file is read by Claude Code at the start of every session. Keep it under 200 lines.

## Project overview

A production-grade, open-source Flutter SDK for the Cardano blockchain. Architecture: thin Dart API → `flutter_rust_bridge` → Rust wrapper crate → `cardano-multiplatform-lib` (CML). Targets iOS, Android, macOS, Linux, Windows via Rust FFI; web via direct JS interop to CML's npm package (not via Rust FFI).

**Why CML over CSL:** CML is co-maintained by Emurgo + dcSpark, more actively released (last update April 2025 vs CSL's August 2025), uses the same CDDL-spec generation approach, and has better CBOR preservation. Architect the Rust wrapper to make the backend swappable (CSL/CML/Pallas) via feature flags or trait abstractions — Pallas v1.0 may become the strategic long-term choice.

**Why FFI:** Generated from Cardano's official CDDL spec. By wrapping in Rust and exposing via FFI, we get correctness for free and protocol upgrades flow downstream automatically rather than requiring SDK rewrites.

**The plan:** see `docs/PLAN.md` (single source of truth). Critical review of stack choices in `.claude/goals/CRITICAL_REVIEW.md`.

## Current state

**Phase 4.5: Hardware Wallets — Core Complete; On-Device Signing PENDING** 🟡 *(2026-06-02)*

Honest status: core protocol layer done + tested; example Ledger BLE read path
code-complete; **transaction signing NOT yet verified on a physical Ledger**
(no device available). v1.0.0 **not** published — the phase's v1.0 gate
("Ledger TX signing round-trip verified on device") is deliberately still open.

Core SDK (`rust/src/hardware.rs` + `dart/lib/src/hardware/`, device-agnostic):
- `xpubToAccount(accountXpubHex, networkId)` — soft-derive base+reward addresses
  and payment/stake key hashes from a BIP-32 **account xpub** (no private keys;
  also serves watch-only). Proven to land on the same credentials as the
  mnemonic private path.
- `assembleVkeyWitnessSet` / `extractVkeyWitnesses` — device `(pubkey,sig)` pairs
  ↔ CBOR `transaction_witness_set` (symmetric; for assembly + partial-sign/multisig).
- `HardwareWallet` interface (`getAccountXpub`, `signTransaction`) + sign-request type.
- `HardwareCip30Wallet` — CIP-30-shaped wallet: addresses from xpub, balance/UTxOs
  via provider, signing delegated to device + assembled into a submittable tx.
- **Tests:** Rust 98/98 (incl. assemble↔extract identity over a real signature),
  Dart hardware suite incl. a **real-crypto round-trip** (software-sign → extract
  → mock device → `HardwareCip30Wallet` assembles a **byte-identical** tx).
  clippy clean · analyze clean.

Example (Ledger over BLE, deps in example only — Vespr's MIT `ledger_cardano_plus`
+ `ledger_flutter_plus`):
- `LedgerHardwareWallet implements HardwareWallet`: scan/connect, version,
  `getAccountXpub` (= `publicKeyHex+chainCodeHex`). **Working read path.**
- **Ledger screen**: scan → connect → derive address → balance/UTxOs via
  `HardwareCip30Wallet`. iOS BLE Info.plist keys added; deployment target → 14.0
  (universal_ble needs ≥13.1). Builds for iOS simulator.
- `signTransaction` **intentionally throws** — the device-side `ParsedSigningRequest`
  mapping (+ deriving witness pubkeys from the xpub) needs on-device validation;
  not shipped unverified. Checklist to close the gate: `docs/hardware-wallets.md`.
- **Trezor deferred** (USB-only, no BLE; Trezor Connect web bridge impractical on
  mobile). Ledger-only for v1.0; Trezor a future follow-up.

**Phase 4.4: CIP-45 Complete & Live-Verified** ✅ *(2026-06-02)*

Protocol core (package, unit-tested) + reference transport (example):
- Core: `Cip45ConnectionUri` (CIP-13 `web+cardano://` build/parse),
  `Cip45WalletHandler` (routes inbound RPC → `Cip30Wallet` + API announcement),
  `Cip45Transport` interface. Dart +15 cip45 tests.
- Transport (example): `BugoutCip45Transport` — hosts `bugout.min.js`
  (WebTorrent+WebRTC) in a headless WebView (`flutter_inappwebview`), bridges RPC.
- Example: **CIP-45 screen** (paste/deep-link a connection URI → connect → serve
  CIP-30 calls) + reference dApp page `example/assets/cip45/dapp.html`.
- iOS `web+cardano://` deep link (Info.plist + `app_links`) → opens CIP-45 screen.
- Builds for iOS simulator; **deps added to example only** (core stays lean).
- **Spec note:** CIP-45 is WebTorrent+WebRTC (not WalletConnect — common myth).
- **Live-verified (iPhone 13 ↔ desktop browser dApp, preview):** full handshake +
  CIP-30 RPC over WebTorrent/WebRTC — `getBalance` (real multi-asset), `getUtxos`
  (real UTXOs), `signData` (valid `COSE_Sign1`+`COSE_Key`) all round-tripped.
- **Session fixes:** home-screen button rows → `Wrap` (CIP-30/45 were clipped
  off-screen); `signData` handler accepts `[payload]` or `[address, payload]`
  (blank address → wallet's base address) per CIP-30; `dapp.html` made QR optional
  + on-page error surfacing. Dart +3 cip45 param tests (17 total).
  Guide: `docs/cip45-testing.md`. Transport notes: `docs/cip45-transport.md`.

**Phase 4.3: Complete & Verified** ✅ *(2026-06-02)*

CIP-30 dApp connector shipped:
- Rust `cip30` module (CSL-backed serialization + CIP-8/COSE signing):
  - `computeBaseAddress`, `addressToHex` (CIP-30 hex address encoding)
  - `valueToCborHex`, `utxoToCborHex` (CBOR `Value` / `TransactionUnspentOutput`)
  - `sumValues` (multi-asset balance folding via CSL)
  - `cip30SignTx` (returns `transaction_witness_set` hex)
  - `cip30SignData` / `cip30VerifyData` (real `COSE_Sign1` + `COSE_Key`, RFC 9052)
- Dart `Cip30Wallet` class (`fromMnemonic`) implementing the CIP-30 surface:
  `getNetworkId`, `getUtxos`, `getBalance`, `getChangeAddress`,
  `getUsedAddresses`, `getUnusedAddresses`, `getRewardAddresses`, `signTx`,
  `signData`, `submitTx`
  - `cip30SignData` / `cip30VerifyData` now built on Emurgo's
    `cardano-message-signing` (the reference COSE lib Lace/Eternl use via WASM),
    so output is interop-correct by construction
  - `cip30AssembleTx` (dApp-side: combine body + witness set into a submittable tx)
- Dart `Cip30Wallet` class (`fromMnemonic`) implementing the CIP-30 surface:
  `getNetworkId`, `getUtxos`, `getBalance`, `getChangeAddress`,
  `getUsedAddresses`, `getUnusedAddresses`, `getRewardAddresses`, `signTx`,
  `signData`, `submitTx`
- `ProtocolParameters.toProtocolParams()` extension (de-dups example screens)
- Example app: **CIP-30 screen** (live method explorer + signData/verify demo)
- **Test suite:** Rust 91/91 · Dart 119/119 · clippy clean · analyze clean
- **Live testnet verified:** end-to-end CIP-30 `signTx → assemble → submit`
  confirmed on-chain (preview tx `01cc6d66…e11277`); getUtxos/getBalance live
- iOS device + simulator dylibs rebuilt (3.2 MB each) → v0.6.0
- Caveat closed: COSE built on the reference library + interop-shaped test.
  Still nice-to-have: a real cross-wallet (Lace/Eternl) signData handshake.

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

**Phase 2.5 (complete, 2026-05-25):** Production hardening
- Rust 56/56 · Dart 102/102 · clippy clean · flutter analyze clean
- Bug fix: multi-asset change output coin=0 (ledger-invalid) → now carries min-ADA
- Bug fix: `SendScreen` dropped native tokens from UTXOs; fixed with `utxoToTxInput`
- Fee estimation now includes vkey witness overhead + per-output size
- TX confirmation polling: `pollTransactionConfirmation()` with configurable interval/timeout
- `utxoToTxInput` / `utxosToTxInputs` helpers in wrappers.dart
- Network mismatch safety gate (testnet addr + mainnet provider → hard error)
- Mainnet-aware `SendScreen`: MAINNET banner, red buttons, mainnet explorer link

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
- **Plutus cost models:** `build_script_tx` uses hardcoded Conway V1/V2/V3 cost models (copied from CSL source, since `TxBuilderConstants` is `pub(crate)`). `script_data_hash` is correct for node validation.

When you start a session, the next phase is:
- **Close the Phase 4.5 v1.0 gate:** implement + verify Ledger `signTransaction`
  on a physical device (Nano X / Stax / Flex), then publish v1.0.0. Checklist:
  `docs/hardware-wallets.md`. Needs hardware the maintainer must supply.
- Optional CIP-45 follow-ups: Android intent-filter + Android-device verify;
  in-wallet QR scanning; a `flutter_webrtc`-native transport as a bugout fallback.
- Done: 4.1 Staking (v0.4.0) · 4.2 Message Signing CIP-8 (v0.5.0) · 4.3 CIP-30 (v0.6.0)
  · 4.4 CIP-45 (v0.7.0, live-verified on iOS) · 4.5 Hardware-wallet **core**
  (v0.8.0; xpub→account, witness assemble/extract, `HardwareCip30Wallet`,
  Ledger BLE read path — **on-device signing still pending**)

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
- Do not edit `bridge_generated.dart` by hand — re-run codegen.
- Do not tunnel Rust through frb-WASM for web. Use CML's official npm package via Dart JS interop instead.
- Do not skip Android 16KB page size verification — it's mandatory for Play Store since Nov 2025.
- Do not hardcode a single backend. Use feature flags / trait abstractions so CSL/CML/Pallas can be swapped.

## Communication style preferences for Claude Code

- Be concise. Skip preamble.
- When proposing a change, show the diff or the exact file contents you'd write.
- Push back on bad ideas. Don't agree to architectural choices that violate the project plan without flagging it.
- If a CSL API has changed since the project plan was written, surface the discrepancy rather than working around it.
