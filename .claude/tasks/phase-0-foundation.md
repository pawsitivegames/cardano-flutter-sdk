# Task: Phase 0 — Foundation Setup & FFI Bootstrap

**Goal:** Ship the FFI foundation with working hello-world on iOS + Android, Android 16KB page size verified, CI green.

**Estimated duration:** 2–4 weeks of focused work  
**Owner:** Solo developer (or distributed across agents per `.claude/COORDINATOR_GUIDE.md`)  
**Blocked by:** None  
**Unblocks:** Phase 1

---

## Milestone 0.1: Toolchain & Scaffold (Day 1–3)

### Tasks

- [ ] Install Rust stable: `rustup default stable && rustup update`
- [ ] Add iOS targets: `rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim`
- [ ] Add Android targets: `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`
- [ ] Install `cargo-ndk`: `cargo install cargo-ndk`
- [ ] Install `flutter_rust_bridge_codegen`: `cargo install flutter_rust_bridge_codegen --locked --version ^2.12`
- [ ] Verify Flutter ≥3.19.0: `flutter --version`
- [ ] Verify Dart ≥3.3.0: `dart --version`
- [ ] Install Android NDK r28+ via Android Studio SDK Manager
- [ ] Verify NDK version: should be `28.x` or higher
- [ ] Verify AGP 8.7.3+ in `android/build.gradle` of example app

### Scaffold

- [ ] Create `rust/cardano_flutter_rs/` directory
- [ ] Run `cargo init --lib` inside it
- [ ] Edit `rust/cardano_flutter_rs/Cargo.toml`:
  - Set `name = "cardano_flutter_rs"`, `edition = "2021"`, `license = "MIT"`
  - Add `[lib] crate-type = ["cdylib", "staticlib"]`
  - Add feature flags: `backend-cml` (default), `backend-csl`, `backend-pallas`
  - Add dependencies: `flutter_rust_bridge = "2.12"`, `thiserror`, `anyhow`
- [ ] Create `dart/` Flutter package:
  - `flutter create --template=plugin --platforms=ios,android dart`
  - Rename package to `cardano_flutter_rs` in `pubspec.yaml`
- [ ] Create `example/` Flutter app:
  - `cd example && flutter create .`
  - Add path dependency: `cardano_flutter_rs: { path: ../dart }`
- [ ] Wire flutter_rust_bridge: `flutter_rust_bridge_codegen create --rust-root rust/cardano_flutter_rs --dart-root dart`
- [ ] Verify scaffold builds: `cd rust/cardano_flutter_rs && cargo build`
- [ ] Verify Dart resolves: `cd dart && flutter pub get`
- [ ] Verify example app builds: `cd example && flutter build apk --debug`

---

## Milestone 0.2: Hello-World End-to-End (Day 4–7)

### Rust Implementation

- [ ] In `rust/cardano_flutter_rs/Cargo.toml`, add CML dependency:
  ```toml
  cardano-multiplatform-lib = { version = "6.2", optional = true }
  ```
- [ ] In `rust/cardano_flutter_rs/src/lib.rs`, write:
  ```rust
  use flutter_rust_bridge::frb;
  
  /// SDK version including backend
  #[frb(sync)]
  pub fn sdk_version() -> String {
      format!("cardano_flutter_rs v{} (backend: {})",
          env!("CARGO_PKG_VERSION"),
          backend_name())
  }
  
  /// Validate a Bech32 address using current backend
  pub fn is_valid_bech32(addr: String) -> bool {
      // Backend-trait dispatch goes here
      crate::backend::current().validate_address(&addr).is_ok()
  }
  ```
- [ ] Create `rust/cardano_flutter_rs/src/backend/mod.rs`:
  ```rust
  pub trait CardanoBackend {
      fn validate_address(&self, addr: &str) -> Result<(), String>;
      fn name(&self) -> &'static str;
  }
  
  #[cfg(feature = "backend-cml")]
  pub mod cml;
  
  pub fn current() -> Box<dyn CardanoBackend> {
      #[cfg(feature = "backend-cml")]
      return Box::new(cml::CmlBackend);
      // ... other backends gated by features
  }
  ```
- [ ] Create `rust/cardano_flutter_rs/src/backend/cml.rs` with `CmlBackend` impl
- [ ] Verify `cargo build` succeeds
- [ ] Verify `cargo clippy --all-targets -- -D warnings` succeeds

### Dart Bindings

- [ ] Run `flutter_rust_bridge_codegen generate` from project root
- [ ] Verify `dart/lib/src/bridge_generated.dart` exists and compiles
- [ ] Create `dart/lib/cardano_flutter_rs.dart` that re-exports public API
- [ ] Write a type-safe wrapper for `isValidBech32` with dartdoc + example

### Example App

- [ ] Edit `example/lib/main.dart`:
  - Show "SDK Version: ..." (calls `sdkVersion()`)
  - Show a TextField for address input
  - Show a button "Validate"
  - Show result Text widget
- [ ] Run on iOS simulator: `cd example && flutter run -d <ios-sim>`
- [ ] Verify: tapping Validate with `"addr1q..."` returns `true`; with `"invalid"` returns `false`
- [ ] Run on Android emulator: `cd example && flutter run -d <android-emu>`
- [ ] Verify same behavior

---

## Milestone 0.3: Android 16KB Page Size (Day 8–10)

### Setup

- [ ] In `example/android/build.gradle`, set AGP version to 8.7.3 or later
- [ ] In `example/android/app/build.gradle.kts`:
  - `compileSdk = 35` (Android 15)
  - `ndkVersion = "28.0.12433566"` (or current r28+)
  - `targetSdk = 34`
- [ ] Configure NDK build flags for 16KB page size:
  - Add to `cargo-ndk` invocations: `-Z build-std --target=aarch64-linux-android`
  - Set `ANDROID_NDK_HOME` env var
- [ ] In `cargo` config (`.cargo/config.toml` for the Rust crate):
  ```toml
  [target.aarch64-linux-android]
  linker = "...path-to-ndk/aarch64-linux-android-ld..."
  rustflags = ["-C", "link-args=-Wl,-z,max-page-size=16384,-z,common-page-size=16384"]
  ```

### Verification

- [ ] Build APK: `cd example && flutter build apk --release`
- [ ] Verify 16KB alignment with `readelf` or Android's `zipalign -c -v -P 16 4 app.apk`
- [ ] Test on physical Pixel 8a or emulator with 16KB page size
- [ ] Upload AAB to Play Store internal testing track
- [ ] Confirm Play Store does NOT reject for 16KB incompatibility

### Documentation

- [ ] Add `docs/android-16kb-setup.md` documenting the build flags and verification steps

---

## Milestone 0.4: CI Matrix (Day 11–14)

### GitHub Actions

- [ ] Create `.github/workflows/ci.yml`:
  - Triggers: push to main, PRs
  - Matrix: `os: [macos-latest, ubuntu-latest, windows-latest]`
  - Jobs:
    1. `cargo test` in `rust/cardano_flutter_rs`
    2. `cargo clippy --all-targets -- -D warnings`
    3. `cargo fmt --check`
    4. `flutter pub get` in `dart/`
    5. `flutter test` in `dart/`
    6. `flutter analyze` in `dart/`
    7. `dart format --set-exit-if-changed .`
- [ ] Best-effort integration test on macos-latest:
  - Run iOS simulator
  - Build + launch example app
  - Run a simple `flutter test integration_test/` that verifies hello-world
- [ ] Verify all matrix jobs pass on push to main

### Branch Protection

- [ ] Configure GitHub branch protection on `main`:
  - Require pull request reviews before merging (≥1 approval)
  - Require status checks to pass (all CI jobs)
  - Require branches to be up to date before merge
  - Restrict push access to maintainers

---

## Milestone 0.5: Open-Source Polish (Day 15–16)

### Files Already Created ✅

- `LICENSE` (MIT)
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `MAINTAINERS.md`
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`
- `.github/pull_request_template.md`

### Files to Create

- [ ] `README.md` at repo root:
  - Project overview (1 paragraph)
  - Architecture diagram or link to `docs/`
  - Quick start: clone, install dependencies, run example
  - Platform support table (iOS ✅, Android ✅, others 🚧)
  - Status badge (CI), license badge
  - Link to docs, CONTRIBUTING, governance
- [ ] `docs/architecture.md`:
  - The FFI layer cake (Dart → frb → Rust → CML)
  - Backend trait abstraction
  - Web bypass strategy (JS interop)
  - Android 16KB notes
- [ ] `docs/getting-started.md`:
  - Prerequisites (Flutter, Rust, NDK)
  - Installation
  - First example
  - Common pitfalls
- [ ] `CHANGELOG.md` (initial entry for v0.0.1-foundation)

---

## Phase 0 Exit Checklist

When ready to call Phase 0 complete, verify all items pass:

### Code & Build
- [ ] `cargo build` succeeds
- [ ] `cargo test` passes (even if minimal — verify at least the sdk_version + is_valid_bech32 functions)
- [ ] `cargo clippy --all-targets -- -D warnings` passes
- [ ] `cargo fmt --check` passes
- [ ] `flutter pub get` succeeds in `dart/`
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
- [ ] `dart format --set-exit-if-changed .` passes

### Platforms
- [ ] Example app runs on iOS simulator (verified manually)
- [ ] Example app runs on Android emulator (verified manually)
- [ ] Example app installs and runs on Pixel 8a or 16KB-compatible device
- [ ] Android Play Store internal testing track accepts the build

### CI
- [ ] All GitHub Actions matrix jobs pass on main
- [ ] Branch protection rules enforced
- [ ] No flaky tests

### Documentation
- [ ] README has accurate quick-start that a stranger can follow
- [ ] Architecture doc accurately describes the FFI stack
- [ ] All files have SPDX-License-Identifier headers

### Tag & Communicate
- [ ] Tag commit `v0.0.1-foundation`
- [ ] Update CLAUDE.md "Current state" section
- [ ] Optional: post first commit publicly on X/Cardano forum (no urgency)

---

## Common Pitfalls & Resolutions

### "flutter_rust_bridge_codegen generate" fails

- Verify `flutter_rust_bridge_codegen` is installed at the correct version (`cargo install flutter_rust_bridge_codegen --locked --version ^2.12`)
- Check `flutter_rust_bridge_codegen.yaml` or equivalent config exists with correct paths
- Re-run with `--verbose` for detailed errors

### iOS staticlib build fails

- Ensure `crate-type = ["cdylib", "staticlib"]` is set in `Cargo.toml`
- Verify iOS targets are installed: `rustup target list --installed`
- Use `cargo-xcode` or manual `lipo` to create universal binary

### Android NDK 16KB build fails

- Verify NDK r28+ (check `$ANDROID_NDK_HOME/source.properties`)
- Set linker flags via `.cargo/config.toml` (see Milestone 0.3)
- Test on emulator with 16KB page size first before physical device

### CSL/CML dependency build fails

- These are large crates; first build takes 5–15 minutes
- Add `cardano-multiplatform-lib` to dependencies with `optional = true` and enable via feature flag
- If linker errors on iOS, try `cargo build --target aarch64-apple-ios --release` with `-Z build-std`

### Flutter analyzes warnings

- Run `dart fix --apply` to auto-fix
- Check `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`

---

## Where Next?

Once all checklists pass and Phase 0 is tagged:

1. Take a break — you earned it.
2. Read `.claude/goals/phase-1.md` for Phase 1 scope
3. Reach out (optional) to TokeoPay re: shared Rust core
4. Begin Phase 1 milestone work
