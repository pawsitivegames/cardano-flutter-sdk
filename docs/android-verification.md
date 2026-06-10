# Android Verification

Current status: Android is verified on an ARM64 16 KB page-size emulator. This is
not physical-device verification and does not prove all Android ABIs are ready.
The checklist follows Android's 16 KB page-size guidance:
https://developer.android.com/guide/practices/page-sizes

## Prerequisites

- Flutter stable
- Android SDK command-line tools
- Android NDK `28.2.13676358`
- JDK 21 for Gradle on this machine
- `cargo-ndk`

```bash
brew install openjdk@21
rustup target add aarch64-linux-android
cargo install cargo-ndk --locked
sdkmanager "ndk;28.2.13676358"
```

## Build JNI Libraries

```bash
tool/android/build_android_jni.sh
```

By default this builds only `arm64-v8a`, matching the current emulator gate. To
build more ABIs later:

```bash
ABIS="arm64-v8a x86_64" tool/android/build_android_jni.sh
```

The Flutter example currently packages `arm64-v8a` only. Do not claim broader
Android ABI support until the extra Rust JNI libraries are built and the APK/AAB
passes 16 KB checks for those ABIs.

## 16 KB Emulator

Install the 16 KB image and create an AVD:

```bash
sdkmanager "system-images;android-36;google_apis_ps16k;arm64-v8a"
avdmanager create avd \
  -n cardano_ps16k_api36 \
  -k "system-images;android-36;google_apis_ps16k;arm64-v8a" \
  -d pixel_8
```

Boot and verify page size:

```bash
emulator -avd cardano_ps16k_api36 -no-snapshot -no-audio -no-boot-anim
adb wait-for-device
adb shell getconf PAGESIZE
# expected: 16384
```

## Build And Check APK

```bash
cd example
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH \
flutter build apk --debug

zipalign -c -P 16 -v 4 build/app/outputs/flutter-apk/app-debug.apk
```

The APK should contain only `lib/arm64-v8a/*.so` for the current emulator gate.
Every ARM64 shared library should have `LOAD` segment alignment of `0x4000` or
larger.

## Install And Runtime Checks

Use a clean install when checking `pageSizeCompat`; Android can retain stale
compat metadata across an in-place reinstall.

```bash
adb uninstall com.example.cardano_flutter_rs_example || true
adb logcat -c
adb install example/build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.example.cardano_flutter_rs_example/.MainActivity
sleep 15

adb shell dumpsys package com.example.cardano_flutter_rs_example \
  | rg 'pageSizeCompat|primaryCpuAbi|extractNativeLibs'

adb logcat -d \
  | rg -i 'PageSizeMismatch|RustLib|SDK Version|Address valid|Key derivation|UnsatisfiedLinkError|FATAL EXCEPTION'
```

Expected evidence:

- `pageSizeCompat=0`
- `primaryCpuAbi=arm64-v8a`
- no `PageSizeMismatchDialog`
- `RustLib.init() completed successfully`
- `SDK Version: cardano_flutter_rs ...`
- `Address valid: true`
- `Key derivation successful`

## CIP-45 Deep Link And QR

```bash
ID=$(printf 'a%.0s' $(seq 1 64))
adb shell am start \
  -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d "web+cardano://connect/v1?identifier=$ID" \
  com.example.cardano_flutter_rs_example
```

Expected evidence:

- `app_links` logs `Handled intent`
- UI navigates to `CIP-45 Wallet (bugout)`
- URI field is populated with the `web+cardano://...` value
- tapping **Scan QR** opens the Android camera permission dialog without a crash
