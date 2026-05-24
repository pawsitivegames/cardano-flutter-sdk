// Convenience wrappers for generated RustLibApi methods.
// These provide direct access to Rust functions via simpler names.

import 'frb_generated.dart';
import 'wallet.dart';
import 'address.dart';

/// Returns the SDK version string.
Future<String> getSdkVersion() {
  return Future.value(RustLib.instance.api.cardanoFlutterRsSdkVersion());
}

/// Validates a Bech32 address string.
Future<bool> isValidBech32(String addr) {
  return Future.value(
      RustLib.instance.api.cardanoFlutterRsAddressIsValidBech32(addr: addr));
}

/// Validates an address and returns detailed info.
Future<AddressInfo> validateAddress(String address) {
  return RustLib.instance.api.cardanoFlutterRsAddressValidateAddressInternal(
      addressStr: address);
}

/// Derives keys from a BIP39 mnemonic.
Future<KeyDerivationResult> deriveKeysFromMnemonic({
  required String mnemonic,
  required String passphrase,
  required int accountIndex,
  required bool isTestnet,
}) {
  return RustLib.instance.api.cardanoFlutterRsWalletDeriveKeysFromMnemonicInternal(
    mnemonic: mnemonic,
    passphrase: passphrase,
    accountIndex: accountIndex,
    isTestnet: isTestnet,
  );
}

/// Derives a child key from an account key.
Future<String> deriveAccountKey({
  required String accountKey,
  required int role,
  required int index,
}) {
  return Future.value(RustLib.instance.api.cardanoFlutterRsWalletDeriveAccountKey(
    accountKey: accountKey,
    role: role,
    index: index,
  ));
}
