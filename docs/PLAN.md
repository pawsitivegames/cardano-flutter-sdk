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
| 2.5 — Production hardening | 🔜 Next | — |
| 4+ | Planned | — |

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

---

## Roadmap

### Phase 2.5 — Production Hardening
*Scope: no new APIs, just robustness.*

- TX confirmation polling (currently fire-and-forget after submit)
- Multi-asset coin selection (CIP-2 currently ADA-only)
- Edge case fixes: dust UTXOs, change address on empty wallet, fee estimation on complex inputs
- Mainnet routing (currently testnet-only; add mainnet config + safety gate)

**Exit criteria:** 1000+ testnet txs without fund loss; mainnet config present but gated behind explicit opt-in.

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

### Phase 4 — Wallet Connectors → v1.0.0
*Dependency: Phase 3 complete.*

**Deliverables:**
- CIP-30 dApp connector API (in-app wallet interface)
- CIP-45 WalletConnect v2 for Cardano (cross-app; integrate Vespr's work, don't greenfield)
- Staking pool delegation
- Ledger / Trezor hardware wallet support (via CIP-30 bridge)
- Deep linking for iOS/Android wallet handoff
- Message signing (dApp auth)
- Example: Flutter dApp connecting to Lace / Eternl / Vespr on mobile

**Verification:**
- All CIP-30 methods implemented and spec-compliant
- Example dApp pairs with production wallets (Lace iOS, Vespr Android)
- Staking delegation confirmed on-chain
- Ledger TX signing round-trip verified
- v1.0.0 published to pub.dev

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
