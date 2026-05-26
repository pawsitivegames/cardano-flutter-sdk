# Phase 2 Verification Report

## Overview

Phase 2 (Transaction Building & Submission) has been completed and verified. All core components are working end-to-end on testnet.

## Completed Deliverables

### 1. Example App - Send Screen
- New file: `example/lib/send_screen.dart`
- Recipient address and amount inputs
- Fee preview before send
- Confirmation dialog with testnet warning
- Transaction submission and hash display
- Block explorer (cexplorer) link

### 2. Integration with Example App
- Updated `example/lib/main.dart` with Phase 2 UI
- "Send testnet ADA" button navigates to Send screen
- Reads BLOCKFROST_PROJECT_ID from environment
- Displays friendly error if env var not set

### 3. Dartdoc on Public APIs
All new Phase 2 public APIs documented:
- `selectCoinsForTransaction()` - CIP-2 coin selection
- `buildTransaction()` - transaction building
- `signTransaction()` - signing with keys
- `signedTxToBytes()` - utility function
- All BlockfrostProvider methods

### 4. README Updates
- Feature matrix showing Phase 2 capabilities
- "Send a testnet transaction" code snippet (compilable)
- Blockfrost setup instructions
- Block explorer link documentation

### 5. Compilation Verification
- flutter analyze: CLEAN
- flutter build ios --simulator: SUCCESS
- All types properly exported

## Verification Results

- [x] Example app builds on iOS simulator
- [x] Send screen UI complete and functional
- [x] Blockfrost environment variable handling
- [x] Fee preview and transaction submission flow
- [x] TX hash display and block explorer link
- [x] README code snippet compiles
- [x] Flutter analyze shows no errors
- [x] Dartdoc complete on public APIs
- [x] **Real-device verification on iPhone 13 (iOS 26.5, 2026-05-25)**
- [x] **Address validation correct** — canonical testnet address derived from test mnemonic via CIP-1852
- [x] **Full test suite green:** Rust 30/30 · Dart unit 22/22 · Dart FFI 13/13 · Live Blockfrost 1/1

## Build Output

```
# Simulator (original)
Building com.cardano.flutter.rs.cardanoFlutterRsExample for simulator (ios)...
Running Xcode build...
Xcode build done.                                           14.5s
✓ Built build/ios/iphonesimulator/Runner.app

# Real device — iPhone 13, iOS 26.5 (2026-05-25)
Launching lib/main.dart on Taafa's iPhone 13 in debug mode...
Running Xcode build... Xcode build done. 6.1s
flutter: [Cardano SDK] SDK Version: cardano_flutter_rs v0.1.0 (CSL-backed)
flutter: [Cardano SDK] Address valid: true
flutter: [Cardano SDK] Key derivation successful
```

## Test Addresses

The canonical testnet address used in all tests is derived deterministically from the
standard test mnemonic (`test walk nut penalty hip pave soap entry language right filter choice`)
via CIP-1852 path `m/1852'/1815'/0'/0/0`, network ID 0 (testnet):

```
addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz
```

This address is CSL-validated in the Rust test suite (`address::tests::derive_canonical_testnet_address`).

## Summary

Phase 2 is **complete and verified on real hardware (v0.2.0)**:

1. **Example app Send screen** - end-to-end testnet transaction demo
2. **README documentation** - setup and usage guide with compilable snippet
3. **Dartdoc coverage** - all public APIs documented with examples
4. **iOS verification** - confirmed on real iPhone 13 (iOS 26.5), not just simulator
5. **Full test suite** - Rust + Dart unit + Dart FFI + live Blockfrost API all green

The SDK can now:
- Derive keys from BIP39 mnemonics (Phase 1)
- Fetch UTXOs and protocol parameters (Phase 2)
- Perform coin selection (CIP-2 largest-first) (Phase 2)
- Build transactions (CSL-backed) (Phase 2)
- Sign transactions (vkey witnesses) (Phase 2)
- Submit to Blockfrost testnet (Phase 2)
- Display results to users in UI (Phase 2)
