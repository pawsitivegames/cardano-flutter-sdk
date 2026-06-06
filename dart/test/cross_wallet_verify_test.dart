// Cross-wallet interop gate (Phase 6).
//
// Proves our CIP-30 `verifyData` (COSE_Sign1 parse + Ed25519 verify + identity
// binding) accepts signatures produced by THIRD-PARTY wallets (Lace, Eternl, …),
// not just our own `signData`. This is the in-our-control external-interop signal
// for the RC: a real wallet-signed message must verify under native verifyData.
//
// Fixtures live in `test/fixtures/cross_wallet_signatures.json`. The array starts
// empty — until a maintainer captures a real signature (see
// `docs/cross-wallet-verify.md`), this test SKIPS rather than fails, so CI stays
// green. Once populated, each fixture is asserted to verify, AND a tampered-payload
// copy is asserted to be rejected — so a passing fixture proves the check is real.
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

  if (signatures.isEmpty) {
    test('cross-wallet verify (no fixtures yet — skipped)', () {
      markTestSkipped(
        'No third-party wallet signatures captured yet. See '
        'docs/cross-wallet-verify.md to add a real Lace/Eternl signData output '
        'to test/fixtures/cross_wallet_signatures.json.',
      );
    }, skip: true);
    return;
  }

  for (final f in signatures) {
    final label = '${f['wallet'] ?? 'wallet'} / ${f['message'] ?? f['payloadHex']}';
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
