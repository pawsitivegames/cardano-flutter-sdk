# Cardano Flutter SDK — Project Plan

> A production-grade, **independent, self-funded** open-source Flutter SDK for Cardano, built on `cardano-multiplatform-lib` (CML) via Rust FFI. Targets iOS, Android, macOS, Linux, Windows via FFI; web via direct JS interop.

> **Status note (2026-05-24):** This plan was originally written assuming Catalyst funding. The project has since pivoted to fully independent. Section 7 (Catalyst Strategy) is preserved for historical context but is **not active**. See `.claude/goals/INDEPENDENT_PROJECT_STRATEGY.md` for current strategy.

---

## 1. The Opportunity

- **Documented gap:** No CSL/CML-correct Flutter SDK exists. Vespr Wallet ships a pure-Dart `cardano_flutter_sdk` (v4.0.1, March 2026) but lacks transaction building, Plutus, and CIP-30 native dApp connector. reaster's pure-Dart SDK is abandoned. CardanoKit (Swift) proves the FFI architecture works but is Apple-only.
- **Stack fit:** Flutter is the fastest-growing cross-platform mobile framework. ~70% of finance app users prefer mobile. Cardano cannot reach mobile-first users without correct tooling.
- **Differentiation:** Pure-Dart Cardano SDKs carry long-term correctness risk (Cardano's CDDL spec evolves; pure-Dart needs constant reimplementation). FFI-wrapping CML/CSL means protocol upgrades flow downstream automatically.
- **Halo effect:** A clean Rust core unlocks Swift and Kotlin SDKs simultaneously via UniFFI. Core extraction pattern lets one Rust crate power three native SDKs.

---

## 2. Architecture Decision

**Build on top of `cardano-multiplatform-lib` (CML) via Rust FFI. Architect for backend swap (CSL/CML/Pallas). Do NOT reimplement in pure Dart.**

### Why CML over CSL

1. **More active maintenance.** CML's last release (April 2025) is more recent than CSL (Aug 2025 v15.0.1 was 9 months stale as of May 2026). Cadence is healthier.
2. **Same correctness story.** CML is also generated from Cardano's official CDDL spec via `cddl-codegen`. Drop-in replacement for CSL with better CBOR preservation.
3. **Co-maintained.** Emurgo + dcSpark share maintenance; broader institutional backing.
4. **Drop-in compatible.** API surface is similar enough to CSL that wrapper code is reusable.

### Why FFI (vs. pure Dart)

1. **Correctness for free.** Protocol upgrades (Conway, Plomin, future hard forks) land upstream — you bump a crate version.
2. **Maintenance load drops 10x.** The Rust wrapper is ~1–2K LOC of ergonomic API. The Dart layer focuses on developer experience, not cryptography.
3. **Mature precedent.** Tokeo's `CardanoKit` (Swift) uses this exact pattern. JavaScript bindings use it (via wasm-bindgen). It's the established architectural path.

### Backend swap strategy

The Rust wrapper should isolate the CML dependency behind a trait abstraction (e.g., `trait CardanoBackend`). Initial implementation uses CML. Feature flags enable CSL or Pallas backends. Why:

- **Pallas v1.0** (released May 2026) is where the Rust Cardano ecosystem is heading. Whisky V2 is migrating CSL → Pallas. Plan a migration before v1.0.
- **CSL compatibility** still useful for parity testing.
- **No backend lock-in** means the SDK survives an upstream library deprecation.

### Layer diagram

```
┌──────────────────────────────────────────────────┐
│  Application code (Flutter app)                   │
├──────────────────────────────────────────────────┤
│  cardano_flutter_rs (Dart package)                │  ← idiomatic, async/await,
│  - Wallet, Transaction, StakePool, etc.           │    null-safe high-level API
│  - Blockfrost/Maestro/Koios providers             │
├──────────────────────────────────────────────────┤
│ Native (iOS/Android/macOS/Linux/Windows)          │  Web (Flutter Web)
│ ─────────────────────────────────────────         │  ─────────────────────
│  flutter_rust_bridge generated bindings           │  Dart JS interop
│            ↓                                      │      ↓
│  cardano_flutter_rs (Rust wrapper crate)          │  CML official npm
│  - Backend trait: swappable CSL/CML/Pallas        │  (WASM, direct)
│  - ~1–2K LOC of ergonomic Rust API                │
│            ↓                                      │
│  cardano-multiplatform-lib (CML) — primary        │
│  cardano-serialization-lib (CSL) — compat flag    │
│  pallas (txpipe) — migration target               │
└──────────────────────────────────────────────────┘
```

**Web bypass:** Don't tunnel CML through Rust→frb-WASM→wasm_bindgen (three layers of WASM). Use Dart JS interop directly to the official CML npm package on web platform.

---

## 3. Repository Structure

```
cardano_flutter/
├── README.md
├── LICENSE                          # MIT (matches CSL, Catalyst-friendly)
├── .github/
│   └── workflows/
│       ├── rust.yml                 # cargo test on PR
│       └── dart.yml                 # flutter test on PR
├── rust/
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs                   # public API surface
│   │   ├── wallet.rs                # mnemonic, key derivation
│   │   ├── address.rs               # bech32, address types
│   │   ├── tx.rs                    # transaction building
│   │   ├── assets.rs                # native tokens, NFTs
│   │   ├── stake.rs                 # staking, delegation
│   │   └── plutus.rs                # smart contract interaction
│   └── tests/
├── dart/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── cardano_flutter.dart     # public exports
│   │   ├── src/
│   │   │   ├── wallet.dart
│   │   │   ├── providers/
│   │   │   │   ├── blockfrost.dart
│   │   │   │   ├── maestro.dart
│   │   │   │   └── koios.dart
│   │   │   ├── tx_builder.dart
│   │   │   └── bridge_generated.dart  # auto-generated, do not edit
│   │   └── cardano_flutter.dart
│   └── test/
├── example/                         # Reference Flutter app
│   └── (full Flutter project)
└── docs/
    ├── getting-started.md
    ├── api-reference.md
    └── cookbook/
```

---

## 4. Starter Files

### `rust/Cargo.toml`

```toml
[package]
name = "cardano_flutter_rs"
version = "0.1.0"
edition = "2021"
license = "MIT"

[lib]
crate-type = ["cdylib", "staticlib"]  # cdylib for Android, staticlib for iOS

[features]
default = ["backend-cml"]
backend-cml = ["cardano-multiplatform-lib"]
backend-csl = ["cardano-serialization-lib"]
backend-pallas = ["pallas"]

[dependencies]
cardano-multiplatform-lib = { version = "6.2", optional = true }
cardano-serialization-lib = { version = "15.0", optional = true }
pallas = { version = "1.0", optional = true }
flutter_rust_bridge = "2.12"          # pin exact 2.x version; breaking changes occur
anyhow = "1.0"
thiserror = "1.0"
hex = "0.4"
bip39 = "2.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
reqwest = { version = "0.12", features = ["json", "rustls-tls"], default-features = false }
tokio = { version = "1", features = ["rt", "macros"] }
```

### `dart/pubspec.yaml`

```yaml
name: cardano_flutter_rs
description: Production-grade Cardano SDK for Flutter, powered by Rust + CML via FFI.
version: 0.1.0
homepage: https://github.com/YOUR_HANDLE/cardano-flutter-sdk

environment:
  sdk: '>=3.3.0 <4.0.0'
  flutter: '>=3.19.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_rust_bridge: ^2.12.0
  ffi: ^2.1.0
  meta: ^1.10.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.0
```

### `rust/src/lib.rs` (minimal first surface)

```rust
use cardano_multiplatform_lib as cml;
use flutter_rust_bridge::frb;

pub mod address;
pub mod wallet;
pub mod tx;

/// Hello-world to confirm the bridge works.
#[frb(sync)]
pub fn sdk_version() -> String {
    format!("cardano_flutter_rs v{} (CML v{})",
        env!("CARGO_PKG_VERSION"),
        cml::VERSION_STRING)  // verify exact accessor in CML docs
}

/// Validate a Bech32 address.
pub fn is_valid_bech32(addr: String) -> bool {
    cml::address::Address::from_bech32(&addr).is_ok()
}
```

### `dart/lib/cardano_flutter_rs.dart` (the API users see)

```dart
library cardano_flutter_rs;

export 'src/wallet.dart';
export 'src/tx_builder.dart';
export 'src/providers/blockfrost.dart';
export 'src/providers/maestro.dart';
export 'src/providers/koios.dart';
export 'src/models/address.dart';
export 'src/models/transaction.dart';
```

---

## 5. Phase 0: Foundation Setup (Weeks 1–2)

> Goal: end Phase 0 with one Rust function callable from a running Flutter app on iOS + Android, with CI passing and Android 16KB page size compatibility verified. Realistic budget: **2–4 weeks**, not a weekend. The plan was originally optimistic; flutter_rust_bridge + multi-platform CI + 16KB compat is a non-trivial setup.

### Initial setup (2–3 hours)

```bash
# 1. Install toolchain
rustup default stable
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

cargo install cargo-ndk
cargo install flutter_rust_bridge_codegen --locked

# 2. Scaffold
mkdir cardano_flutter && cd cardano_flutter
git init
flutter create --template=plugin --platforms=ios,android,macos,linux,windows dart
cargo new --lib rust

# 3. Wire flutter_rust_bridge
# Follow the current quickstart at:
#   https://cjycode.com/flutter_rust_bridge/quickstart
# (the tool moves fast — use their generator rather than copy-pasting old setups)
flutter_rust_bridge_codegen create --rust-root rust --dart-root dart
```

### Phase 0 milestones (no calendar deadline; ship when ready)

**Milestone 0.1: Hello-world via FFI**
- Add `cardano-multiplatform-lib = "6.2"` to `rust/Cargo.toml` (with feature flag for backend swap)
- Write `is_valid_bech32` in `rust/src/lib.rs`
- Run `flutter_rust_bridge_codegen generate` to produce Dart bindings
- In the example Flutter app, call `isValidBech32("addr1...")` from a button tap, display result
- Verify on **both iOS simulator and Android emulator**

**Milestone 0.2: Android 16KB page size compatibility**
- Use NDK r28+ and AGP 8.7.3+
- Verify with `cargo-ndk` build flags for 16KB
- Test on Pixel 8a or equivalent (16KB device)
- Confirm Play Store internal testing track accepts the build

**Milestone 0.3: CI matrix**
- GitHub Actions workflow building on macOS, Ubuntu, Windows
- Runs `cargo test`, `cargo clippy`, `flutter test`, `flutter analyze` on each push
- Integration test on iOS simulator + Android emulator runs in CI (best effort)

**Milestone 0.4: First wallet API end-to-end**
- Implement `Wallet.fromMnemonic(String mnemonic)` — derives the master key, returns first payment address
- Test against a known mnemonic (BIP39 test vectors) — verify the address matches what Yoroi/Eternl produce for the same seed
- This is the moment you know the foundation is real

**Phase 0 exit criteria:** all four milestones complete with green CI. Time estimate: 2–4 weeks of focused work, longer if learning Rust+Flutter FFI from scratch.

---

## 6. Phased Roadmap

> **Timelines are estimates, not deadlines.** Phases ship when production-ready. Realistic budget for a single developer working part-time: 10–18 months to v1.0. See `.claude/goals/PHASES_WITH_VERIFICATION.md` for verification strategies per phase.

### Phase 1 — Read-only wallet → v0.1.0

**Deliverables:**
- Mnemonic → BIP-32-Ed25519 key derivation (CIP-1852 paths)
- Address generation: payment, stake, enterprise, byron-era for legacy support
- Mainnet, preprod, preview network support
- Blockfrost API client (start with one provider; add Maestro/Koios later)
- Query balance, UTXOs, transaction history, staking info
- Example: a Flutter wallet tracker app

**Why this scope:** ships something useful immediately, validates the architecture end-to-end, gives a real reference app to demo.

### Phase 2 — Transactions → v0.2.0

**Deliverables:**
- Transaction builder API (inputs, outputs, change, fees, metadata)
- Coin selection algorithms (largest-first, random-improve)
- Witness/signature construction
- Transaction submission via provider
- Native asset transfers (multi-asset outputs)
- Mainnet validation: small test transactions submitted successfully
- Example: send ADA + a native token

**Where CML pays off:** all the fee math, CBOR encoding, witness set construction is in CML. We orchestrate, not implement.

### Phase 3 — Smart contracts & assets → v0.3.0

**Deliverables:**
- Plutus script attachment (V2 + V3)
- Datum and redeemer encoding (using CML's PlutusData)
- Native token minting/burning
- CNFT support (CIP-25, CIP-68 metadata standards)
- Reference inputs, collateral handling
- Example: mint an NFT from a phone

### Phase 4 — Wallet connectors → v1.0.0

**Deliverables (consider integrating Vespr's funded WalletConnect SDK instead of greenfield):**
- CIP-30 dApp connector API (the in-app wallet interface)
- CIP-45 (WalletConnect v2 for Cardano) — the cross-app connector — *integrate with Vespr's funded SDK if their work is mature*
- Deep linking for iOS/Android wallet handoff
- Example: a Flutter dApp that connects to Lace/Eternl/Vespr on mobile

**Strategy:** Don't reimplement what Vespr is building with Catalyst funding. Integrate at the interface level instead.

### Phase 5 — Web, Desktop, Performance → v1.1.0

**Deliverables:**
- Web platform support via Dart JS interop to CML npm package (NOT via Rust→frb-WASM)
- macOS, Linux, Windows desktop builds
- Performance benchmarks (UTXO fetch <2s, TX build <500ms for complex)
- Pallas migration evaluation (decide on CML→Pallas swap before v1.0)

---

## 7. Project Catalyst Strategy — **DEPRECATED**

> ⚠️ **This section is no longer active.** As of 2026-05-24, the project has pivoted to fully independent / self-funded. No Catalyst submission is planned. The driver is technical merit and long-term ecosystem value, not external funding.
>
> The original Catalyst strategy is preserved below for historical context, not as guidance.

**Current strategy:** see `.claude/goals/INDEPENDENT_PROJECT_STRATEGY.md`.

Key implications of the pivot:
- No deadline pressure; phases ship when production-ready
- No artificial scope constraints (no 200K ADA cap, no "Cardano Open: Developers" category fit)
- Coordination with TokeoPay (CardanoKit) and Vespr remains optional (technical only, not political)
- Sustainability via real-world usage, not grant cycles

<details>
<summary>Historical: Original Catalyst plan (no longer active)</summary>

- Submit to current Catalyst fund after building visible work
- Target: $40K-$80K USD for Phases 2-4 (rejected by reality check; per-proposal cap is 200K ADA ~$50K)
- "Continuation" framing — submit only after Phase 1 is shipped publicly
- Reach out to Tokeo for joint proposal

</details>

---

## 8. Differentiation Strategy

The SDK differentiates on **technical correctness**, not marketing demos:

1. **CSL/CML correctness via FFI** — the only Flutter SDK that wraps the canonical, CDDL-generated Cardano libraries. Vespr's pure-Dart SDK has inherent long-term correctness drift; we don't.

2. **Backend swap architecture** — CSL/CML/Pallas can be swapped via feature flags. Future-proof against any single upstream library going legacy.

3. **Transaction building** — Vespr ships parse/sign but not build. We ship full tx-builder, coin selection, witness construction with CSL/CML semantics.

4. **Plutus & smart contracts** — No Flutter competitor has Plutus V2/V3 support today. This is the largest gap in the ecosystem.

5. **Production hardening** — Tested binary sizes, Android 16KB page size compatibility, security audit pathway, comprehensive testnet integration.

### Optional: post-v1.0 showcase demos

Once v1.0 is shipping and stable, simple demo apps that showcase capability are useful for documentation and adoption. Examples could include voice-controlled tx building, NFT minting flows, or staking dashboards. **These are optional post-v1.0 work**, not pre-v1.0 differentiators.

---

## 9. Reference Implementations to Study

| Project | Language | What to learn from it |
|---|---|---|
| `dcSpark/cardano-multiplatform-lib` | Rust | **Primary backend.** API surface to wrap. |
| `Emurgo/cardano-serialization-lib` | Rust | Compat backend; canonical API mirror |
| `txpipe/pallas` | Rust | Migration target; modular Cardano primitives |
| `TokeoPay/CardanoKit` | Swift+Rust | Same architecture pattern; potential shared Rust core |
| `vespr-wallet/cardano_dart_sdk` | Dart | Existing pure-Dart competitor; what we're differentiating against |
| `MeshJS/mesh` | TypeScript | Best-in-class developer ergonomics — match this in Dart |
| `Anastasia-Labs/lucid-evolution` | TypeScript | Modern transaction builder API design |
| `reaster/cardano_wallet_sdk` | Pure Dart | Historical reference (abandoned 2023) |

---

## 10. Key Resources

- **Developer portal:** https://developers.cardano.org
- **Cardano Forum:** https://forum.cardano.org
- **flutter_rust_bridge docs:** https://cjycode.com/flutter_rust_bridge
- **CML repo (primary backend):** https://github.com/dcSpark/cardano-multiplatform-lib
- **CSL Rust docs (compat backend):** https://docs.rs/cardano-serialization-lib
- **Pallas (migration target):** https://github.com/txpipe/pallas
- **Blockfrost (free tier API):** https://blockfrost.io
- **Android 16KB page size:** https://developer.android.com/guide/practices/page-sizes
- **Aiken (smart contract language):** https://aiken-lang.org
- **CIPs (Cardano Improvement Proposals):** https://github.com/cardano-foundation/CIPs
  - **CIP-30:** dApp-Wallet Web Bridge
  - **CIP-45:** Decentralized dApp-Wallet Pairing (WalletConnect for Cardano)
  - **CIP-1852:** HD wallet derivation paths
  - **CIP-25 / CIP-68:** NFT metadata standards

---

## 11. Honest Risk Assessment

- **Scope creep is the #1 killer.** CML/CSL have ~500 exported types. Do not wrap all of them for v1.0. Wrap what the example app needs. Add the rest by request.
- **flutter_rust_bridge v2 moves fast.** Pin exact version (2.12.x); expect 1–2 days of toolchain debugging per quarter on upgrades.
- **iOS builds are harder than Android.** Static lib + universal binary setup has rough edges. Budget extra time for the first iOS build.
- **Android 16KB page size is mandatory.** Play Store requires 16KB-compatible builds since Nov 2025. NDK r28+, AGP 8.7.3+. Verify in Phase 0.
- **CML/CSL upgrades sometimes break.** Test on testnet preview before any major-version bump. Backend swap architecture mitigates risk.
- **CSL slowing, Pallas rising.** Whisky V2 is migrating CSL→Pallas. By v1.0, evaluate whether to migrate primary backend.
- **Vespr is the real competitor.** They ship a pure-Dart `cardano_flutter_sdk` and own the obvious pub.dev name. We differentiate on correctness and tx-building capabilities, not on being first.
- **Cardano adoption may not arrive.** Even if the SDK is perfect, total addressable users depend on the broader ecosystem. Mitigation: Rust+UniFFI skills transfer to any chain.
- **Solo maintenance burnout.** No funding deadline means no external pace, which means motivation must come from within. Build slowly; rest when needed.

---

## 12. Definition of Done (v1.0.0)

- [ ] Phases 0–4 complete; semver-stable public API; no known critical bugs
- [ ] iOS, Android, macOS, Linux, Windows tested and passing CI
- [ ] Android 16KB page size compatibility verified on Pixel 8a or equivalent
- [ ] Web platform working via Dart JS interop to CML npm (no Rust→WASM tunneling)
- [ ] >80% test coverage on the Dart layer; Rust layer has CML's coverage + wrapper-specific tests
- [ ] Backend swap demonstrated: SDK works with CML and at least one alternative (CSL or Pallas) via feature flag
- [ ] Example app: full functional wallet with send/receive/stake/dApp-connect
- [ ] Mainnet validation: at least 100 transactions successfully submitted to mainnet without loss of funds
- [ ] Published to pub.dev as `cardano_flutter_rs`
- [ ] Tagged release on GitHub with binaries for all platforms
- [ ] Documentation site live (cardano-flutter-rs.dev or similar)
- [ ] At least one real third-party dApp or wallet using the SDK in production
- [ ] Security baseline: clippy clean, flutter analyze clean, no hardcoded secrets, responsible disclosure process in place
