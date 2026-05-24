# Cardano Flutter SDK — Complete Roadmap with Verification Strategies

**Summary:** 8 phases (0–7) to production-grade v1.0 + ecosystem SDKs. **Independent project, no fixed deadlines.** Phases ship when production-ready. Realistic single-developer part-time estimate: 10–18 months to v1.0.

> **Stack decision (2026-05-24):** Primary backend is **CML** (Cardano Multiplatform Lib), with backend-swap architecture supporting CSL and Pallas via feature flags. Package name: `cardano_flutter_rs`.

---

## Phase 0: Foundation Setup → v0.0.x

**Goal:** flutter_rust_bridge bootstrapped, Android 16KB page size verified, hello-world callable from Dart on iOS+Android, CI green.

### Deliverables

- flutter_rust_bridge v2.12+ codegen pipeline configured
- `cardano_flutter_rs` Rust crate scaffold with backend trait (CML primary, CSL/Pallas feature-gated)
- `cardano_flutter_rs` Dart package scaffold with example app
- Hello-world function (`is_valid_bech32`) callable end-to-end on iOS simulator and Android emulator
- **Android 16KB page size compatibility verified** (NDK r28+, AGP 8.7.3+)
- CI matrix: macOS, Ubuntu, Windows runners; runs cargo test, cargo clippy, flutter test, flutter analyze
- Documentation: README, CONTRIBUTING.md, LICENSE, CODE_OF_CONDUCT.md, SECURITY.md in place

### Verification Strategy

| Verification | What | How |
|---|---|---|
| **Build** | flutter_rust_bridge codegen | Generates `bridge_generated.dart` without errors |
| **Build** | iOS staticlib | `cargo build --target aarch64-apple-ios` succeeds |
| **Build** | Android NDK | `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86` succeeds |
| **Build** | Android 16KB page size | Test on Pixel 8a; Play Store internal testing accepts build |
| **Run** | iOS simulator | Example app launches, calls Rust function, displays result |
| **Run** | Android emulator | Same as iOS — verified on emulator with 16KB page size |
| **CI** | All platforms | GitHub Actions matrix passes on push to main |
| **Lint** | cargo clippy | `cargo clippy --all-targets -- -D warnings` passes |
| **Lint** | flutter analyze | `flutter analyze` passes with no warnings |

### Success Criteria
- ✅ `is_valid_bech32("addr1...")` returns correct result on iOS simulator AND Android emulator
- ✅ Android 16KB page size build runs on a Pixel 8a or similar device
- ✅ CI green on every push to main
- ✅ Backend trait defined in Rust; CML is wired up (even if minimal usage)
- ✅ Time estimate: 2–4 weeks of focused work

### Blockers & Risks
- **Risk:** flutter_rust_bridge codegen quirks on Windows
- **Risk:** Android NDK r28 + AGP 8.7.3 setup complexity
- **Risk:** iOS universal binary (lipo) configuration
- **Mitigate:** Reference Ferrostar (StadiaMaps/ferrostar) for production cross-platform Rust+Flutter setup

---

## Phase 1: Read-Only Wallet → v0.1.0

**Status:** Planned via `.claude/goals/phase-1.md` + 5 parallel agents  
**Blocked by:** Phase 0 (FFI bootstrap, Android 16KB)

### Deliverables
- Mnemonic → BIP-32-Ed25519 key derivation (CIP-1852 paths)
- Address generation (payment, stake, enterprise, Byron legacy)
- Mainnet + testnet (preprod, preview) support
- Blockfrost API client (read-only: balance, UTXOs, history, staking info)
- Full test coverage (unit + integration against testnet)
- Working example app (wallet tracker)

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Unit tests** | All Rust PoC functions | `cargo test` ≥2 tests per function | Rust Agent |
| **Unit tests** | All Dart wrappers | `flutter test` ≥2 tests per function | Dart Agent |
| **Integration tests** | Address derivation correctness | Derive address from known mnemonic, compare with Yoroi/Eternl output | Test Agent |
| **Integration tests** | Blockfrost connectivity | Fetch real UTXO from testnet preview, deserialize, re-serialize | Test Agent |
| **Platform tests** | iOS simulator | `flutter run` on iOS simulator, no crashes | Example Agent |
| **Platform tests** | Android emulator | `flutter run` on Android emulator, no crashes | Example Agent |
| **Manual acceptance** | Example app flow | User enters address → validate → result displays | Coordinator |
| **Security baseline** | No panics in Rust | Rust public API returns `Error`, never panics | Code Review |
| **Linting** | Rust style | `cargo clippy --all-targets -- -D warnings` passes | CI/Agent |
| **Linting** | Dart style | `flutter analyze` passes; no warnings | CI/Agent |

### Success Criteria
- ✅ Example app runs on iOS simulator and Android emulator
- ✅ All Rust public functions have ≥2 tests
- ✅ All Dart public functions have ≥2 tests
- ✅ Address derivation tested against known mnemonics
- ✅ Integration test against Cardano testnet passes
- ✅ No clippy warnings; no Flutter analyze warnings
- ✅ README has working setup/build/test instructions
- ✅ Published to GitHub (open-source, MIT license)

### Blockers & Risks
- **Risk:** flutter_rust_bridge v2.x is fast-moving; version pinning required
- **Risk:** iOS static lib linking can be finicky; budget extra time
- **Mitigate:** Research Agent deep-dives on platform-specific FFI quirks upfront

---

## Phase 2: Transaction Building & Signing → v0.2.0

**Dependency:** Phase 1 complete (address derivation, UTXO fetching)

### Deliverables
- Transaction builder API (inputs, outputs, change, fees, metadata)
- Coin selection algorithms (largest-first, random-improve, simple)
- Witness/signature construction via CSL
- Transaction submission via Blockfrost
- Native asset transfers (multi-asset outputs)
- Working example: send ADA + native token
- Full test coverage (fee math, witness generation, on-chain submission)

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Unit tests** | Fee calculation | Build 10 test transactions with varying inputs/outputs, verify fee against known CSL results | Test Agent |
| **Unit tests** | Coin selection | Test algorithm on synthetic UTXOs, verify selection correctness | Test Agent |
| **Unit tests** | Witness construction | Build transaction, sign with known key, verify signature via CSL | Test Agent |
| **Integration tests** | Transaction round-trip | Build TX → serialize → deserialize → verify CBOR matches original | Test Agent |
| **Integration tests** | Multi-asset output | Build TX with ADA + native token, verify output serialization | Test Agent |
| **Integration tests** | Testnet submission** | Build real transaction, submit to testnet preview, verify on-chain | Test Agent + Coordinator |
| **Acceptance tests** | Example app send flow | User selects UTXO → enters recipient + amount → reviews fee → confirms signature → TX submitted | Example Agent |
| **Property tests** | Invariants | All outputs ≤ inputs + minting; all fees ≥ min protocol fee | Property testing framework |

**\*Do not submit to mainnet in Phase 2 — testnet preview only**

### Success Criteria
- ✅ Transaction builder API is type-safe and ergonomic
- ✅ Coin selection produces valid witness sets
- ✅ Fee calculation matches CSL + protocol spec
- ✅ Multi-asset transactions serialize correctly
- ✅ Test TX submitted to testnet preview and appears on-chain within 1 minute
- ✅ Example app can send real ADA + native token on testnet
- ✅ All edge cases tested (insufficient inputs, dust outputs, extreme fees)
- ✅ No mainnet submissions; testnet preview only

### Blockers & Risks
- **Risk:** Fee calculation changes with protocol epochs; test against current epoch
- **Risk:** Witness set construction is complex; CSL version mismatches break easily
- **Mitigate:** Testnet-only in Phase 2; full validation before mainnet in Phase 2.5

---

## Phase 2.5 (Optional): Mainnet Validation & Production Hardening

**Decision gate:** Ship Phase 2 to mainnet only after:
- ✅ 1000+ testnet preview transactions tested without loss of funds
- ✅ Security audit of Rust FFI boundary (optional, but recommended before real money)
- ✅ Mainnet feature parity verified (same protocol version as live chain)

### Deliverables
- Mainnet + testnet detection and routing
- Production config (Blockfrost mainnet + testnet endpoints)
- Error telemetry and logging (no PII)
- Rate-limiting and retry logic

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Manual tests** | Mainnet connectivity | Query real wallet address via Blockfrost mainnet; verify balances | Coordinator |
| **Smoke tests** | Mainnet transaction submission | Build and submit small test TX on testnet, then equivalent on mainnet (with real ADA) | Coordinator |
| **Audit** | FFI security | Review Rust→Dart boundary for memory safety, panic freedom | Optional external auditor |
| **Performance** | Transaction submission latency | Measure time from signing to on-chain confirmation; target <5 seconds | Coordinator |

### Success Criteria
- ✅ v0.2.0 published and ready for production use
- ✅ Mainnet transactions work end-to-end
- ✅ No loss of user funds in internal testing
- ✅ Security audit completed (if budget allows) or internal review documented

---

## Phase 3: Smart Contracts & Advanced Assets → v0.3.0

**Dependency:** Phase 2 complete (transaction building, signing)

### Deliverables
- Plutus script attachment (V2 + V3)
- Datum and redeemer encoding (PlutusData via CSL)
- Native token minting/burning
- CNFT support (CIP-25, CIP-68 metadata standards)
- Reference inputs and collateral handling
- Working example: mint an NFT from the app
- Full test coverage (script validation, datum serialization, on-chain interaction)

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Unit tests** | Datum encoding | Encode sample Plutus data, verify CBOR matches known CSL output | Test Agent |
| **Unit tests** | Redeemer construction | Build redeemer for known script, verify serialization | Test Agent |
| **Unit tests** | CNFT metadata | Encode CIP-25 and CIP-68 metadata, verify JSON structure | Test Agent |
| **Integration tests** | Plutus V2 script execution | Build TX with V2 script, submit to testnet, verify script validation | Test Agent |
| **Integration tests** | Plutus V3 script execution | Build TX with V3 script, submit to testnet (requires Conway era), verify | Test Agent |
| **Integration tests** | Minting transaction | Build minting TX, mint 1 NFT, submit to testnet, query result | Test Agent |
| **Acceptance tests** | Example app mint flow | User reviews metadata → mints 1 NFT → verifies on-chain | Example Agent |
| **Property tests** | Invariants | All reference inputs exist; all mints have valid redeemers | Property testing |

### Success Criteria
- ✅ Plutus V2 and V3 scripts can be executed
- ✅ Datum/redeemer serialization matches CSL spec
- ✅ NFT minting works and appears on testnet with correct metadata
- ✅ Example app successfully mints CNFT
- ✅ All edge cases tested (missing datums, invalid redeemers, out-of-gas)

### Blockers & Risks
- **Risk:** Conway era features (V3) may not be stable on testnet; use preprod or preview
- **Risk:** Plutus script debugging is opaque; compile error messages from CSL can be cryptic
- **Mitigate:** Use Aiken language (Cardano's Plutus DSL) for reference examples; include error mapping guides

---

## Phase 4: Wallet Connectors & dApp Integration → v1.0.0

**Dependency:** Phase 3 complete (multi-asset, Plutus support)

### Deliverables
- CIP-30 dApp connector API (in-app wallet interface for dApps)
- CIP-45 WalletConnect v2 for Cardano (cross-app connector)
- Deep linking for iOS/Android wallet handoff (e.g., open Eternl, return to dApp)
- Message signing (dApp authentication)
- Working example: Flutter dApp connecting to Lace/Eternl/Vespr on mobile
- Full test coverage (CIP compliance, message signing, cross-app flows)

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Unit tests** | CIP-30 API spec compliance | Test all required methods; verify return types match spec | Test Agent |
| **Unit tests** | Message signing | Sign message with known key, verify signature determinism | Test Agent |
| **Unit tests** | WalletConnect v2 handshake | Encode/decode WalletConnect messages, verify format | Test Agent |
| **Integration tests** | CIP-30 dApp ↔ wallet | Build demo dApp, connect via CIP-30, request signature, verify | Example Agent |
| **Integration tests** | WalletConnect pairing | Pair example dApp with Lace (iOS) or Vespr (Android) via QR code | Example Agent |
| **Integration tests** | Message signing flow | User clicks "Sign message" in dApp → review → wallet signature → return to dApp | Example Agent |
| **Integration tests** | Cross-app handoff | Deep link from dApp → Eternl → back to dApp with signature | Example Agent |
| **Acceptance tests** | Real wallet integration | Connect to production wallet (Lace, Eternl, Vespr) on testnet | Coordinator |
| **Security tests** | CIP-30 origin validation | Verify dApp cannot forge origin; wallets enforce same-origin policy | Security review |

**Note:** Requires access to production wallets (Lace, Eternl, Vespr). Coordinate with wallet teams.

### Success Criteria
- ✅ Example dApp successfully connects to Lace (iOS) and Vespr (Android)
- ✅ User can request signature from connected wallet
- ✅ WalletConnect pairing QR code works with production wallets
- ✅ All CIP-30 methods implemented and tested
- ✅ Deep linking works on iOS and Android
- ✅ v1.0.0 published to pub.dev with semantic versioning

### Blockers & Risks
- **Risk:** Production wallets may not have full CIP-30/CIP-45 support on mobile; fall back to web bridge
- **Risk:** WalletConnect v2 for Cardano is nascent; may require wallet team coordination
- **Mitigate:** Start with CIP-30 (simpler in-app connector); WalletConnect is phase 4.5 if wallets support it

---

## Phase 4.5 (Optional): dApp Ecosystem Growth

**Decision gate:** Only after v1.0.0 ships and is stable for 1–2 weeks.

### Deliverables
- Partner with 2–3 dApp projects (Minswap, SundaeSwap, JPG Store) to integrate SDK
- Port SDK to Swift via UniFFI (unlock iOS native wallets)
- Port SDK to Kotlin via UniFFI (unlock Android native wallets)
- Comprehensive developer guide for building dApps on mobile

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Partner validation** | Minswap integration | Minswap dApp on mobile using cardano_flutter SDK, swap works | Partner audit |
| **Partner validation** | JPG Store integration | CNFT marketplace on mobile using SDK, listing creation works | Partner audit |
| **Swift SDK tests** | UniFFI bridging | Rust → Swift bindings auto-generated, Swift code compiles | Swift Agent |
| **Kotlin SDK tests** | UniFFI bridging | Rust → Kotlin bindings auto-generated, Kotlin code compiles | Kotlin Agent |
| **Documentation** | dApp developer guide | 5+ chapters, with working examples for common patterns | Docs Agent |

### Success Criteria
- ✅ At least 2 production dApps shipping with cardano_flutter SDK
- ✅ Swift SDK compiles and passes tests on macOS/iOS
- ✅ Kotlin SDK compiles and passes tests on Android
- ✅ Developer guide has ≥5 complete examples
- ✅ Community contributions accepted (2+ external PRs merged)

---

## Phase 5: Performance, Hardening & Desktop

**Dependency:** v1.0.0 stable + ecosystem adoption feedback

### Deliverables
- Web platform support (via WASM or js-interop; verify flutter_rust_bridge web support)
- macOS app support (Intel + Apple Silicon)
- Windows app support
- Performance optimization (batch UTXOs, caching, lazy loading)
- Comprehensive logging and metrics
- v1.1.0 release

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Platform tests** | Web support | Build and run example app as web target; verify TX submission works | Web Agent |
| **Platform tests** | macOS universal | Build on Intel Mac, test on Apple Silicon, verify binary runs on both | macOS Agent |
| **Platform tests** | Windows | Build on Windows, run example app, verify desktop UI renders | Windows Agent |
| **Performance tests** | UTXO fetch latency | Measure time to fetch 100+ UTXOs via Blockfrost; target <2 seconds | Perf Agent |
| **Performance tests** | Transaction build latency | Measure time to build complex TX (10+ inputs, 5+ outputs); target <500ms | Perf Agent |
| **Load tests** | Concurrent operations | Simulate 50 concurrent wallet balance fetches; no memory leaks | Load testing |

### Success Criteria
- ✅ Example app builds and runs on web, macOS, Windows
- ✅ UTXO fetch: <2 seconds for 100+ UTXOs
- ✅ TX build: <500ms for complex transactions
- ✅ No memory leaks under sustained load (1M+ operations)
- ✅ v1.1.0 published with performance improvements documented

---

## Phase 6: Advanced Wallet Features

**Dependency:** v1.1.0 stable + production feedback

### Deliverables
- HD wallet account management (derive multiple accounts per mnemonic)
- Staking pool delegation via SDK
- Governance participation (CIP-36 voting, SanchoNet integration)
- Ledger/Trezor hardware wallet support (via CIP-30 bridge)
- Seed phrase encryption/backup
- v1.2.0 release

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Unit tests** | HD account derivation | Derive 10 accounts from same mnemonic; verify paths match CIP-1852 | Test Agent |
| **Integration tests** | Staking delegation | Delegate to pool, verify on-chain | Test Agent |
| **Integration tests** | Governance voting | Cast vote on SanchoNet, verify participation | Test Agent |
| **Hardware wallet tests** | Ledger integration | Connect Ledger via CIP-30, sign TX, verify signature | Hardware Agent |
| **Acceptance tests** | Seed encryption | Encrypt seed phrase, decrypt, verify recovery | Coordinator |

### Success Criteria
- ✅ Multiple accounts derivable from single mnemonic
- ✅ Staking delegation works end-to-end
- ✅ Governance voting tested on SanchoNet
- ✅ Ledger/Trezor integration working (if CIP-30 bridge available)
- ✅ v1.2.0 published with stability improvements

---

## Phase 7: Maintenance, Documentation & Community (Ongoing)

**Ongoing:** Long-term support mode

### Deliverables
- Quarterly security audits (or reactive audits on major CSL upgrades)
- Community support (GitHub issues, Discord, forum)
- API stability guarantees (semver strict; v1.x = no breaking changes)
- Annual documentation refresh
- CI/CD pipeline with automated testing on all platforms
- CSL version compatibility matrix (published & maintained)

### Verification Strategy

| Verification Level | What | How | Owner |
|---|---|---|---|
| **Security audit** | Quarterly review | External audit or internal security checklist | Coordinator + Security Agent |
| **CSL compatibility** | Major version bumps | Test SDK against new CSL versions; document breaking changes | Test Agent |
| **Community adoption** | Third-party usage | Track GitHub stars, pub.dev downloads, Twitter mentions | Community Agent |
| **Documentation** | Annual refresh | Update guides, examples, add new community contributions | Docs Agent |
| **SLA tests** | API stability | Run phase 1–6 example apps monthly; flag any regressions | CI/CD Agent |

### Success Criteria
- ✅ Zero critical CVEs in production; any found fixed within 48 hours
- ✅ Quarterly security audits completed and documented
- ✅ Community contributions accepted (≥10 external PRs per quarter)
- ✅ Pub.dev shows ✅ all health indicators
- ✅ 1000+ GitHub stars by end of year 1
- ✅ Used in ≥5 production dApps or wallets

---

## Summary Roadmap (Untimed)

> **No fixed deadlines.** Phases ship when production-ready. Estimates below are realistic single-developer part-time projections, not commitments.

| Phase | Scope | Version | Estimate |
|---|---|---|---|
| **0** | FFI bootstrap, Android 16KB compat, CI green | v0.0.x | 2–4 weeks |
| **1** | Read-only wallet (HD derivation, address gen, Blockfrost client) | v0.1.0 | 4–8 weeks |
| **2** | Transaction building, signing, multi-asset, mainnet validation | v0.2.0 | 8–12 weeks |
| **3** | Plutus V2/V3, NFTs (CIP-25/68), reference inputs | v0.3.0 | 8–12 weeks |
| **4** | CIP-30 integration; CIP-45 via Vespr integration (not greenfield) | v1.0.0 | 6–10 weeks |
| **4.5** | Optional: Swift/Kotlin SDKs via UniFFI shared core | v1.0.x | 4–8 weeks |
| **5** | Web (JS interop to CML npm), desktop, performance | v1.1.0 | 6–10 weeks |
| **6** | Advanced: HD accounts, staking, governance, Ledger | v1.2.0 | 8–12 weeks |
| **7** | Maintenance: security audits, CSL/CML/Pallas migrations, community | v1.x+ | Ongoing |

**Realistic v1.0.0 estimate:** 10–18 months part-time, faster if dedicated full-time.

**Independent project — no Catalyst submission planned.** See `.claude/goals/INDEPENDENT_PROJECT_STRATEGY.md`.

---

## Definition of Done (v2.0.0 and Beyond)

By end of Phase 7, the SDK is **production-ready** when:

- ✅ All 8 phases (0–7) shipped and stable
- ✅ iOS, Android, web, macOS, Linux, Windows all passing CI
- ✅ Android 16KB page size verified on Play Store internal testing
- ✅ ≥80% test coverage on Dart; Rust inherits CML's coverage + wrapper-specific tests
- ✅ Backend swap proven: works with at least 2 of {CSL, CML, Pallas}
- ✅ Example app is a fully functional wallet (send, receive, stake, mint, vote, connect dApps)
- ✅ Published to pub.dev as `cardano_flutter_rs`, crates.io as `cardano_flutter_rs`
- ✅ Optional: Swift SDK published to CocoaPods (via UniFFI shared core)
- ✅ Optional: Kotlin SDK published to Maven (via UniFFI shared core)
- ✅ ≥1 production dApp or wallet using the SDK (≥5 is a stretch goal)
- ✅ Documentation site live with tutorials, API reference, cookbook
- ✅ Security: best-effort audits, responsible disclosure, no unpatched CVEs
- ✅ Community sustaining itself organically (external PRs land regularly)

---

**Last Updated:** 2026-05-24  
**Next Review:** After Phase 0 completion
