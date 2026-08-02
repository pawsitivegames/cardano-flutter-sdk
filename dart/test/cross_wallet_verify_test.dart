// Cross-wallet interop gate (Phase 6).
//
// Proves our CIP-30 `verifyData` (COSE_Sign1 parse + Ed25519 verify + identity
// binding) accepts signatures produced by THIRD-PARTY wallets (Lace, Eternl, …),
// not just our own `signData`. This is the in-our-control external-interop signal
// for the RC: a real wallet-signed message must verify under native verifyData.
//
// Fixtures live in `test/fixtures/cross_wallet_signatures.json`. Each fixture is
// asserted to verify, AND a tampered-payload copy is asserted to be rejected — so
// a passing fixture proves the check is real. The fixture is a release-quality
// interop gate, so an empty array fails instead of silently removing coverage.
import 'dart:convert';
import 'dart:io';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  final file = File('test/fixtures/cross_wallet_signatures.json');
  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final signatures = (root['signatures'] as List).cast<Map<String, dynamic>>();

  test('cross-wallet fixture retains at least one real wallet vector', () {
    expect(signatures, isNotEmpty,
        reason: 'At least one third-party wallet fixture is required. See '
            'docs/cross-wallet-verify.md to add a real wallet signData output.');
  });

  for (final f in signatures) {
    final label =
        '${f['wallet'] ?? 'wallet'} / ${f['message'] ?? f['payloadHex']}';
    final expectAccept = (f['expectAccept'] as bool?) ?? true;
    final payloadHex = f['payloadHex'] as String;
    final addressHex = f['addressHex'] as String?;
    final sig = DataSignature(
      signature: f['signature'] as String,
      key: f['key'] as String,
    );

    test('cross-wallet verify: $label', () {
      final ok = cip30VerifyData(
        dataSignature: sig,
        expectedPayloadHex: payloadHex,
        expectedAddressHex: addressHex,
      );
      expect(ok, expectAccept,
          reason: 'verifyData on $label returned $ok, expected $expectAccept');

      // A genuinely-valid fixture must reject a tampered payload — otherwise the
      // acceptance above proves nothing.
      if (expectAccept) {
        final tampered = cip30VerifyData(
          dataSignature: sig,
          expectedPayloadHex: '${payloadHex}00',
          expectedAddressHex: addressHex,
        );
        expect(tampered, isFalse,
            reason: 'tampered-payload verify on $label unexpectedly accepted');
      }
    });
  }
}
