# Cardano Flutter SDK — Project Plan

> Single source of truth. Last updated: 2026-05-26.
> Independent, self-funded, open-source. No deadlines — phases ship when production-ready.

---

## Architecture

```
Flutter app
    ↓
cardano_flutter_rs (Dart package)   ← idiomatic async/await API
    ↓ flutter_rust_bridge FFI
cardano_flutter_rs (Rust crate)     ← ~1-2K LOC ergonomic wrapper
    ↓
cardano-serialization-lib (CSL)     ← active backend (v15.0.3)
    [CML / Pallas via feature flag] ← swap targets
```

**Web exception:** Dart JS interop → CML npm package directly. No Rust→WASM tunnel.

**Backend swap:** Rust wrapper isolates CSL behind a trait. CML or Pallas can be swapped via feature flag without touching Dart. Pallas v1.0 is the long-term migration target.

**Why FFI over pure Dart:** Protocol upgrades (Conway, hard forks) land upstream — bump a crate version. Pure-Dart SDKs require constant reimplementation. CSL/CML are generated from Cardano's official CDDL spec.

---

## Current State

| Phase | Status | Version |
|-------|--------|---------|
| 0 — Foundation | ✅ Complete | v0.0.x |
| 1 — Read-only wallet | ✅ Complete | v0.1.0 |
| 2 — Transaction building | ✅ **Verified 2026-05-25** | v0.2.0 |
| 3 — Minting + Plutus + CIP-25/68 | ✅ **Verified 2026-05-26** | v0.3.0 |
| 2.5 — Production hardening | ✅ **Complete 2026-05-25** | v0.3.1 |
| 4.1 — Staking operations | ✅ **Verified 2026-05-26** | v0.4.0 |
| 4.2 — Message signing (CIP-8) | ✅ **Complete 2026-05-26** | v0.5.0 |
| 4.3 — CIP-30 dApp connector | ✅ **Verified 2026-06-02** | v0.6.0 |
| 4.4 — CIP-45 mobile connector | 🟡 **Core done 2026-06-02** (transport deferred) | v0.7.0 |
| 4.5+ | Planned | — |

**Phase 2 verification (2026-05-25):**
- Rust 30/30 · Dart unit 22/22 · Dart FFI 13/13 · Live Blockfrost 1/1
- Real device: iPhone 13, iOS 26.5 — all green
- Canonical test address: `addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz`

**Phase 3 verification (2026-05-26):**
- Rust 55/55 · Dart unit 93/93 · 1 live test skipped (no env key in CI)
- `cargo clippy --all-targets -- -D warnings` clean · `flutter analyze` clean
- New modules: `minting`, `metadata`, `plutus`
- `KeyDerivationResult.payment_key_hash` added
- Example app: NFT Mint screen (CIP-25, native tokens, end-to-end)
- iOS arm64 device + arm64-sim frameworks updated

**Phase 4.1 verification (2026-05-26):**
- Rust 77/77 · Dart unit 102/102 · clippy clean · flutter analyze clean
- Staking operations: register, delegate, withdraw, deregister
- Example app: Stake screen with pool delegation and reward management

**Phase 4.2 verification (2026-05-26):**
- Rust 77/77 (8 new message tests) · Dart package: no issues found
- New module: `message` with CIP-8 COSE Sign1 support
- `signMessage()` / `verifyMessage()` with payment or stake keys
- Blake2b-256 hashing + Ed25519 signatures + CBOR encoding
- Example app: Message screen with sign/verify UI for dApp auth
- Build label: build-008 · Phase 4.2

**Phase 4.3 verification (2026-06-02):**
- Rust 90/90 (13 new cip30 tests) · Dart 119/119 (17 new cip30 tests) · clippy clean · analyze clean
- Live testnet check: `Cip30Wallet` getNetworkId/getUtxos/getBalance against Blockfrost preview ✅
- New Rust module: `cip30` (CSL serialization + CIP-8/COSE_Sign1 data signing)
- New Dart class: `Cip30Wallet.fromMnemonic` — full CIP-30 method surface
- Example app: CIP-30 screen (method explorer + signData/verify)
- iOS device + simulator dylibs rebuilt (3.1 MB); example builds for simulator
- Caveat: COSE signatures round-trip-verify internally and follow CIP-8/RFC 9052,
  but interop with third-party wallets (Lace/Eternl) is not yet cross-verified.

**Phase 2.5 verification (2026-05-25):**
- Rust 56/56 · Dart 102/102 · 1 live test skipped · clippy clean · flutter analyze clean
- Bug fix: multi-asset change output coin was 0 (ledger-invalid); now correct min-ADA
- Feat: TX confirmation polling (`pollTransactionConfirmation`) with configurable interval/timeout
- Feat: `utxoToTxInput` / `utxosToTxInputs` helpers — preserves native tokens in UTXO conversion
- Fix: `SendScreen` used `assets: []` for all UTXOs, silently dropping tokens; fixed to use helpers
- Fix: fee estimation now includes vkey witness overhead (100B/input) + per-output size (65B)
- Feat: network mismatch safety gate in `SendScreen` (testnet address on mainnet provider → hard error)
- Feat: confirmation polling spinner in `SendScreen` (submits → polls → "Confirmed in block N!")
- Mainnet UI: MAINNET label, red confirm button, mainnet explorer link

---

## Roadmap

### Phase 2.5 — Production Hardening ✅
*Complete. All scope items shipped.*

---

### Phase 3 — Smart Contracts & NFTs → v0.3.0
*Dependency: Phase 2.5 complete.*

**Deliverables:**
- Plutus script attachment (V2 + V3)
- Datum and redeemer encoding (PlutusData via CSL)
- Native token minting / burning
- CNFT metadata (CIP-25 + CIP-68)
- Reference inputs + collateral handling
- Example app: mint an NFT from the phone

**Verification:**
- Datum encoding round-trips against known CSL CBOR
- Plutus V2 + V3 scripts execute on testnet preview
- NFT minting tx appears on-chain with correct CIP-25/68 metadata
- Example app mints successfully end-to-end

---

### Phase 4.1 — Staking Operations → v0.4.0
*Dependency: Phase 3 complete. Self-contained — uses existing tx-building primitives.*

**Deliverables:**
- Register stake key on-chain
- Delegate to a pool (`stake_pool_id`)
- Withdraw staking rewards
- Deregister stake key
- Example app: Stake tab (pool picker → delegate → show rewards)

**Verification:**
- Stake key registration tx confirmed on preview testnet
- Delegation tx confirmed on-chain (pool shows delegator)
- Reward withdrawal tx succeeds
- Dart tests for all staking tx builders

---

### Phase 4.2 — Message Signing (CIP-8) → v0.5.0 ✅
*Dependency: Phase 4.1 complete. Prerequisite for CIP-30.*

**Deliverables:**
- Sign arbitrary payload with payment or stake key (CIP-8 `signData`) ✅
- Verify a CIP-8 signature ✅
- Example: dApp login / auth flow in example app ✅

**Verification:**
- Signatures verified via Blake2b-256 + Ed25519 + CBOR round-trips ✅
- Round-trip sign → verify passes for both payment and stake keys ✅
- Rust 77/77 · Dart clean · Example app integrated ✅

---

### Phase 4.3 — CIP-30 dApp Connector → v0.6.0 ✅
*Dependency: Phase 4.2 complete.*

**Deliverables:**
- Full CIP-30 wallet API: `getNetworkId`, `getUtxos`, `getBalance`, `signTx`, `signData`, `submitTx`, `getChangeAddress`, `getRewardAddresses`, `getUsedAddresses`, `getUnusedAddresses` ✅
- In-app wallet interface (`Cip30Wallet` — Flutter app acts as CIP-30 wallet backend) ✅
- Example: CIP-30 screen exercising every method + signData/verify ✅

**Verification:**
- All CIP-30 methods implemented; outputs are spec-shaped (hex addresses, CBOR
  `Value`/`TransactionUnspentOutput`, `transaction_witness_set`, COSE `DataSignature`) ✅
- Rust 91/91 · Dart 119/119 · clippy + analyze clean ✅
- signData built on Emurgo's `cardano-message-signing` reference lib → interop-
  correct by construction; interop-shaped test asserts wallet-expected structure ✅
- **Live end-to-end on preview testnet:** `signTx → assemble → submit` confirmed
  on-chain (tx `01cc6d66…e11277`); getUtxos/getBalance live ✅
- Nice-to-have (not blocking): a real cross-wallet (Lace/Eternl) signData handshake.

---

### Phase 4.4 — CIP-45 mobile dApp connector → v0.7.0  🟡 core done
*Dependency: Phase 4.3 complete.*

> Correction: CIP-45 proper is **WebTorrent (discovery) + WebRTC (data channel)**
> with a CIP-13 connection URI — not WalletConnect (a common conflation). The
> roadmap label was updated to match the spec.

**Shipped (transport-agnostic protocol core, fully unit-tested):**
- `Cip45ConnectionUri` — build/parse the CIP-13 `web+cardano://connect/v1?identifier=…` URI ✅
- `Cip45WalletHandler` — bridge inbound RPC (CIP-30 method names) to `Cip30Wallet`, plus the API-announcement payload ✅
- `Cip45Transport` interface for a pluggable WebTorrent/WebRTC backend ✅
- Example: CIP-45 card (connection URI + simulated dApp RPC call) ✅
- Dart 15 new tests; analyze clean ✅

**Reference transport implemented (example app):**
- `BugoutCip45Transport` — hosts `bugout.min.js` (WebTorrent+WebRTC) in a headless
  WebView (`flutter_inappwebview`) and bridges RPC to `Cip45WalletHandler` ✅
- CIP-45 wallet screen (paste/deep-link a URI → connect → serve CIP-30 calls) ✅
- Reference dApp page `example/assets/cip45/dapp.html` (URI + QR + method buttons) ✅
- iOS `web+cardano://` deep link (Info.plist + `app_links`) ✅
- Builds for iOS simulator; deps confined to the example (core stays lean) ✅

**Pending (needs live two-peer run on a device — see `docs/cip45-testing.md`):**
- dApp page ↔ wallet connect over public trackers, RPC round-trip, signData/signTx
- Android intent-filter + Android device run (iOS prioritized first)

---

### Phase 4.5 — Hardware Wallets → v0.8.0 → v1.0.0
*Dependency: Phase 4.3 complete. Can parallel with 4.4.*

**Deliverables:**
- Ledger signing via CIP-30 bridge
- Trezor signing
- Physical device verification (Ledger Nano X / Stax)
- v1.0.0 published to pub.dev

**Verification:**
- Ledger TX signing round-trip verified on device
- v1.0.0 published to pub.dev with full changelog

---

### Phase 5 — Web, Desktop & Performance → v1.1.0
*Dependency: v1.0.0 stable.*

**Deliverables:**
- Web platform: Dart JS interop → CML npm (no Rust→WASM)
- macOS, Linux, Windows desktop builds
- Performance: UTXO fetch <2s, TX build <500ms
- Memory leak verification under sustained load

---

### Phase 6 — Advanced Features → v1.2.0
*Dependency: v1.1.0 stable + user feedback.*

**Deliverables:**
- HD wallet multi-account management
- Governance participation (CIP-36, SanchoNet)
- Seed phrase encryption / backup
- Optional: Swift SDK via UniFFI shared core
- Optional: Kotlin SDK via UniFFI shared core

---

### Phase 7 — Maintenance (Ongoing)
- Quarterly security audits
- CSL/CML/Pallas version compatibility matrix
- Community contributions + PR reviews
- API stability guarantees (semver strict, v1.x = no breaking changes)

---

## Definition of Done (v1.0.0)

- [ ] Phases 0–4 complete, semver-stable public API
- [ ] iOS + Android passing CI; Android 16KB page size verified
- [ ] Web working via Dart JS interop (no WASM tunnel)
- [ ] >80% Dart test coverage; Rust has CML coverage + wrapper tests
- [ ] Backend swap demonstrated (CSL + one alternative)
- [ ] Example app: full functional wallet (send, receive, stake, mint, connect dApp)
- [ ] Published to pub.dev as `cardano_flutter_rs`
- [ ] At least one real third-party dApp or wallet using the SDK in production
- [ ] Documentation site live
- [ ] No hardcoded secrets; clippy clean; flutter analyze clean

---

## Build & Test Commands

```bash
# Rust tests (30 tests as of Phase 2)
cargo test

# Dart tests (requires macOS framework — one-time setup below)
cd dart && flutter test

# Live Blockfrost test
cd dart && BLOCKFROST_PROJECT_ID=<key> flutter test test/providers/blockfrost_live_test.dart

# Lint
cargo clippy --all-targets -- -D warnings && flutter analyze

# Deploy to device (run in background; monitor via iPhone Mirroring)
cd example && flutter run -d <device-id>

# Regenerate Dart bindings after Rust API changes
flutter_rust_bridge_codegen generate
```

**One-time macOS setup for `flutter test`** (widget tests load the Rust FFI bridge):
```bash
cargo build --lib
FWDIR="/opt/homebrew/Caskroom/flutter/$(flutter --version | head -1 | awk '{print $2}')/flutter/bin/cache/artifacts/engine/darwin-x64/Frameworks"
mkdir -p "$FWDIR/cardano_flutter_rs.framework"
cp rust/target/debug/libcardano_flutter_rs.dylib "$FWDIR/cardano_flutter_rs.framework/cardano_flutter_rs"
install_name_tool -id "@rpath/cardano_flutter_rs.framework/cardano_flutter_rs" "$FWDIR/cardano_flutter_rs.framework/cardano_flutter_rs"
```

---

## Key Decisions (Locked)

| Decision | Choice | Reason |
|----------|--------|--------|
| Package name | `cardano_flutter_rs` | Avoids collision with Vespr's `cardano_flutter_sdk`; signals Rust/FFI |
| Active backend | CSL v15.0.3 | Shipped Phase 1 & 2; swap to CML/Pallas is long-term |
| FFI framework | flutter_rust_bridge v2.12 (pinned) | Best Dart↔Rust option; breaking changes require pinning |
| iOS binary | Dynamic framework | `dart/ios/Libs/cardano_flutter_rs.framework` |
| Web strategy | Dart JS interop → CML npm | No Rust→WASM tunnel |
| Funding | Independent, self-funded | No Catalyst; quality over speed |
| Android NDK | r28+ | 16KB page size mandatory since Nov 2025 |

---

## Risks

- **flutter_rust_bridge moves fast** — pin exact 2.x version; budget 1–2 days/quarter for upgrades
- **CSL slowing, Pallas rising** — Whisky V2 migrated CSL→Pallas; evaluate before v1.0
- **Vespr is the real competitor** — differentiate on correctness + tx-building, not speed
- **Scope creep** — CSL/CML have ~500 exported types; wrap only what the example app needs
- **Android 16KB mandatory** — verify on Pixel 8a before any Play Store submission
