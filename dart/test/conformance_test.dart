// Phase 6: CSL↔CML golden-CBOR conformance gate.
//
// Asserts the native (CSL/FFI) backend still reproduces every frozen golden
// vector in `test/conformance/golden_cbor.json`. Drift here means a CSL upgrade
// changed canonical bytes — a potential consensus/interop hazard that must be
// reviewed deliberately (regenerate via `generate_golden.dart` only on purpose).
//
// The same vectors are the contract a future web (CML-JS) backend must satisfy;
// see `docs/web-backend.md`. Run that backend through `runConformanceCase`
// against this identical file to prove byte-for-byte parity.

import 'dart:io';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const backend = NativeConformanceBackend();
  late List<ConformanceCase> cases;

  setUpAll(() async {
    await RustLib.init();
    final file = File('test/conformance/golden_cbor.json');
    expect(file.existsSync(), isTrue,
        reason: 'golden_cbor.json missing — run generate_golden.dart');
    cases = parseConformanceCases(file.readAsStringSync());
  });

  test('golden file is non-empty and covers each category', () {
    expect(cases, isNotEmpty);
    final categories = cases.map((c) => c.category).toSet();
    expect(categories,
        containsAll(<String>{'address', 'value', 'plutus', 'witness', 'cose'}));
  });

  test('vector ids are unique', () {
    final ids = cases.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate vector id');
  });

  test('native CSL backend reproduces every golden vector byte-for-byte', () {
    final mismatches = <String>[];
    for (final c in cases) {
      final actual = runConformanceCase(backend, c);
      if (actual != c.expected) {
        mismatches.add('• ${c.id} (${c.op})\n'
            '    expected: ${c.expected}\n'
            '    actual:   $actual');
      }
    }
    expect(mismatches, isEmpty,
        reason: 'Conformance drift in ${mismatches.length} vector(s):\n'
            '${mismatches.join('\n')}');
  });

  test('COSE signatures from golden vectors verify', () {
    for (final c in cases.where((c) => c.op == 'signData')) {
      final parts = c.expected.split('|');
      final ok = backend.verifyData(
        signature: parts[0],
        key: parts[1],
        expectedPayloadHex: c.input['payloadHex'] as String,
      );
      expect(ok, isTrue, reason: 'signData vector ${c.id} failed to verify');
    }
  });
}
