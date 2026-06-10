# Changelog

All notable changes to `cardano_flutter_rs` are documented here.
This project follows [Semantic Versioning](https://semver.org). Pre-1.0 = `0.x.y`.

## 0.12.0 — Feature-complete RC

- **Android RC gate:** ARM64 16 KB page-size emulator verified: Rust FFI `.so`
  load, SDK smoke test, CIP-45 deep link, QR entry path, and `pageSizeCompat=0`.
  This is explicitly **not** physical-device verification and does not claim
  broader ABI support.
- **Web scoped backend:** `cardano_flutter_rs_web.dart`, `WebCip30Wallet`, and
  `CmlWebBackend` over CML-JS interop, locked to native bytes by the in-browser
  golden-CBOR conformance gate.
- **macOS desktop:** packaged FFI plugin verified, including a real testnet-preview
  send transaction.
- **Security hardening:** pre-1.0 review fixes for transaction change handling,
  seed KDF parameter validation, checked asset accumulation, TTL handling, COSE
  strictness, and debug Blockfrost key handling.
- **Coverage / conformance:** hand-written Dart coverage is above the 80% RC
  threshold; Rust tests, clippy, CBOR property tests, and browser conformance are
  part of the release gate.
- **Hardware wallets remain experimental:** the API is present and annotated
  `@experimental`; Ledger transaction signing is still unverified on physical
  hardware.

## 0.9.0 — HD multi-account discovery (Phase 5a)

- **Rust:** `deriveAddress(accountKey, role, index, networkId)` → `DerivedAddress`
  (bech32 base address + payment key hash) for arbitrary CIP-1852 slots.
- **Blockfrost:** `fetchAddressMetadata` / `isAddressUsed` via
  `GET /addresses/{address}/total` (the endpoint carrying `tx_count`), plus an
  `AddressMetadata` type.
- **`HdWalletDiscovery`:** BIP-44 gap-limit address scanning (`scanChain`),
  per-account scanning (`scanAccount`), and `discoverAccounts` — stops at the
  first empty account (account gap = 1); account 0 always included.
  `HdAccount` / `HdAddress` expose used addresses, next receive address, activity.
- **Example:** "Accounts" screen — discover accounts, per-account used count, next
  receive address, aggregated ADA balance.
- Tests: Rust 108 · Dart 155.

## 0.8.1

- **Foundation hygiene (Phase 4.6).** CI hardened to a real gate (Rust tests +
  clippy + fmt, Dart analyze + unit tests with the FRB bridge built first, iOS +
  macOS builds). Package metadata fixed for pub.dev: pinned
  `flutter_rust_bridge: 2.12.0`, corrected description (CSL backend), real
  repository/homepage.
- **Hardware-wallet API marked `@experimental`.** `HardwareWallet`,
  `HardwareSignRequest`, and `HardwareCip30Wallet` are implemented but signing is
  **unverified on physical hardware** (simple payments only). Stable in v1.1.0
  after the on-device verification gate closes.

## 0.8.0 — Hardware wallets (core)

- Device-agnostic core: `xpubToAccount`, `assembleVkeyWitnessSet` /
  `extractVkeyWitnesses`, `HardwareWallet` interface, `HardwareCip30Wallet`.
- Ledger BLE adapter + screen (example): scan/connect, account xpub, address +
  balance/UTxO read path.
- Ledger transaction signing implemented in code (`xpubDerivePublicKey`,
  `decomposeTxBody`); on-device verification pending.

## 0.7.0 — CIP-45 mobile dApp connector

- `Cip45ConnectionUri`, `Cip45WalletHandler`, `Cip45Transport`.
- Reference `BugoutCip45Transport` (WebTorrent + WebRTC) — live-verified iOS ↔
  desktop dApp. iOS/Android deep links; in-wallet QR scanning (verified on iPhone).

## 0.6.0 — CIP-30 dApp connector

- Full `Cip30Wallet` API (`getNetworkId`, `getUtxos`, `getBalance`, `signTx`,
  `signData`, `submitTx`, address getters). COSE/CIP-8 via Emurgo's
  `cardano-message-signing`. Live testnet `signTx → assemble → submit` verified.

## 0.5.0 — Message signing (CIP-8)

- `signData` / `verifyData` for payment and stake keys.

## 0.4.0 — Staking operations

- Stake key registration, delegation, reward withdrawal, deregistration.

## 0.3.0 — Smart contracts & NFTs

- Native token minting/burning, Plutus V2/V3 tx building, CIP-25/68 metadata.

## 0.2.x — Transaction builder, coin selection, Blockfrost, signing

- Transaction building, coin selection, Blockfrost provider, key derivation and
  signing. Production hardening (fee estimation, min-ADA change, confirmation
  polling, network-mismatch safety gate).

## 0.1.0 — Initial scaffold

- Dart API → `flutter_rust_bridge` → Rust → `cardano-serialization-lib`; iOS
  dynamic framework; mnemonic key derivation.
