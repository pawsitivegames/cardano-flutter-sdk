# cardano_flutter_rs

Production-grade Cardano SDK for Flutter. Native platforms use a thin Dart API
over `flutter_rust_bridge` into a Rust wrapper around Emurgo's
`cardano-serialization-lib` (CSL). Web uses a scoped CML-JS backend through Dart
JS interop, not Rust/WASM FFI.

## Status

`0.12.0` is the feature-complete RC:

- iOS: live-verified on device.
- Android: ARM64 16 KB page-size emulator verified. Physical-device and broader
  ABI verification are still pending.
- macOS: packaged FFI plugin verified, including testnet transaction submission.
- Web: scoped CML-JS backend verified in browser by golden-CBOR conformance.
- Hardware wallets: API is `@experimental`; Ledger transaction signing is not
  yet verified on physical hardware.

## Entrypoints

Use the native entrypoint for iOS, Android, macOS, Linux, and Windows:

```dart
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
```

Use the web-safe entrypoint for browser builds:

```dart
import 'package:cardano_flutter_rs/cardano_flutter_rs_web.dart';
```

## Example

```dart
final keys = await deriveKeysFromMnemonic(
  mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  networkId: 0,
);

final address = await deriveAddress(
  accountKey: keys.accountKey,
  role: 0,
  index: 0,
  networkId: 0,
);
```

See the repository README and `docs/PLAN.md` for platform support, verification
status, and roadmap details.
