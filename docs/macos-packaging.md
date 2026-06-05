# macOS Desktop Packaging (Phase 6)

> Status: **done & verified** (2026-06-04). The SDK builds, embeds, codesigns, and
> loads its Rust FFI on macOS; the example runs unchanged. CI gates it.

macOS runs the **native CSL backend over Rust FFI** (same as iOS/Android), *not*
the web CML-JS backend. The work was to package the Rust library as a macOS
Flutter plugin and prove the FFI loads at runtime in a real `.app`.

## Pieces

| Path | Role |
|------|------|
| `dart/macos/cardano_flutter_rs.podspec` | macOS FFI plugin spec. `FlutterMacOS` dep, `:osx, '10.15'`, `static_framework = true`, vendors `Libs/cardano_flutter_rs.framework`. |
| `dart/macos/Classes/CardanoFlutterRsPlugin.{h,m}` | Symbol-forcing ObjC stub — holds hard references to the `frb_*` symbols so the linker keeps the framework and it loads into the process. |
| `dart/macos/build_macos_framework.sh` | Builds the universal (arm64 + x86_64) Rust dylib and assembles a **versioned** `.framework` with install name `@rpath/cardano_flutter_rs.framework/cardano_flutter_rs`. |
| `dart/macos/Libs/cardano_flutter_rs.framework` | The vendored universal framework (committed, like the iOS binaries, so consumer builds are turnkey; CI rebuilds it from source to stay current). |
| `example/macos/` | Scaffolded Runner. `DebugProfile`/`Release` entitlements add `com.apple.security.network.client` for the provider layer (Blockfrost / CIP-45). |
| `example/integration_test/macos_packaging_test.dart` | Runs inside the built `.app`; loads the embedded framework via the FRB loader and exercises FFI deterministically. |

## Why these specific choices

- **Versioned framework bundle** (`Versions/A` + symlinks), not a flat one or a
  bare dylib: macOS `codesign` rejects malformed framework bundles, and a release
  `flutter build macos` deep-signs everything under `Contents/Frameworks`. The iOS
  framework here is flat (iOS allows that); macOS needs the versioned layout.
- **`static_framework = true`** (same as iOS): with `use_frameworks!` every pod
  would otherwise become its own dynamic framework, and the ObjC stub's
  `cardano_flutter_rs.framework` would collide with the vendored Rust framework of
  the same name. Static-linking the stub leaves the Rust framework as the sole one.
- **The FRB loader resolution order** (macOS, from `flutter_rust_bridge`
  `loader/_io.dart`) is: `libcardano_flutter_rs.dylib` →
  `rust_builder.framework/rust_builder` →
  **`cardano_flutter_rs.framework/cardano_flutter_rs`**. We ship the third — the
  same shape iOS uses. The embedded framework resolves via the app's rpath
  (`@executable_path/../Frameworks`); the integration test confirms it loads.
- **`network.client` entitlement**: the Rust FFI needs no entitlement, but the
  SDK's Dart provider layer (Blockfrost REST, CIP-45 WebRTC) is blocked by the App
  Sandbox without it. Added to both Debug and Release entitlements.
- **No trimmed example needed**: all example plugins ship macOS implementations,
  so the full example builds and runs on macOS unchanged (the earlier assumption
  that a desktop build needed a stripped-down example was wrong).

## Rebuilding after a Rust change

```bash
bash dart/macos/build_macos_framework.sh      # regenerate the universal framework
# for `flutter test` (host dylib), also refresh rust/target/release per CLAUDE.md
cd example && flutter build macos --release
flutter test integration_test/macos_packaging_test.dart -d macos
```

## CI gate

The `macos-build` job (`.github/workflows/ci.yml`, in the gating summary) rebuilds
the framework from source, runs a **release** `flutter build macos` (compile +
link + codesign + entitlements), then runs the packaging integration test inside
the built `.app`. A regression in any of those fails the build.

## Verified (2026-06-04, Apple Silicon, macOS 26.6)

- [x] Universal dylib (arm64 + x86_64), `frb_*` symbols present.
- [x] Debug + release `flutter build macos` succeed; release framework stays
      universal; deep `codesign -v` passes on framework and app.
- [x] App ships `app-sandbox` + `network.client` entitlements.
- [x] Integration test in the built `.app`: `RustLib.init()` loads the embedded
      framework and FFI key-derivation round-trips deterministically (`+1`).
