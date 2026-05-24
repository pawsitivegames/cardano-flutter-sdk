---
title: Phase 0 — Foundation Setup & FFI Bootstrap
status: ready-to-start
created: 2026-05-24
blocks: phase-1
---

# Goal: Phase 0 — Foundation Setup & FFI Bootstrap

Establish a solid, multi-platform-ready FFI foundation before any feature work begins. Phase 0 is intentionally narrow and rigorous — getting this right prevents weeks of pain later.

## Why Phase 0 Exists

The original plan started directly at Phase 1 ("read-only wallet"). Critical review found this skipped real risks:

1. **flutter_rust_bridge codegen + multi-platform CI** is non-trivial (2–4 weeks alone)
2. **Android 16KB page size compatibility** is mandatory for Play Store since November 2025 — must be verified early
3. **iOS staticlib + Android NDK + universal binaries** have setup-time gotchas
4. **Backend trait pattern** (CML/CSL/Pallas swap) is easier to design before code exists than to retrofit

Phase 0 de-risks all of these before Phase 1 begins.

## Success Criteria

The following must ship together before Phase 0 closes:

### 1. Toolchain & Scaffold
- ✅ Rust stable (edition 2021), `cargo` working
- ✅ Flutter ≥3.19.0, Dart ≥3.3.0
- ✅ Android NDK r28+, AGP 8.7.3+ installed
- ✅ flutter_rust_bridge_codegen v2.12+ installed and working
- ✅ `rust/cardano_flutter_rs` crate scaffolded
- ✅ `dart/cardano_flutter_rs` package scaffolded
- ✅ `example/` Flutter app exists and depends on local Dart package via path

### 2. Hello-World Function
- ✅ Rust function: `pub fn sdk_version() -> String` returning "cardano_flutter_rs v0.1.0 (CML vX.Y.Z)"
- ✅ Rust function: `pub fn is_valid_bech32(addr: String) -> bool` using CML
- ✅ `flutter_rust_bridge_codegen generate` produces `bridge_generated.dart`
- ✅ Example app calls both functions from a button; displays results

### 3. Backend Trait Architecture
- ✅ Rust crate has feature flags: `backend-cml` (default), `backend-csl`, `backend-pallas`
- ✅ `pub trait CardanoBackend` defined with minimal interface
- ✅ CML implementation of trait is wired up
- ✅ Trait abstracts at least 2 operations (e.g., `validate_address`, `parse_address`)

### 4. Platform Coverage
- ✅ Example app builds and runs on **iOS simulator** (Apple Silicon or Intel Mac)
- ✅ Example app builds and runs on **Android emulator** (API 34+, 16KB page size)
- ✅ Tested on at least one **physical Android device with 16KB page size** (Pixel 8a or similar)
- ✅ Universal binary works on iOS (lipo arm64 + x86_64 simulator)

### 5. CI Matrix
- ✅ `.github/workflows/ci.yml` runs on push to main + PRs
- ✅ Matrix: macOS, Ubuntu, Windows runners
- ✅ Per-runner: `cargo test`, `cargo clippy --all-targets -- -D warnings`, `flutter test`, `flutter analyze`
- ✅ Best-effort: iOS simulator + Android emulator integration test (may be macOS-only)
- ✅ All green on main

### 6. Open-Source Foundation
- ✅ LICENSE (MIT) in place
- ✅ CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, MAINTAINERS.md committed
- ✅ Issue + PR templates in `.github/`
- ✅ README explains the project, quick start, and architecture
- ✅ Branch protection on `main`: require CI pass + ≥1 review

## Verification Strategy

| Verification | What | How | Owner |
|---|---|---|---|
| **Build** | flutter_rust_bridge codegen | `flutter_rust_bridge_codegen generate` produces valid Dart | Self |
| **Build** | Rust crate | `cargo build` succeeds with default features | Self |
| **Build** | iOS staticlib | `cargo build --target aarch64-apple-ios --release` | Self |
| **Build** | Android NDK | `cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 build --release` | Self |
| **Run** | iOS simulator | `cd example && flutter run -d <ios-sim>` launches; button works | Self |
| **Run** | Android emulator | `cd example && flutter run -d <android-emu>` launches; button works | Self |
| **Run** | 16KB device | Sideload to Pixel 8a; app runs without crash | Self |
| **Run** | Play Store internal | Upload AAB to internal testing track; passes 16KB validation | Self |
| **CI** | Multi-platform | All GitHub Actions matrix jobs pass on main | CI |
| **Lint** | Rust | `cargo clippy --all-targets -- -D warnings` | CI + Self |
| **Lint** | Dart | `flutter analyze` no warnings | CI + Self |
| **Lint** | Format | `cargo fmt --check && dart format --set-exit-if-changed .` | CI + Self |

## Out of Scope for Phase 0

Things deliberately NOT included in Phase 0 (they belong in Phase 1+):

- ❌ HD wallet derivation (CIP-1852) — Phase 1
- ❌ Address generation beyond `is_valid_bech32` — Phase 1
- ❌ Blockfrost API client — Phase 1
- ❌ Transaction building — Phase 2
- ❌ Plutus / smart contracts — Phase 3
- ❌ CIP-30 / CIP-45 — Phase 4
- ❌ Web platform support — Phase 5 (Phase 0 is iOS + Android only)
- ❌ Desktop platforms — Phase 5

**Why this scope is small:** Phase 0 is a foundation. Don't over-deliver here.

## Estimated Time

**2–4 weeks of focused work** (single developer). Longer if learning Rust+Flutter FFI from scratch.

Note: this is an estimate, not a deadline. Independent project — no rush.

## Reference Projects to Study

- **[StadiaMaps/ferrostar](https://github.com/stadiamaps/ferrostar)** — Production cross-platform Rust+Flutter setup; navigation SDK
- **[TokeoPay/CardanoKit](https://github.com/TokeoPay/CardanoKit)** — Same architecture pattern (Rust+CSL via FFI, Swift)
- **[fzyzcjy/flutter_rust_bridge quickstart](https://cjycode.com/flutter_rust_bridge/quickstart)** — Official guide

## Coordination

Optional outreach during Phase 0 (no rush):

- **TokeoPay (CardanoKit team)** — Propose extracting a shared `cardano_core` Rust crate so Swift (UniFFI) and Dart (frb) share the same wrapper. Reduces duplicate work for both projects. Useful when Phase 0 is ~50% complete with concrete proposal in hand.
- **Vespr Wallet (Alex Dochioiu)** — Acknowledge their pure-Dart SDK exists; clarify positioning as complementary (we do CSL/CML/FFI correctness; they do CIP-30/WalletConnect). No collaboration required, but courtesy outreach reduces ecosystem friction.

## Phase 0 Exit Checklist

When all six success-criteria sections are ✅:

1. Tag repo as `v0.0.1-foundation`
2. Update CLAUDE.md "Current state" to reflect Phase 0 completion
3. Update root README with installation/build instructions
4. Optional: push to GitHub publicly (no pub.dev publish yet — that's Phase 1 exit)
5. Begin Phase 1 (see `.claude/goals/phase-1.md`)

---

**Created:** 2026-05-24  
**Status:** Ready to start when you are. No deadline pressure.
