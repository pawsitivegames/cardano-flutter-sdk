#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
JNI_DIR="$ROOT_DIR/dart/android/src/main/jniLibs"

ABIS="${ABIS:-arm64-v8a}"
PROFILE="${PROFILE:-release}"
MIN_API="${MIN_API:-24}"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_SDK_ROOT/ndk/28.2.13676358}"

if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "Android NDK not found at: $ANDROID_NDK_HOME" >&2
  echo "Install it with: sdkmanager 'ndk;28.2.13676358'" >&2
  exit 1
fi

if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "cargo-ndk is required. Install with: cargo install cargo-ndk --locked" >&2
  exit 1
fi

target_for_abi() {
  case "$1" in
    arm64-v8a) echo "aarch64-linux-android" ;;
    armeabi-v7a) echo "armv7-linux-androideabi" ;;
    x86_64) echo "x86_64-linux-android" ;;
    x86) echo "i686-linux-android" ;;
    *)
      echo "Unsupported ABI: $1" >&2
      exit 1
      ;;
  esac
}

mkdir -p "$JNI_DIR"

for abi in $ABIS; do
  target="$(target_for_abi "$abi")"
  rustup target add "$target"
done

build_args=(ndk --platform "$MIN_API")
for abi in $ABIS; do
  build_args+=(-t "$abi")
done
build_args+=(-o "$JNI_DIR" build)

if [[ "$PROFILE" == "release" ]]; then
  build_args+=(--release)
elif [[ "$PROFILE" != "debug" ]]; then
  echo "Unsupported PROFILE: $PROFILE (use release or debug)" >&2
  exit 1
fi

(
  cd "$RUST_DIR"
  ANDROID_NDK_HOME="$ANDROID_NDK_HOME" cargo "${build_args[@]}"
)

echo "Built Android JNI libraries:"
find "$JNI_DIR" -name '*.so' -maxdepth 3 -print | sort
