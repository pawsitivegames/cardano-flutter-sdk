import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// macOS desktop packaging verification.
///
/// Runs INSIDE the built `.app` bundle (driven by `flutter test … -d macos`), so
/// it proves the real thing the unit-test suite cannot: that the universal Rust
/// framework embedded in `Contents/Frameworks/cardano_flutter_rs.framework`
/// actually loads at runtime on macOS and the FFI works — i.e. the podspec +
/// vendored framework + rpath wiring is correct, not just that the dylib builds.
///
/// Deterministic, no network. Run:
///   cd example && flutter test integration_test/macos_packaging_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';
  const backend = NativeConformanceBackend();

  testWidgets('embedded Rust framework loads and derives deterministically',
      (tester) async {
    // Loads cardano_flutter_rs.framework from the app bundle via the FRB loader.
    // If the framework were mis-packaged or unresolved at runtime, this throws.
    await RustLib.init();

    final keys = backend.deriveKeys(
      mnemonic: mnemonic,
      passphrase: '',
      accountIndex: 0,
      isTestnet: true,
    );
    expect(keys.accountKey, isNotEmpty);
    expect(keys.paymentKeyHash.length, 56); // Blake2b-224 = 28 bytes hex

    // Same CIP-1852 path the golden suite freezes — must land on a testnet base
    // address, proving the FFI round-trips real bytes through the embedded lib.
    final addr = backend.deriveAddress(
      accountKey: keys.accountKey,
      role: 0,
      index: 0,
      networkId: 0,
    );
    expect(addr.address, startsWith('addr_test1'));
  });
}
