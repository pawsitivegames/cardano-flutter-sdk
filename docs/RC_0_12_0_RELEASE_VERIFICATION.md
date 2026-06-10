# 0.12.0 RC Release Verification

Date: 2026-06-10

## Local Gates

- PASS: `cd rust && cargo fmt --check`
- PASS: `cd rust && cargo clippy --all-targets -- -D warnings`
- PASS: `cd rust && cargo test` — 146 passed
- PASS: `cd rust && cargo build --lib`; copied current debug dylib to
  `rust/target/release/libcardano_flutter_rs.dylib` for Flutter tests
- PASS: `cd dart && flutter analyze`
- PASS: `cd example && flutter analyze`
- PASS: `cd dart && flutter test` — 195 passed, 4 skipped live tests
- PASS: `cd dart && flutter test --coverage` — 195 passed, 4 skipped live tests
- PASS: filtered hand-written Dart coverage — 558/697 lines, 80.06%
- PASS: hardcoded Blockfrost release grep — no active `previewAmnr`, `_devKey`, or
  `TODO: remove before release` hits outside the historical security-review doc
- PASS: `dart compile js web/conformance_harness.dart ...`
- PASS: `dart compile js web/web_wallet_harness.dart ...`
- PASS: `cd tool/web_conformance && npm install && node build.mjs`
- PASS: `cd tool/web_conformance && node run-headless.mjs` —
  `PASS 32 FAIL 0 SKIP 0 / 32`
- PASS: `cd tool/web_conformance && node run-headless-wallet.mjs` —
  `PASS 10 FAIL 0 / 10`
- PASS: `cd example && flutter build ios --release --no-codesign`
- PASS: `bash dart/macos/build_macos_framework.sh`
- PASS: `cd example && flutter build macos --release`
- PASS: `cd example && flutter test integration_test/macos_packaging_test.dart -d macos`
- PASS: `cd example && flutter build web -t lib/main_web.dart`
- PASS: `cd example && JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH flutter build apk --release`

## Notes

- The Android build fails under the machine default JDK 26 because Gradle/Kotlin
  cannot parse Java version `26.0.1` during settings evaluation. JDK 21 succeeds.
- The web example build emits Flutter wasm-dry-run warnings for transitive
  dependencies that import `dart:html`, `dart:js_util`, and `package:js`. The
  JavaScript web build still succeeds.
- `dart pub publish --dry-run` succeeds structurally but reports one warning:
  `flutter_rust_bridge` is pinned to `2.12.0`. That pin is intentional for this
  package because the generated FRB bindings and Rust bridge content hash must
  stay aligned.
- Live Blockfrost tests were skipped because `BLOCKFROST_PROJECT_ID` was not set.
  The submit-spending live test also requires `CIP30_LIVE_SUBMIT=1`.

## Still External

- Publish `cardano_flutter_rs` `0.12.0` to pub.dev.
- Re-run remote GitHub CI for the final release cut.
- Rotate the historical Blockfrost development key outside the repository if it
  has not already been rotated.
- Android physical-device verification and Play Store acceptance remain
  post-RC / `1.0.0` gates.
- Ledger transaction signing remains `@experimental` until physical hardware
  verification.
