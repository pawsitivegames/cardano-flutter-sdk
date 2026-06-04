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
| 4.4 — CIP-45 mobile connector | ✅ **Live-verified 2026-06-02** (iOS) | v0.7.0 |
| 4.5 — Hardware wallets (Ledger) | 🟡 **Core done 2026-06-02**; on-device signing pending | v0.8.0 |
| 5+ | Planned | — |

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

### Phase 4.6 — Foundation hygiene → v0.8.1
*Dependency: none. Cheap, hardware-free, unblocks everything. Do first.*

**Deliverables:**
- **CI** (GitHub Actions): `cargo test` + `clippy -D warnings`, `flutter analyze`,
  `flutter test`, build iOS + macOS + web; status badge in README.
- **Metadata hygiene** (blocks any pub.dev publish): `dart/pubspec.yaml` version,
  `flutter_rust_bridge: =2.12.x` (pin — not `^2.0.0`), fix description ("CSL"
  backend, not "CML"), real `homepage`/`repository` (drop `YOUR_HANDLE`); same in
  `rust/Cargo.toml`.
- Mark hardware-wallet public API `@experimental`.

---

### Phase 5a — HD multi-account → v0.9.0
*Dependency: Phase 4.3. Pure Dart/Rust — verifiable on iPhone 13 + testnet.*

**Deliverables:**
- HD multi-account management (CIP-1852 account discovery; N accounts per seed)
- Address gap-limit scanning (BIP-44 gap=20) for used/unused discovery
- Example: "Accounts" screen (add/switch account, per-account balance)

**Verification:**
- Account derivation matches CIP-1852 vectors; Rust + Dart unit tests
- Testnet: derive account #1, receive, send — confirmed on-chain from the phone
- Note: gap scanning depends on the **provider's** address-history semantics +
  rate limits — test against Blockfrost with backoff.

---

### Phase 5b — Seed encryption & backup (security subsystem) → v0.9.1
*Dependency: Phase 5a. **Security-critical** — own phase, explicit design.*

**Deliverables:**
- **Rust-side** at-rest encryption: Argon2id KDF + XChaCha20-Poly1305 AEAD
  (`encrypt_seed` / `decrypt_seed` FFI; new crates `argon2`, `chacha20poly1305`).
- Key **zeroization** in Rust; integrate platform secure storage (iOS Keychain /
  Android Keystore) for the wrapping key where available.
- Written **threat model** (what it protects against; what it does not).

**Verification:**
- Encrypt → wipe → decrypt round-trip; wrong-password reject; tamper → AEAD-fail test
- KDF params documented + benchmarked on iPhone 13
- Security review of the at-rest format (see Phase 7 review, applied here too)

---

### Phase 6 — Web (scoped) & Desktop → v0.10.0
*Dependency: Phase 5b. Verifiable in a desktop browser + macOS — no phone needed.*

> Web ≠ a recompile. No Rust FFI on web → a **CML-JS backend** must implement the
> Dart API surface. Scope is deliberately reduced for the RC.

**Deliverables:**
- **Web backend spike first:** does CML-npm satisfy the existing CSL-shaped Dart
  API? Build a **CSL↔CML golden-CBOR conformance suite** (tx/value/witness/COSE).
  This must run *before* any API freeze (it may force API changes).
- Web (scoped): address derivation, balance/UTxO read, **CIP-30 connect** — *not*
  full tx-building (deferred to a later web-parity track).
- **macOS** plugin scaffolding: universal dylib (`lipo` arm64+x86_64), podspec
  framework embedding, entitlements (network client), codesign. (Linux/Windows:
  best-effort, CI-build only, no prebuilt artifacts.)
- Performance: UTXO fetch <2s, TX build <500ms; memory-leak check under load.

**Verification:**
- Golden-CBOR suite: native (CSL) and web (CML) agree byte-for-byte where required
- Scoped CIP-30 methods run in a desktop browser build
- **Cross-wallet check vs Lace/Eternl** — note this depends on the web backend
  existing first. Cheaper interop check available *today* with no web: confirm a
  real Lace/Eternl-signed message **verifies** under our native `verifyMessage`.
- macOS example app builds + runs a send tx on testnet

---

### Phase 7 — Governance, Security & Pre-1.0 Hardening → v0.11.0
*Dependency: Phase 6.*

**Deliverables:**
- Governance: CIP-36 catalyst/vote key registration (SanchoNet/testnet)
- **Security review pass** (pre-1.0, not post): secret handling, COSE/CIP-8
  correctness, fee/coin-selection edge cases, seed-at-rest format
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
- [ ] **Android emulator-verified**: app + FFI `.so` load + deep-link/QR + **16KB
      page-size image** all pass (labeled "emulator", not "device")
- [ ] >80% Dart coverage; Rust wrapper + crypto coverage; fuzz suite green
- [ ] Security review pass complete; no hardcoded secrets; clippy + analyze clean
- [ ] Pallas backend-swap feasibility demonstrated
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
