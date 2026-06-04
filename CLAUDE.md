# Cardano Flutter SDK — Project Memory

> This file is read by Claude Code at the start of every session. Keep it under 200 lines.

## Project overview

A production-grade, open-source Flutter SDK for the Cardano blockchain. Architecture: thin Dart API → `flutter_rust_bridge` → Rust wrapper crate → `cardano-multiplatform-lib` (CML). Targets iOS, Android, macOS, Linux, Windows via Rust FFI; web via direct JS interop to CML's npm package (not via Rust FFI).

**Why CML over CSL:** CML is co-maintained by Emurgo + dcSpark, more actively released (last update April 2025 vs CSL's August 2025), uses the same CDDL-spec generation approach, and has better CBOR preservation. Architect the Rust wrapper to make the backend swappable (CSL/CML/Pallas) via feature flags or trait abstractions — Pallas v1.0 may become the strategic long-term choice.

**Why FFI:** Generated from Cardano's official CDDL spec. By wrapping in Rust and exposing via FFI, we get correctness for free and protocol upgrades flow downstream automatically rather than requiring SDK rewrites.

**The plan:** see `docs/PLAN.md` (single source of truth). Critical review of stack choices in `.claude/goals/CRITICAL_REVIEW.md`.

## Current state

**Phase 6: Web (scoped) & Desktop — WEB BACKEND VERIFIED IN-BROWSER; macOS
PENDING** 🟢 *(2026-06-04)*
Web = a **second backend** (no Rust FFI on web; CML-JS via Dart JS interop —
Rust→WASM stays banned). Shipped the linchpin: a **CSL↔CML golden-CBOR
conformance suite** freezing the byte-for-byte contract both backends must meet.
- `dart/lib/src/conformance/conformance.dart`: `ConformanceBackend` (deterministic
  subset: key-deriv/address/value/plutus/witness/COSE), `runConformanceCase`
  dispatcher, `NativeConformanceBackend` (CSL/FFI reference). Barrel-exported.
- `dart/test/conformance/golden_cbor.json`: **23 frozen vectors** (from native via
  `generate_golden.dart`); `dart/test/conformance_test.dart` = CI gate (native
  reproduces every vector byte-for-byte + COSE sigs verify).
- `dart/lib/src/conformance/cml_web_backend.dart`: `CmlWebBackend` — **all scoped
  ops now mapped** (`dart:js_interop` → `@dcspark/cardano-multiplatform-lib-browser`
  + `@emurgo/cardano-message-signing-browser`): address, value, plutus
  (constr/list/int/bytes), witness, COSE `signData`, key derivation. NOT
  barrel-exported. `verifyData`/legacy `signMessageCose` left `throw` (out of
  contract).
- `dart/lib/src/conformance/conformance_contract.dart`: NEW — the platform-agnostic
  contract (interface + `ConformanceCase` + `runConformanceCase`), no FFI / no
  `dart:js_interop`. Split out of `conformance.dart` so the web backend compiles
  under dart2js (without it, importing the contract dragged in the FFI chain →
  web build impossible). `conformance.dart` keeps `NativeConformanceBackend` and
  re-exports the contract.
- **VERIFIED IN A REAL BROWSER (24/24):** `CmlWebBackend`, dart2js-compiled, driven
  through the full golden suite against the live CML 6.2.0 + message-signing 1.1.0
  **browser WASM** builds → **PASS 24 FAIL 0** (`tool/web_conformance/`). First
  de-risked at the library level under Node (`tool/cml_conformance_spike/`, also
  `PASS 24`). Divergences resolved & baked in: Plutus → `to_cardano_node_format()`
  (indefinite arrays); `Value` → `to_canonical_cbor_hex()` (sorted map keys). Fixed
  a scaffold bug (`BaseAddress.new` static vs JS `new`) and a dart2js int-precision
  bug (Plutus i64 rounded as float64 → `plutusDataInt` now takes `BigInt`, golden
  stores `n` as a string).
- **Tests:** Dart **+4** conformance (native 4/4 green); analyze clean; web harness
  24/24 in-browser. Rust unchanged.
- **Pending (honest):** wire the in-browser run into CI as a headless step (today
  it's a manual `npm install` + `dart compile js` + browser harness); web example
  app build; macOS packaging (needs trimmed example — many plugins mobile-only);
  Lace/Eternl cross-wallet `verifyMessage` check; `CmlWebBackend.verifyData` mapping.
  Design: `docs/web-backend.md`.

**Phase 4.6: Foundation hygiene — COMPLETE** ✅ *(2026-06-04, PR #2)*
CI badge + README de-stale (status → v0.9.0, fixed broken `docs/project-plan.md`
links), `rust/Cargo.toml` version `0.1.0`→`0.9.0`. CI/pinned-FRB/CSL-metadata/
`@experimental` had landed earlier in `258348d`. Web CI build deferred to Phase 6
(no web backend yet).

**Phase 5b: Seed encryption — CORE COMPLETE; on-device verify PENDING** 🟡 *(2026-06-04)*
At-rest encryption for recovery secrets, **all crypto in Rust** (no Dart crypto):
- `rust/src/seed.rs`: Argon2id KDF + XChaCha20-Poly1305 AEAD. FFI `encrypt_seed`,
  `encrypt_seed_with_params`, `decrypt_seed`, `benchmark_kdf`, `default_kdf_params`.
  Self-describing versioned `CFS1` hex container; KDF params embedded + **AAD-bound**
  (KDF-downgrade-resistant); `Zeroizing` of derived key + plaintext. Default cost
  64 MiB / t=3 / p=1 (~101 ms dev Mac). Crates: `argon2`, `chacha20poly1305`, `zeroize`.
- Dart: generated `src/seed.dart` (sync fns + `EncryptedSeed`/`KdfParams`), exported.
- Example **Seed Vault screen** (`seed_vault_screen.dart`, `flutter_secure_storage`):
  random wrapping secret in Keychain/Keystore composed with the user password
  (input composition only) → stolen blob useless without the device.
- **Tests:** Rust 119/119 (+11), Dart 167/167 (+12); clippy/fmt/analyze clean.
- **Threat model:** `docs/seed-encryption.md`. **Pending:** iPhone 13 benchmark +
  Keychain round-trip (needs iOS framework rebuilt with seed symbols); security
  review folded into Phase 7.

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

**Roadmap restructure v2 (2026-06-03, post critic review)** — `docs/PLAN.md` is the
source of truth. No Android phone, no spare Ledger. Three adversarial critics
reviewed v1 and the plan was corrected: the feature-complete build ships as
**`0.12.0` RC (iOS verified · macOS · Web scoped · Android emulator-verified)**, NOT
`1.0.0`. The bare **`1.0.0`** tag waits for **Android on a physical device** (a
platform, ~70% of mobile — a used Pixel is the cheap unblock). **Ledger** is a
peripheral → stays `@experimental` → verified in **v1.1.0**.

When you start a session, the next phase is:
- **Phase 4.6 — Foundation hygiene → v0.8.1 (do first; cheap, unblocks all):** CI
  (GitHub Actions: cargo test/clippy, analyze, flutter test, build iOS/macOS/web),
  pubspec/Cargo metadata hygiene (pin `flutter_rust_bridge: =2.12.x`, fix "CSL" not
  "CML" in description, drop `YOUR_HANDLE`), mark hardware-wallet API `@experimental`.
- **5a** HD multi-account (CIP-1852 discovery + gap scan) ✅ **complete & live-verified
  on iPhone 13 (v0.9.0)** — `deriveAddress`, `HdWalletDiscovery`, Blockfrost
  `isAddressUsed`, Accounts screen; Rust 108 · Dart 155. Live run discovered
  account 0 (~36,092 ₳) via real Blockfrost queries; gap-limit + account-gap correct.
- Next: **5b** seed encryption (Rust Argon2id + XChaCha20-Poly1305, threat model,
  security review — NOT pure-Dart crypto) → **6** Web *scoped* (CML-JS backend =
  second backend; golden-CBOR CSL↔CML conformance suite; macOS packaging) → **7**
  CIP-36 governance + security review + Pallas eval + fuzzing → **0.12.0 RC**.
- **Android emulator IS valid partial verification** (app + FFI `.so` load + 16KB
  page-size image, Google's recommended test) — label "emulator", never "device".
- **Track B (physical-device-gated → v1.1.0):** H1 Ledger TX signing on a *spare*
  device (Nano S Plus ≈ $80 — NOT the maintainer's main-account Ledger; signing
  models simple payments only, expect more than the alonzo↔babbage fix). H2 Android
  physical-device + Play Store acceptance. Native WebRTC transport = unbuilt
  research (Dart WebTorrent client + bugout NaCl/bencode), not "parked verification".
  Checklists: `docs/hardware-wallets.md`, `docs/cip45-transport.md`.
- CIP-45 follow-ups (2026-06-03): Android `web+cardano://` intent-filter ✅
  (Android-device verify pending), in-wallet QR scanning (`mobile_scanner`) ✅
  **verified on iPhone 13** (scan dApp QR → parse → CIP-45 connect → API handshake),
  `flutter_webrtc`-native transport **scaffold** (`WebrtcCip45Transport`) — WebRTC
  done; bugout seams (`Cip45SignalingChannel`=WebTorrent tracker, `Cip45RpcCodec`=
  NaCl/bencode) documented, not implemented. Remaining: a Dart WebTorrent tracker
  client + bugout framing, plus Android-device live run.
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
