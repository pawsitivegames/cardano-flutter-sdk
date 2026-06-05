#!/bin/bash
# Build the universal (arm64 + x86_64) macOS Rust framework for the SDK.
#
# Produces dart/macos/Libs/cardano_flutter_rs.framework — a proper *versioned*
# macOS framework bundle (codesign requires the Versions/A layout) whose binary
# is a lipo'd universal dylib with install name
#   @rpath/cardano_flutter_rs.framework/cardano_flutter_rs
# so the embedded copy in <App>.app/Contents/Frameworks resolves at runtime.
#
# The macOS FRB loader (flutter_rust_bridge .../loader/_io.dart) resolves, in
# order: libcardano_flutter_rs.dylib → rust_builder.framework/rust_builder →
# cardano_flutter_rs.framework/cardano_flutter_rs. We provide the third (the same
# shape the iOS side ships), and the ObjC stub in Classes/ force-links it so the
# framework is loaded at launch and the loader gets the live handle.
#
# Re-run after any Rust change (and re-copy the dylib for `flutter test`, per
# CLAUDE.md). CI runs this in the macos-build job.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$(cd "$SCRIPT_DIR/../../rust" && pwd)"
LIBS_DIR="$SCRIPT_DIR/Libs"
FRAMEWORK="$LIBS_DIR/cardano_flutter_rs.framework"
NAME="cardano_flutter_rs"

echo "[macos] building Rust release for both darwin arches…"
( cd "$RUST_DIR"
  rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null 2>&1 || true
  cargo build --release --lib --target aarch64-apple-darwin
  cargo build --release --lib --target x86_64-apple-darwin )

ARM="$RUST_DIR/target/aarch64-apple-darwin/release/lib${NAME}.dylib"
X86="$RUST_DIR/target/x86_64-apple-darwin/release/lib${NAME}.dylib"

echo "[macos] assembling versioned framework bundle…"
rm -rf "$FRAMEWORK"
mkdir -p "$FRAMEWORK/Versions/A/Resources"
lipo -create -output "$FRAMEWORK/Versions/A/$NAME" "$ARM" "$X86"
lipo -info "$FRAMEWORK/Versions/A/$NAME"

install_name_tool -id "@rpath/$NAME.framework/$NAME" "$FRAMEWORK/Versions/A/$NAME"

cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.pawsitivegames.cardanoFlutterRs</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.9.0</string>
  <key>CFBundleVersion</key><string>0.9.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
</dict>
</plist>
PLIST

# Standard macOS framework symlinks (Current → A; top-level → Versions/Current/*).
ln -sfn A "$FRAMEWORK/Versions/Current"
ln -sfn "Versions/Current/$NAME" "$FRAMEWORK/$NAME"
ln -sfn "Versions/Current/Resources" "$FRAMEWORK/Resources"

echo "[macos] done: $FRAMEWORK"
