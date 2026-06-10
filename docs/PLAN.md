# Cardano Flutter SDK — Project Plan

> Single source of truth. Last updated: 2026-06-09.
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

**Long-term FFI boundary:** native platforms keep a small, stable Rust FFI surface for deterministic Cardano-critical work: address/key derivation, transaction body building, fee/size calculation, canonical CBOR serialization, signing/witness assembly, metadata/minting/staking builders, Plutus data encoding, seed crypto, and hardware-wallet transaction decomposition. Dart owns app flow, Flutter UI, provider REST calls, wallet state, secure-storage composition, deep links, Bluetooth/transport adapters, and CIP-30/CIP-45 orchestration. This boundary is deliberate: Rust protects correctness and backend swapability; Dart keeps product integration fast and platform-native. Do not expand FFI to generic network/app logic, and do not reimplement Cardano cryptography or canonical serialization in Dart.

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
| 4.4 — CIP-45 mobile connector | ✅ **Live-verified 2026-06-02** (iOS) | v0.7.0 |
| 4.5 — Hardware wallets (Ledger) | 🟡 **Core done 2026-06-02**; on-device signing pending | v0.8.0 |
| 4.6 — Foundation hygiene | ✅ **Complete 2026-06-04** | v0.8.1 |
| 5a — HD multi-account | ✅ **Live-verified 2026-06-04** (iPhone 13) | v0.9.0 |
| 5b — Seed encryption | ✅ **Live-verified 2026-06-06** (iPhone 13: Keychain round-trip + `benchmark_kdf` ~158 ms) | v0.9.1 |
| 6 — Web (scoped) & Desktop | ✅ **Verified 2026-06-06** (conformance 32/32 + scoped `WebCip30Wallet` + macOS send-tx on-chain + perf within budget); only cross-wallet capture (Lace/Eternl) outstanding | v0.10.0 |
| 7+ | Planned | — |

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

**Follow-ups shipped (2026-06-03, code-complete; device verify pending):**
- Android `web+cardano://` `<intent-filter>` (singleTop `MainActivity` + `app_links`) ✅
- In-wallet QR scanning of the connection URI (`mobile_scanner` + `qr_scanner_page.dart`,
  camera permissions for both platforms) ✅ **verified on iPhone 13 (2026-06-03):
  scan dApp QR → parse → CIP-45 connect → API handshake**
- `WebrtcCip45Transport` — native (no-WebView) `flutter_webrtc` transport scaffold:
  WebRTC negotiation + data-channel RPC implemented; bugout-compatibility seams
  (`Cip45SignalingChannel` = WebTorrent tracker, `Cip45RpcCodec` = NaCl/bencode)
  documented but not implemented 🟡 (see `docs/cip45-transport.md`)

**Pending (needs live two-peer run on a device — see `docs/cip45-testing.md`):**
- dApp page ↔ wallet connect over public trackers, RPC round-trip, signData/signTx
- Android-device run of the deep link + QR flow (iOS already live-verified)
- A Dart WebTorrent tracker client + bugout framing to make the native WebRTC
  transport talk to real bugout.js dApps

---

### Phase 4.5 — Hardware Wallets → v0.8.0 (core) → v1.1.0 (verified)
*Dependency: Phase 4.3 complete. Can parallel with 4.4.*

**Deliverables:**
- ✅ Core (device-agnostic, tested): `xpubToAccount`, `assembleVkeyWitnessSet` /
  `extractVkeyWitnesses`, `HardwareWallet` interface, `HardwareCip30Wallet`.
- ✅ Ledger BLE adapter + screen (example): scan/connect, account xpub, address +
  balance/UTxO read path. (Vespr's MIT `ledger_cardano_plus`/`ledger_flutter_plus`.)
- ✅ Ledger transaction signing — implemented (Rust `xpubDerivePublicKey` +
  `decomposeTxBody`; example maps body → `ParsedSigningRequest`, re-derives witness
  pubkeys, assembles a submittable tx). Code-complete.
- ⏸️ Trezor signing — **deferred** (USB-only/no BLE; Trezor Connect impractical on mobile).
- 🅱️ Physical device verification — **moved to Track B (Phase H1); blocked on hardware**.

**Verification:**
- 🅱️ Ledger TX signing round-trip on device — **deferred to Track B / Phase H1**.
  The honesty rule stands: no "verified on device" claim until it runs on real
  hardware (see `docs/hardware-wallets.md` → on-device checklist).
- The public hardware-wallet API ships **`@experimental`** (loud dartdoc warning;
  `signTransaction` unverified on hardware) for the entire 0.x and 1.0.x line, and
  is promoted to stable only in v1.1.0 once an on-device round-trip passes.

> Honesty note: the core protocol layer is complete and unit-tested (incl. a
> real-crypto byte-identical assemble round-trip) and the Ledger signing path is
> implemented end-to-end in code. Only the *on-hardware* round-trip is outstanding.
> See the restructure below for how this affects versioning (it does **not** gate
> the feature-complete RC, but it **does** gate the bare `1.0.0` tag).

---

## Roadmap restructure v2 (2026-06-03, post critic review) — two tracks

We have no Android phone and no spare Ledger (the maintainer's Ledger holds a live
main account and must not be used for testing). The original plan gated **v1.0.0 on
Ledger device verification** and made Phases 5–6 depend on v1.0 — a hardware
deadlock. A first restructure split the work into tracks but was reviewed by three
adversarial critics; this **v2** incorporates their findings. Key corrections vs v1:

1. **Don't brand the hardware-unverified build `1.0.0`.** It ships as **`0.12.0`
   (feature-complete RC)**. The bare **`1.0.0`** tag is reserved until **Android is
   verified at least on an emulator (incl. the 16KB-page-size image)** — Android is
   a *platform* (~70% of mobile), not an optional peripheral, so a "production"
   claim cannot skip it. Hardware wallets (Ledger) *are* a peripheral and stay a
   v1.1 fast-follow.
2. **Android emulator counts as partial verification — labeled precisely.** A Mac
   AVD verifies the app build, **Rust `.so` FFI load**, deep-link/QR flow, and
   **16KB page-size compatibility** (Google ships a dedicated 16KB emulator image —
   their recommended test path). It does **not** replace a physical-device + Play
   Store check. We write "verified on Android emulator," never "verified on device."
3. **Web is a second backend, not a checkbox.** Web has no Rust FFI (Rust→WASM is
   banned) so it needs the crypto/tx/COSE/Plutus surface reimplemented against
   **CML JS**. It is **scoped down** to a read-only + CIP-30-connect subset for the
   RC, gated on a CSL↔CML golden-CBOR conformance suite. Full web tx-building is a
   later track, *not* a 1.0 gate.
4. **Seed encryption is a security subsystem** — its own phase, **Rust-side**
   Argon2id + XChaCha20-Poly1305 (new FFI surface), threat model, secure-storage
   (Keychain/Keystore), zeroization, + a security review. No hand-rolled Dart crypto.
5. **CI + metadata hygiene move to the front** (cheap, hardware-free, unblock
   everything). Security review moves *pre*-1.0. "Backend swap" specifically means a
   **Pallas** evaluation (addresses the CSL-legacy strategic risk before API freeze).
6. **Track B = genuinely device-blocked only.** The native-WebRTC bugout framing
   (unbuilt Dart WebTorrent client + NaCl/bencode) is *unbuilt implementation*, part
   of it hardware-free, so it lives in an explicit research bucket — not "parked
   verification."

---

## Track A — Active (no Ledger; Android via emulator only)

### Phase 4.6 — Foundation hygiene → v0.8.1  ✅ complete (2026-06-04)
*Dependency: none. Cheap, hardware-free, unblocks everything. Do first.*

**Deliverables:**
- ✅ **CI** (GitHub Actions `ci.yml`): `cargo test` + `clippy -D warnings` +
  `cargo fmt --check`, `flutter analyze`, `flutter test`, build iOS + macOS +
  Android; gating summary job; **status badge in README**. *(Web build deferred to
  Phase 6 — no web backend exists yet; macOS/Android jobs are informational until
  their scaffolding/device verification lands, same pattern.)*
- ✅ **Metadata hygiene**: `dart/pubspec.yaml` version `0.9.0`,
  `flutter_rust_bridge: 2.12.0` (pinned), description fixed to "CSL", real
  `homepage`/`repository` (no `YOUR_HANDLE`); `rust/Cargo.toml` version bumped
  `0.1.0` → `0.9.0`, CSL description, `flutter_rust_bridge = "=2.12.0"`.
- ✅ Hardware-wallet public API marked `@experimental` (3 sites).
- ✅ README de-staled: badge added, status line updated to v0.9.0, broken
  `docs/project-plan.md` links fixed → `docs/PLAN.md`.

---

### Phase 5a — HD multi-account → v0.9.0  ✅ complete & live-verified (iPhone 13)
*Dependency: Phase 4.3. Pure Dart/Rust — verifiable on iPhone 13 + testnet.*

**Deliverables:**
- ✅ HD multi-account discovery (CIP-1852; stops at first empty account, gap=1)
- ✅ Address gap-limit scanning (`HdWalletDiscovery`, default BIP-44 gap=20)
- ✅ Rust `deriveAddress` (base address + payment key hash per role/index)
- ✅ Blockfrost `fetchAddressMetadata` / `isAddressUsed` (`/addresses/{addr}/total`)
- ✅ Example: "Accounts" screen (discover, used count, next receive, balance)

**Verification:**
- ✅ Account derivation matches CIP-1852 (account-0 ext-0 hash + base address
  identical to the CIP-30 path); Rust 108 · Dart 155; clippy/fmt/analyze clean
- ✅ Gap-limit + account-gap logic unit-tested with a deterministic fake lookup
  over real FFI-derived addresses
- ✅ **Live-verified on iPhone 13 (2026-06-04):** discovered account 0 (Active,
  ~36,092 ₳) via real Blockfrost `/addresses/{addr}/total` queries — external 6
  scanned (1 used at idx 0 + gap-limit 5 unused), change 5 scanned, stopped at the
  first empty account (account 1). Next-receive = first unused external (idx 1).

---

### Phase 5b — Seed encryption & backup (security subsystem) → v0.9.1  ✅ live-verified (iPhone 13, 2026-06-06)
*Dependency: Phase 5a. **Security-critical** — own phase, explicit design.*
*Design + threat model: `docs/seed-encryption.md`.*

**Deliverables:**
- ✅ **Rust-side** at-rest encryption (`rust/src/seed.rs`): Argon2id KDF +
  XChaCha20-Poly1305 AEAD. FFI: `encrypt_seed`, `encrypt_seed_with_params`,
  `decrypt_seed`, `benchmark_kdf`, `default_kdf_params`. Self-describing,
  versioned `CFS1` container (hex); KDF params embedded + AAD-bound (downgrade-
  resistant). Crates: `argon2`, `chacha20poly1305`, `zeroize`.
- ✅ Key **zeroization** in Rust (derived key + plaintext via `Zeroizing`).
- ✅ Platform secure storage **integrated in the example** (`seed_vault_screen.dart`,
  `flutter_secure_storage`): random wrapping secret in Keychain/Keystore composed
  with the user password (input composition only — crypto stays in Rust), so an
  exfiltrated blob is useless without the device. Core SDK stays dependency-lean.
- ✅ Written **threat model** (`docs/seed-encryption.md`) — in/out of scope stated.

**Verification:**
- ✅ Encrypt → drop key → decrypt round-trip; wrong-password reject; tamper (ct +
  KDF-param) → AEAD fail; distinct salt/nonce per call; bad-magic/non-hex reject.
  Rust **119/119** (+11 seed), Dart **167/167** (+12 seed); clippy/fmt/analyze clean.
- ✅ KDF default params documented + benchmarked on dev hardware (~101 ms @ 64 MiB/t=3).
- ✅ **Live-verified on iPhone 13 (2026-06-06):** Seed Vault screen ran the full
  hardware-backed round-trip — encrypt → `CFS1` blob (145 bytes) written to the
  iOS Keychain → read back → decrypt → exact secret recovery ("Unlocked ✓").
  On-device `benchmark_kdf` = **~158 ms** @ 64 MiB/t=3/p=1 (the seed FFI symbols
  execute on real arm64). Comfortable one-time unlock latency; defaults unchanged.
- ⏳ Security review of the at-rest format folded into the Phase 7 review pass.

---

### Phase 6 — Web (scoped) & Desktop → v0.10.0  ✅ verified 2026-06-06 (cross-wallet capture outstanding)
*Dependency: Phase 5b. Verifiable in a desktop browser + macOS — no phone needed.*

> Web ≠ a recompile. No Rust FFI on web → a **CML-JS backend** must implement the
> Dart API surface. Scope is deliberately reduced for the RC.
> Full design: `docs/web-backend.md`.

**Deliverables:**
- ✅ **Web backend spike + CSL↔CML golden-CBOR conformance suite** — the contract
  both backends must satisfy byte-for-byte, shipped *in the package* so it runs
  in-browser against CML, not just in CI. `dart/lib/src/conformance/conformance.dart`
  (`ConformanceBackend` interface, `runConformanceCase` dispatcher,
  `NativeConformanceBackend`), 32 frozen golden vectors
  (`test/conformance/golden_cbor.json`) across address/value/plutus/witness/COSE,
  CI gate (`test/conformance_test.dart`), generator (`generate_golden.dart`).
- ✅ **CML-JS web backend scaffold** (`cml_web_backend.dart`): `dart:js_interop`
  bindings to `@dcspark/cardano-multiplatform-lib-browser` + `CmlWebBackend`.
  **Browser-verify pending** — unmapped ops throw (fail loud, not silent). Not
  exported from the barrel so native builds never link `dart:js_interop`.
- ✅ Web (scoped): address derivation, balance/UTxO read, **CIP-30 connect +
  signData** — *not* full tx-building (deferred to a later web-parity track).
  Shipped as a second package entrypoint `cardano_flutter_rs_web.dart` exposing
  `WebCip30Wallet` (CML-JS + Blockfrost REST); every scoped op mapped. Example
  runs as a web build (`example/lib/main_web.dart` + `example/web/`).
- ✅ **macOS** plugin scaffolding (universal dylib + podspec + entitlements +
  codesign) — done & verified (`docs/macos-packaging.md`); `macos-build` is a
  hard CI gate (framework rebuild → release build → in-`.app` integration test).
- ✅ Performance (2026-06-06, macOS + live testnet preview, real FFI):
  UTxO fetch **53 ms** (budget <2 s); coin-selection + tx-build over 20 runs
  **median 0 ms / avg 1 ms / max 12 ms** (budget <500 ms); no latency growth
  across runs (leak smoke check). Gated by `integration_test/perf_benchmark_test.dart`.

**Verification:**
- ✅ Golden-CBOR suite: native (CSL) reproduces all **32** vectors byte-for-byte
  (added non-base address types + nested Plutus); COSE `signData` vectors verify
  under native `verifyData`. analyze clean. Frozen contract a web backend must meet.
- ✅ `CmlWebBackend` passes the **full 32/32** golden suite in a real (headless
  Chromium) browser — `tool/web_conformance/`, wired as the `web-conformance` CI gate.
- ✅ Scoped CIP-30 runs in a desktop browser build — `WebCip30Wallet` derivation +
  `signData`→`verifyData` gated in-browser against native golden values
  (`web_wallet_harness.dart`, PASS 10), wired into CI.
- 🅱️ **Cross-wallet check vs Lace/Eternl** — verify harness + fixture + capture
  guide in place (`docs/cross-wallet-verify.md`); **awaiting a captured real
  signature** (only remaining manual step, no web/hardware needed).
- ✅ macOS example **send-tx on testnet preview** (2026-06-06): built → signed →
  submitted → **confirmed on-chain** (tx `30c4b6e0…d13702`, block 4355766, fee
  181253). Surfaced + fixed a real bug: native tokens on the spent UTxO were
  dropped (→ node `ValueNotConserved`); the send now routes them through
  `utxosToTxInputs` so change carries the assets (NFT `TestNFT1`×2 conserved).
  Gated by `integration_test/send_flow_test.dart` (live when `BLOCKFROST_PROJECT_ID` set).

---

### Phase 7 — Governance, Security & Pre-1.0 Hardening → v0.11.0
*Dependency: Phase 6.*

**Deliverables:**
- Governance: CIP-36 catalyst/vote key registration (SanchoNet/testnet)
- ✅ **Security review pass** (pre-1.0) — done 2026-06-06, `docs/security-review-phase7.md`.
  Audited secret handling, COSE/CIP-8, fee/coin-selection/tx-building, seed-at-rest;
  no critical issues; 9 findings fixed (notably TX-1 double-change → re-verified
  on-chain, SEED-1 KDF-DoS clamp, COSE alg/empty-payload strictness, legacy
  `message.rs` deprecated). 1 owner action: **rotate the Blockfrost dev key**.
- **Pallas backend evaluation** (the "backend swap" deliverable is specifically
  CSL→Pallas feasibility — addresses CSL going legacy before the API freeze)
- Fuzz/property tests on CBOR (de)serialization + witness assemble/extract
- Documentation site live; API stability pass (semver freeze candidates)
- >80% Dart coverage

---

### v0.12.0 — Feature-complete RC (iOS verified · macOS · Web scoped · Android emulator)
*Gate: Track A 4.6–7 done. **NOT gated on Ledger or physical Android hardware.***

Definition of Done (`0.12.0` RC):
- [ ] Phases 0–4 (minus hardware verification) + Track A 4.6/5a/5b/6/7 complete
- [ ] iOS passing CI + live-verified; macOS functional; Web (scoped) functional
- [ ] Web scoped subset via Dart JS interop → CML (no WASM tunnel); golden-CBOR parity
- [x] **Android ARM64 emulator-verified** (2026-06-09): app + FFI `.so` load +
      SDK smoke test + deep-link/QR entry + **16KB page-size image** all pass
      (`pageSizeCompat=0`; labeled "emulator", not "device"). Broader Android
      ABI policy remains pending; current example APK is ARM64-only.
- [x] >80% hand-written Dart coverage; Rust wrapper + crypto coverage; fuzz suite green
      (2026-06-10: `flutter test --coverage` PASS; LCOV hand-written Dart
      coverage 80.06% / 558 of 697 lines, excluding generated FRB/Rust twins
      and `error.freezed.dart`; Rust `cargo test`/clippy + CBOR property tests
      green in `32610ab`).
- [ ] Security review pass complete; no hardcoded secrets; clippy + analyze clean
- [x] Pallas backend-swap feasibility demonstrated (2026-06-09):
      `docs/pallas-feasibility.md`; conclusion is feature-gated conformance
      backend first, not a production backend flip.
- [ ] Hardware-wallet API marked `@experimental`; Android marked **supported
      (emulator-verified)** in platform table
- [ ] Published to pub.dev as `cardano_flutter_rs` (0.12.0 / `1.0.0-rc.1`)
- [ ] Documentation site live; README platform-support matrix

### v1.0.0 — Production release
*Gate: 0.12.0 RC + **Android verified on a physical device** (incl. Play Store
build acceptance). A used Pixel (~$150) is the cheap unblock — lower bar than a
Ledger. Hardware-wallet (Ledger) support remains `@experimental` until v1.1.0.*

> Note: "a real third-party dApp using the SDK in production" is a post-1.0 adoption
> goal, not a gate (not on our timeline). The in-our-control external-interop signal
> is the Lace/Eternl cross-wallet check in Phase 6 — keep it in the RC gate.

---

## Complete SDK Backlog

These are the remaining workstreams required before the SDK should be considered
complete in the broader sense: a Flutter developer can build a production wallet,
dApp connector, staking/native-asset app, or advanced transaction workflow without
dropping into Rust, CSL/CML, or custom Cardano plumbing.

Priority order:

1. **Android production verification**
   - Physical-device verification on a real Android phone.
   - Play Store build acceptance, including 16 KB page-size compliance.
   - Final ABI policy: arm64, x86_64 emulator, and whether to support armeabi-v7a.

2. **Provider abstraction beyond Blockfrost**
   - Keep Blockfrost as the default provider.
   - Add Maestro and Koios providers.
   - Define a common provider interface for UTxOs, protocol parameters, submit,
     transaction status, account history, and address metadata.
   - Normalize retries, rate limits, pagination, and provider-specific errors.

3. **Full wallet account model**
   - Multi-account discovery and account selection.
   - Address gap scanning and change-address management.
   - UTxO cache with explicit refresh/invalidation.
   - Balance aggregation for ADA and native assets.
   - Transaction-history helpers suitable for wallet UI.

4. **Production transaction-builder coverage**
   - ADA send and multi-asset send.
   - Metadata-only transactions.
   - Native token mint/burn.
   - Staking certificates, delegation, deregistration, and reward withdrawals.
   - Collateral, reference inputs, inline datums, redeemers, and Plutus scripts.
   - Governance/voting support when the upstream libraries and network flows are stable.

5. **dApp connector maturity**
   - Stable CIP-30 wallet API surface.
   - CIP-45 mobile connector with a mature native transport path.
   - Permission, session, and origin/app-identity management.
   - Human-readable signing prompts for `signData` and `signTx`.

6. **Hardware-wallet completion**
   - Ledger transaction signing verified on real hardware.
   - Explicit supported transaction subset.
   - Safe refusal for unsupported transaction shapes.
   - Promote hardware-wallet APIs out of `@experimental` only after real-device
     signing passes.

7. **Web parity decision**
   - Decide whether web remains a scoped wallet-lite backend or grows toward full
     transaction building/signing parity.
   - Keep CML-JS and native CSL/Pallas byte parity enforced by golden-CBOR conformance.

8. **Security hardening**
   - Keep seed-encryption threat model current.
   - Complete recurring security reviews before stable releases.
   - Remove or rotate any hardcoded development secrets before publication.
   - Provide secure-storage examples for iOS, Android, and macOS.
   - Preserve zeroization where practical.
   - Expand fuzz/property tests around serialization-sensitive code.

9. **Backend swap strategy**
   - Keep CSL as the active backend until a replacement is proven.
   - Maintain real trait boundaries for CML/Pallas migration.
   - Use golden-CBOR conformance to protect Dart API behavior from backend churn.

10. **Developer experience**
    - Example flows for every major capability.
    - API docs with copy-paste snippets.
    - Actionable error types and troubleshooting notes.
    - Migration guides for breaking changes.
    - CI matrix for Rust, Flutter, iOS, Android, web, and macOS.

---

## Track B — Hardware-gated (parked until physical devices available)

### Phase H1 — Ledger on-device verification → v1.1.0
*Blocked on: a spare Ledger (Nano S Plus ≈ $80 — do NOT use the maintainer's
main-account device).*
- Verify TX signing round-trip on device (checklist: `docs/hardware-wallets.md`)
- `decompose_tx_body` currently models **simple payments only** (certs/withdrawals/
  mint/collateral/ref-inputs/votes are flagged unsupported), so expect on-hardware
  work beyond the likely `alonzo`↔`babbage` output-format fix: full 5-segment BIP-32
  paths, datum/script-ref outputs.
- Promote the hardware-wallet API from `@experimental` to stable; publish in v1.1.0.

### Phase H2 — Android physical-device verification → v1.1.0
*Blocked on: a physical Android phone (Pixel 8a recommended).*
- Deep link + QR connect flow on a real device (emulator already covers functional)
- **Play Store build acceptance** (16KB already emulator-checked in the RC)
- Real-device perf + OEM BLE behavior

### Research bucket (not device-blocked) — native CIP-45 WebRTC transport
*Not "verification" — unbuilt implementation. Mostly hardware-free; pursue
independently of Track B if/when desired.*
- A Dart **WebTorrent WSS tracker client** (none exists on pub.dev — multi-week,
  standalone networking project).
- **bugout framing**: bencode + NaCl (ed25519 sign / box encrypt) `BugoutCip45RpcCodec`
  byte-matching bugout.js, for the documented `Cip45SignalingChannel` / `Cip45RpcCodec`
  seams. Only then can a desktop browser act as the second peer.
- Until then, `BugoutCip45Transport` (WebView, already live-verified) remains the
  only supported CIP-45 path.

### v1.1.0 — Hardware-verified release
*Gate: H1 + H2 done.* Ledger signing + Android verified on real devices; changelog
notes the hardware coverage now closed.

---

### Phase 8 — Maintenance (Ongoing)
- Quarterly security audits
- CSL/CML/Pallas version compatibility matrix
- Community contributions + PR reviews
- API stability guarantees (semver strict, v1.x = no breaking changes)

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
| FFI boundary | Rust for deterministic Cardano bytes/signing/crypto; Dart for product, REST, and platform flow | Long-term correctness, smaller API surface, and backend swapability |
| iOS binary | Dynamic framework | `dart/ios/Libs/cardano_flutter_rs.framework` |
| Web strategy | Dart JS interop → CML npm | No Rust→WASM tunnel |
| Funding | Independent, self-funded | No Catalyst; quality over speed |
| Android NDK | r28.2.13676358+ | 16KB page size mandatory since Nov 2025 |

---

## Risks

- **flutter_rust_bridge moves fast** — pin exact 2.x version; budget 1–2 days/quarter for upgrades
- **CSL slowing, Pallas rising** — Whisky V2 migrated CSL→Pallas; evaluate before v1.0
- **Vespr is the real competitor** — differentiate on correctness + tx-building, not speed
- **Scope creep** — CSL/CML have ~500 exported types; wrap only what the example app needs
- **Android 16KB mandatory** — ARM64 emulator pass is complete; still verify on
  Pixel 8a before any Play Store submission and settle non-ARM64 ABI support.
