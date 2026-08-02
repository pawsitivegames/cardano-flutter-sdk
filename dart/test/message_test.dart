// Public API contract tests for the retained legacy message-signing surface.
// CIP-30 signData is the interoperable path; these tests make the legacy
// format's round-trip and identity/failure behavior explicit.

import 'dart:convert';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';

const _mnemonic =
    'test walk nut penalty hip pave soap entry language right filter choice';

String _utf8Hex(String value) =>
    utf8.encode(value).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  late KeyDerivationResult keys;
  late String address;

  setUp(() async {
    keys = await deriveKeysFromMnemonic(
      mnemonic: _mnemonic,
      passphrase: '',
      accountIndex: 0,
      isTestnet: true,
    );
    address = computeBaseAddress(
      paymentKeyHashHex: keys.paymentKeyHash,
      stakeKeyHashHex: keys.stakeKeyHash,
      networkId: 0,
    );
  });

  test('signs and verifies the legacy payment-key message round-trip',
      () async {
    final signed = await signMessage(
      message: _utf8Hex('legacy message'),
      signingKey: keys.paymentSigningKey,
      address: address,
    );

    expect(signed.coseSign1Hex, isNotEmpty);
    expect(signed.publicKeyHex, hasLength(64));
    expect(signed.address, address);
    expect(
      await verifyMessage(
        signedMessage: signed,
        expectedAddress: address,
      ),
      isTrue,
    );
  });

  test('rejects a valid signature stamped with another wallet address',
      () async {
    final attacker = await deriveKeysFromMnemonic(
      mnemonic: _mnemonic,
      passphrase: '',
      accountIndex: 1,
      isTestnet: true,
    );
    final forged = await signMessage(
      message: _utf8Hex('transfer authorization'),
      signingKey: attacker.paymentSigningKey,
      address: address,
    );

    expect(
      await verifyMessage(
        signedMessage: forged,
        expectedAddress: address,
      ),
      isFalse,
    );
    expect(await verifyMessage(signedMessage: forged), isFalse);
  });

  test('rejects a mismatched expected address', () async {
    final signed = await signMessage(
      message: _utf8Hex('address-bound message'),
      signingKey: keys.paymentSigningKey,
      address: address,
    );
    final other = await deriveKeysFromMnemonic(
      mnemonic: _mnemonic,
      passphrase: '',
      accountIndex: 1,
      isTestnet: true,
    );
    final otherAddress = computeBaseAddress(
      paymentKeyHashHex: other.paymentKeyHash,
      stakeKeyHashHex: other.stakeKeyHash,
      networkId: 0,
    );

    expect(
      await verifyMessage(
        signedMessage: signed,
        expectedAddress: otherAddress,
      ),
      isFalse,
    );
  });

  test('rejects malformed message hex before signing', () async {
    expect(
      () => signMessage(
        message: 'abc',
        signingKey: keys.paymentSigningKey,
      ),
      throwsA(anything),
    );
  });
}
