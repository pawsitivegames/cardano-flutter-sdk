// Golden-vector generator for the CSL↔CML conformance suite (Phase 6).
//
// NOT a normal test (no `_test.dart` suffix → `flutter test` skips it). Run it
// explicitly to (re)generate the frozen golden file from the **native CSL**
// backend, then commit the result:
//
//   cd dart && flutter test test/conformance/generate_golden.dart
//
// The conformance test (`conformance_test.dart`) then asserts the native backend
// still reproduces these bytes, and a future CML-JS backend must match them too.
// Inputs are baked concretely (keys/addresses pre-derived) so the golden file is
// fully self-contained — a web backend can be checked against it without re-deriving.

import 'dart:io';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const backend = NativeConformanceBackend();
  const mnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';

  setUpAll(() async {
    await RustLib.init();
  });

  test('generate golden_cbor.json from native CSL backend', () async {

    // Derive once; bake concrete keys/addresses into the vector inputs.
    final keys = backend.deriveKeys(
      mnemonic: mnemonic,
      passphrase: '',
      accountIndex: 0,
      isTestnet: true,
    );
    final addr0 = backend.deriveAddress(
      accountKey: keys.accountKey,
      role: 0,
      index: 0,
      networkId: 0,
    );
    final addrHex = backend.addressToHex(addressBech32: addr0.address);

    final cases = <ConformanceCase>[
      ConformanceCase(
        id: 'key-derivation-acct0-testnet',
        category: 'address',
        op: 'keyDerivation',
        input: {
          'mnemonic': mnemonic,
          'passphrase': '',
          'accountIndex': 0,
          'isTestnet': true,
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'derive-address-r0-i0-testnet',
        category: 'address',
        op: 'deriveAddress',
        input: {
          'accountKey': keys.accountKey,
          'role': 0,
          'index': 0,
          'networkId': 0,
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'derive-address-r1-i0-testnet',
        category: 'address',
        op: 'deriveAddress',
        input: {
          'accountKey': keys.accountKey,
          'role': 1,
          'index': 0,
          'networkId': 0,
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'derive-address-r0-i5-testnet',
        category: 'address',
        op: 'deriveAddress',
        input: {
          'accountKey': keys.accountKey,
          'role': 0,
          'index': 5,
          'networkId': 0,
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'derive-address-r0-i0-mainnet',
        category: 'address',
        op: 'deriveAddress',
        input: {
          'accountKey': keys.accountKey,
          'role': 0,
          'index': 0,
          'networkId': 1,
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'compute-base-address-testnet',
        category: 'address',
        op: 'computeBaseAddress',
        input: {
          'paymentKeyHashHex': keys.paymentKeyHash,
          'stakeKeyHashHex': keys.stakeKeyHash,
          'networkId': 0,
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'compute-base-address-mainnet',
        category: 'address',
        op: 'computeBaseAddress',
        input: {
          'paymentKeyHashHex': keys.paymentKeyHash,
          'stakeKeyHashHex': keys.stakeKeyHash,
          'networkId': 1,
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'address-to-hex',
        category: 'address',
        op: 'addressToHex',
        input: {'addressBech32': addr0.address},
        expected: '',
      ),
      ConformanceCase(
        id: 'value-ada-only',
        category: 'value',
        op: 'valueToCbor',
        input: {'coin': '1000000', 'assets': <Map<String, dynamic>>[]},
        expected: '',
      ),
      ConformanceCase(
        id: 'value-single-asset',
        category: 'value',
        op: 'valueToCbor',
        input: {
          'coin': '2000000',
          'assets': [
            {
              'policyId':
                  '00000000000000000000000000000000000000000000000000000000',
              'assetName': '74657374', // "test"
              'quantity': '42',
            },
          ],
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'value-multi-asset',
        category: 'value',
        op: 'valueToCbor',
        input: {
          'coin': '5000000',
          'assets': [
            {
              'policyId':
                  '11111111111111111111111111111111111111111111111111111111',
              'assetName': '41', // "A"
              'quantity': '1',
            },
            {
              'policyId':
                  '22222222222222222222222222222222222222222222222222222222',
              'assetName': '42', // "B"
              'quantity': '1000000000000',
            },
          ],
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-int-zero',
        category: 'plutus',
        op: 'plutusInt',
        // `n` stored as a STRING so it survives dart2js JSON parsing (a JSON
        // number would be a lossy float64 on web). See ConformanceBackend.plutusDataInt.
        input: {'n': '0'},
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-int-small',
        category: 'plutus',
        op: 'plutusInt',
        input: {'n': '42'},
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-int-negative',
        category: 'plutus',
        op: 'plutusInt',
        input: {'n': '-1'},
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-int-large',
        category: 'plutus',
        op: 'plutusInt',
        input: {'n': '1234567890123456789'},
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-bytes',
        category: 'plutus',
        op: 'plutusBytes',
        input: {'hexData': 'deadbeef'},
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-bytes-empty',
        category: 'plutus',
        op: 'plutusBytes',
        input: {'hexData': ''},
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-constr-0',
        category: 'plutus',
        op: 'plutusConstr',
        input: {
          'constructor': '0',
          'fieldsCborHex': [backend.plutusDataInt(BigInt.from(42))],
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-constr-1-empty',
        category: 'plutus',
        op: 'plutusConstr',
        input: {'constructor': '1', 'fieldsCborHex': <String>[]},
        expected: '',
      ),
      ConformanceCase(
        id: 'plutus-list',
        category: 'plutus',
        op: 'plutusList',
        input: {
          'itemsCborHex': [
            backend.plutusDataInt(BigInt.one),
            backend.plutusDataInt(BigInt.two),
          ],
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'witness-set-single',
        category: 'witness',
        op: 'witnessSet',
        input: {
          'witnesses': [
            {
              // 32-byte vkey (64 hex), 64-byte signature (128 hex).
              'vkeyHex': 'ab' * 32,
              'signatureHex': 'cd' * 64,
            },
          ],
        },
        expected: '',
      ),
      ConformanceCase(
        id: 'sign-data-cafe',
        category: 'cose',
        op: 'signData',
        input: {
          'addressHex': addrHex,
          'payloadHex': 'cafe',
          'signingKeyBech32': keys.paymentSigningKey,
        },
        expected: '',
      ),
      // Canonical-ordering stress: assets supplied OUT of CBOR-canonical order
      // (policy 0x33 before 0x22; within 0x33, name "AB"(len 2) before "A"(len 1)).
      // A conformant backend MUST re-sort to canonical (0x22 first; "A" before
      // "AB"). This catches a backend that does no sorting — the #1 CSL/CML
      // divergence area, which the in-order vectors above cannot detect.
      ConformanceCase(
        id: 'value-multi-asset-unsorted',
        category: 'value',
        op: 'valueToCbor',
        input: {
          'coin': '3000000',
          'assets': [
            {
              'policyId':
                  '33333333333333333333333333333333333333333333333333333333',
              'assetName': '4142', // "AB" (length 2)
              'quantity': '7',
            },
            {
              'policyId':
                  '33333333333333333333333333333333333333333333333333333333',
              'assetName': '41', // "A" (length 1)
              'quantity': '8',
            },
            {
              'policyId':
                  '22222222222222222222222222222222222222222222222222222222',
              'assetName': '42', // "B"
              'quantity': '9',
            },
          ],
        },
        expected: '',
      ),
      // Multiple witnesses supplied out of vkey order — pins witness-set ordering.
      ConformanceCase(
        id: 'witness-set-multi',
        category: 'witness',
        op: 'witnessSet',
        input: {
          'witnesses': [
            {'vkeyHex': 'ab' * 32, 'signatureHex': 'cd' * 64},
            {'vkeyHex': '01' * 32, 'signatureHex': '02' * 64},
          ],
        },
        expected: '',
      ),
    ];

    // Fill expected outputs from the native backend.
    final filled = cases
        .map((c) => c.withExpected(runConformanceCase(backend, c)))
        .toList();

    final out = File('test/conformance/golden_cbor.json');
    out.writeAsStringSync(encodeConformanceCases(filled));
    // ignore: avoid_print
    print('Wrote ${filled.length} golden vectors to ${out.path}');

    expect(filled.every((c) => c.expected.isNotEmpty), isTrue);
  });
}
