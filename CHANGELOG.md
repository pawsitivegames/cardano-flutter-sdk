# Changelog

Phase-by-phase development history for the Cardano Flutter SDK. This is the
narrative log that used to live in `CLAUDE.md` → `## Current state`. The
forward-looking roadmap and version gates live in [`docs/PLAN.md`](docs/PLAN.md)
(the single source of truth); per-phase verification reports are in `docs/`.

Status legend: 🟢 in progress / partially verified · ✅ complete & verified ·
🟡 core complete, on-device verification pending.

---

## Phase 6 — Web (scoped) & Desktop ✅ *(2026-06-04 → 2026-06-06)*

**Web backend verified in-browser; macOS packaged & verified.** Web is a
**second backend** (no Rust FFI on web; CML-JS via Dart JS interop — Rust→WASM
stays banned). The linchpin shipped is a **CSL↔CML golden-CBOR conformance
suite** freezing the byte-for-byte contract both backends must meet.

- `dart/lib/src/conformance/conformance.dart`: `ConformanceBackend` (deterministic
  subset: key-deriv/address/value/plutus/witness/COSE), `runConformanceCase`
  dispatcher, `NativeConformanceBackend` (CSL/FFI reference). Barrel-exported.
- `dart/test/conformance/golden_cbor.json`: frozen vectors (from native via
  `generate_golden.dart`); `dart/test/conformance_test.dart` = CI gate (native
  reproduces every vector byte-for-byte + COSE sigs verify).
- `dart/lib/src/conformance/cml_web_backend.dart`: `CmlWebBackend` — all scoped
  ops mapped (`dart:js_interop` → `@dcspark/cardano-multiplatform-lib-browser`
  + `@emurgo/cardano-message-signing-browser`): address, value, plutus
  (constr/list/int/bytes), witness, COSE `signData`/`verifyData`, key derivation.
  NOT barrel-exported. Legacy `signMessageCose` left `throw` (out of contract).
- `dart/lib/src/conformance/conformance_contract.dart`: the platform-agnostic
  contract (interface + `ConformanceCase` + `runConformanceCase`), no FFI / no
  `dart:js_interop`. Split out of `conformance.dart` so the web backend compiles
  under dart2js (otherwise importing the contract dragged in the FFI chain).
- **Verified in a real browser (32/32):** `CmlWebBackend`, dart2js-compiled,
  driven through the full golden suite against the live CML 6.2.0 +
  message-signing 1.1.0 **browser WASM** builds → **PASS 32 FAIL 0**
  (`tool/web_conformance/`). First de-risked at the library level under Node
  (`tool/cml_conformance_spike/`, `PASS 24`). Divergences resolved & baked in:
  Plutus → `to_cardano_node_format()` (indefinite arrays); `Value` →
  `to_canonical_cbor_hex()` (sorted map keys). Fixed a scaffold bug
  (`BaseAddress.new` static vs JS `new`) and a dart2js int-precision bug (Plutus
  i64 rounded as float64 → `plutusDataInt` now takes `BigInt`, golden stores `n`
  as a string).
- **`CmlWebBackend.verifyData` mapped & gated (2026-06-06):** COSE_Sign1 parse +
  Ed25519 verify + identity-binding against the protected-header address. 4 new
  golden `verifyData` vectors (accept, pure-signature accept, wrong-payload
  reject, wrong-address reject) run in-browser as part of the 32/32 suite.
- **Divergence-prone vectors added (2026-06-06):** golden grew 28 → **32** —
  non-base address types (enterprise / reward / script-credential base, via
  `addressToHex`) and **nested Plutus** (`constr[list[constr,int],bytes]`,
  recursive Cardano-node indefinite arrays). CML reproduces all 32 in-browser.
- **Scoped web CIP-30 shipped (2026-06-06):** new second package entrypoint
  `dart/lib/cardano_flutter_rs_web.dart` exposing `WebCip30Wallet`
  (`dart/lib/src/web/web_cip30_wallet.dart`) — CML-JS derivation + `signData`
  over the conformance-frozen backend, chain reads over the web-capable
  Blockfrost REST provider. Out-of-scope web tx-building is deliberately absent
  (not stubbed). Native barrel untouched (no `dart:js_interop` leak).
- **Example runs on web:** `example/lib/main_web.dart` + `example/web/` (CML/MS
  WASM instantiation + BIP-39 bridge in `index.html`); `flutter build web -t
  lib/main_web.dart` compiles, renders in Chrome, backend initializes. A second
  in-browser gate `web_wallet_harness.dart` (PASS 10) proves `WebCip30Wallet`
  derivation + `signData`→`verifyData` match native golden values; wired into the
  `web-conformance` CI job (`run-headless-wallet.mjs`).
- **Cross-wallet interop harness (2026-06-06):** `test/cross_wallet_verify_test.dart`
  + `test/fixtures/cross_wallet_signatures.json` + `docs/cross-wallet-verify.md`
  — the verify side is automated; paste a real Lace/Eternl `signData` output and
  it asserts acceptance + tamper-rejection. Skips (CI-green) until populated.
- **CI gate:** the in-browser run is an automated gate — `web-conformance` job in
  `.github/workflows/ci.yml` runs `CmlWebBackend` through every vector in
  headless Chromium (Puppeteer) on each PR; fails the build on any divergence.
- **macOS desktop — packaged & verified:** `dart/macos/` is a real FFI plugin
  (podspec + symbol-forcing stub) vendoring a universal arm64+x86_64
  `cardano_flutter_rs.framework` (built by `dart/macos/build_macos_framework.sh`);
  `example/macos/` scaffolded with App-Sandbox + `network.client` entitlements.
  Release `flutter build macos` compiles/links/codesigns clean; a packaging
  integration test (`example/integration_test/macos_packaging_test.dart`, `-d macos`)
  loads the embedded framework and round-trips FFI key derivation. `macos-build`
  CI job is a hard gate. Doc: `docs/macos-packaging.md`.
- **Pending:** a captured real Lace/Eternl signature to exercise the cross-wallet
  harness (verify side is built & gated, just needs one paste); macOS example
  **send-tx** run on testnet (the example builds + the FFI integration test gates
  already). Design: `docs/web-backend.md`.

## Phase 5b — Seed encryption ✅ *(2026-06-04 → live-verified iPhone 13 2026-06-06)*

At-rest encryption for recovery secrets, **all crypto in Rust** (no Dart crypto):
- `rust/src/seed.rs`: Argon2id KDF + XChaCha20-Poly1305 AEAD. FFI `encrypt_seed`,
  `encrypt_seed_with_params`, `decrypt_seed`, `benchmark_kdf`, `default_kdf_params`.
  Self-describing versioned `CFS1` hex container; KDF params embedded + AAD-bound
  (KDF-downgrade-resistant); `Zeroizing` of derived key + plaintext. Default cost
  64 MiB / t=3 / p=1 (~101 ms dev Mac). Crates: `argon2`, `chacha20poly1305`, `zeroize`.
- Dart: generated `src/seed.dart` (sync fns + `EncryptedSeed`/`KdfParams`), exported.
- Example **Seed Vault screen** (`seed_vault_screen.dart`, `flutter_secure_storage`):
  random wrapping secret in Keychain/Keystore composed with the user password →
  stolen blob useless without the device.
- **Tests:** Rust 119/119 (+11), Dart 167/167 (+12); clippy/fmt/analyze clean.
- **Live-verified on iPhone 13 (2026-06-06):** Seed Vault ran the full
  hardware-backed round-trip — encrypt → `CFS1` blob (145 bytes) to the iOS
  Keychain → read back → decrypt → exact recovery; on-device `benchmark_kdf`
  **~158 ms** @ 64 MiB/t=3/p=1. Added `integration_test/seed_vault_test.dart`
  (+ `test_driver/`) for the on-device round-trip/benchmark.
- **Threat model:** `docs/seed-encryption.md`. Security review folded into Phase 7.

## Phase 5a — HD multi-account ✅ *(v0.9.0, live-verified on iPhone 13)*

CIP-1852 discovery + gap scan: `deriveAddress`, `HdWalletDiscovery`, Blockfrost
`isAddressUsed`, Accounts screen; Rust 108 · Dart 155. Live run discovered
account 0 (~36,092 ₳) via real Blockfrost queries; gap-limit + account-gap correct.

## Phase 4.6 — Foundation hygiene ✅ *(2026-06-04, PR #2)*

CI badge + README de-stale (status → v0.9.0), `rust/Cargo.toml` `0.1.0`→`0.9.0`.
CI/pinned-FRB/CSL-metadata/`@experimental` landed earlier in `258348d`.

## Phase 4.5 — Hardware Wallets 🟡 *(2026-06-02)*

Core complete; on-device signing pending. Core protocol layer done + tested;
example Ledger BLE read path code-complete; **transaction signing NOT yet
verified on a physical Ledger** (no device).

Core SDK (`rust/src/hardware.rs` + `dart/lib/src/hardware/`, device-agnostic):
- `xpubToAccount(accountXpubHex, networkId)` — soft-derive base+reward addresses
  and payment/stake key hashes from a BIP-32 account xpub (no private keys; also
  serves watch-only).
- `assembleVkeyWitnessSet` / `extractVkeyWitnesses` — device `(pubkey,sig)` pairs
  ↔ CBOR `transaction_witness_set` (symmetric; for assembly + partial-sign/multisig).
- `HardwareWallet` interface + `HardwareCip30Wallet` (CIP-30-shaped: addresses from
  xpub, balance/UTxOs via provider, signing delegated to device + assembled).
- **Tests:** Rust 98/98, Dart hardware suite incl. a real-crypto round-trip.

Example (Ledger over BLE, deps in example only — Vespr's MIT `ledger_cardano_plus`
+ `ledger_flutter_plus`): `LedgerHardwareWallet` scan/connect/version/getAccountXpub
(working read path); Ledger screen; iOS BLE Info.plist; deployment target → 14.0.
`signTransaction` **intentionally throws** — device-side `ParsedSigningRequest`
mapping needs on-device validation. Checklist: `docs/hardware-wallets.md`.
**Trezor deferred** (USB-only, no BLE).

## Phase 4.4 — CIP-45 ✅ *(v0.7.0, live-verified on iOS, 2026-06-02)*

Protocol core (package, unit-tested) + reference transport (example):
- Core: `Cip45ConnectionUri` (CIP-13 `web+cardano://`), `Cip45WalletHandler`
  (routes inbound RPC → `Cip30Wallet`), `Cip45Transport` interface.
- Transport (example): `BugoutCip45Transport` — hosts `bugout.min.js`
  (WebTorrent+WebRTC) in a headless WebView (`flutter_inappwebview`), bridges RPC.
- Example CIP-45 screen + reference dApp page; iOS `web+cardano://` deep link.
- **Spec note:** CIP-45 is WebTorrent+WebRTC (not WalletConnect — common myth).
- **Live-verified (iPhone 13 ↔ desktop browser dApp):** full handshake + CIP-30
  RPC over WebTorrent/WebRTC — `getBalance`, `getUtxos`, `signData` round-tripped.
- CIP-45 follow-ups: Android `web+cardano://` intent-filter; in-wallet QR scanning
  (`mobile_scanner`, verified on iPhone 13); `flutter_webrtc`-native transport
  **scaffold** (`WebrtcCip45Transport`) — WebRTC done, bugout seams
  (`Cip45SignalingChannel`=WebTorrent tracker, `Cip45RpcCodec`=NaCl/bencode)
  documented but not implemented. Guides: `docs/cip45-testing.md`,
  `docs/cip45-transport.md`.

## Phase 4.3 — CIP-30 dApp connector ✅ *(v0.6.0, live testnet verified, 2026-06-02)*

- Rust `cip30` module (CSL-backed serialization + CIP-8/COSE signing):
  `computeBaseAddress`, `addressToHex`, `valueToCborHex`, `utxoToCborHex`,
  `sumValues`, `cip30SignTx`, `cip30SignData`/`cip30VerifyData` (real `COSE_Sign1`
  + `COSE_Key`, RFC 9052, built on Emurgo's `cardano-message-signing`),
  `cip30AssembleTx`.
- Dart `Cip30Wallet` (`fromMnemonic`) implementing the CIP-30 surface;
  `ProtocolParameters.toProtocolParams()` extension; example CIP-30 screen.
- **Tests:** Rust 91/91 · Dart 119/119. **Live testnet verified:** end-to-end
  `signTx → assemble → submit` confirmed on-chain (preview tx `01cc6d66…e11277`).

## Phase 4.1 / 4.2 — Staking & Message Signing ✅ *(v0.4.0 / v0.5.0)*

Staking (v0.4.0); CIP-8 message signing (v0.5.0).

## Phase 3 — Minting, Plutus, NFT metadata ✅ *(2026-05-26)*

- Native script policies: `makePubkeyScript`, `makeTimelockExpiryScript`,
  `computePolicyId`; mint/burn: `buildMintTx`, `signMintTransaction`.
- CIP-25 metadata (label 721): `buildCip25Metadata`; CIP-68 datum: `buildCip68Datum`.
- PlutusData helpers: `plutusDataInt/Bytes/Constr/List`, `validatePlutusData`;
  Plutus V2/V3 tx: `buildScriptTx` (collateral, redeemers, script-data-hash).
- `KeyDerivationResult.paymentKeyHash` (Blake2b-224, 28 bytes); example NFT Mint screen.
- **Tests:** Rust 55/55 · Dart 93/93.

## Phase 2.5 — Production hardening ✅ *(2026-05-25)*

- Bug fix: multi-asset change output coin=0 (ledger-invalid) → now carries min-ADA.
- Bug fix: `SendScreen` dropped native tokens from UTXOs; fixed with `utxoToTxInput`.
- Fee estimation includes vkey witness overhead + per-output size.
- `pollTransactionConfirmation()`; `utxoToTxInput`/`utxosToTxInputs` in wrappers.dart.
- Network mismatch safety gate (testnet addr + mainnet provider → hard error);
  mainnet-aware `SendScreen` (banner, red buttons, mainnet explorer link).
- **Tests:** Rust 56/56 · Dart 102/102.

## Phase 2 — TX Builder, Coin Selection, Blockfrost, Signing ✅ *(2026-05-25)*

Real-device verification: iPhone 13, iOS 26.5, all green.
