// In-browser conformance harness entrypoint (Phase 6 web gate).
//
// Compiled with `dart compile js` and loaded by `tool/web_conformance/index.html`
// AFTER `globalThis.CML` / `globalThis.MS` (the CML + cardano-message-signing
// browser WASM builds) are instantiated. It drives `CmlWebBackend` through the
// SAME `runConformanceCase` runner and the SAME frozen golden vectors the native
// CI gate uses, then publishes a summary the test driver reads.
//
// This is what turns the Node-level library-equivalence proof
// (`tool/cml_conformance_spike/`) into a verification of THIS Dart JS-interop
// binding against the real browser WASM build. See `docs/web-backend.md`.
library;

import 'dart:js_interop';

import 'package:cardano_flutter_rs/src/conformance/cml_web_backend.dart';
import 'package:cardano_flutter_rs/src/conformance/conformance_contract.dart';

@JS('GOLDEN_JSON')
external String get _goldenJson;

@JS('CONFORMANCE_RESULT')
external set _result(JSAny value);

@JS('console.log')
external void _log(String message);

void main() {
  const backend = CmlWebBackend();
  final cases = parseConformanceCases(_goldenJson);

  var pass = 0;
  var fail = 0;
  var skip = 0;
  final lines = <String>[];

  for (final c in cases) {
    String got;
    try {
      got = runConformanceCase(backend, c);
    } on UnimplementedError {
      // Out-of-contract op intentionally unmapped on web (verifyData / legacy
      // signMessageCose). Not a failure — record and move on.
      skip++;
      continue;
    } catch (e) {
      got = 'ERROR: $e';
    }
    if (got == c.expected) {
      pass++;
    } else {
      fail++;
      lines.add('✗ ${c.id} (${c.op})\n    exp: ${c.expected}\n    got: $got');
    }
  }

  final summary = StringBuffer()
    ..writeln('PASS $pass  FAIL $fail  SKIP $skip  / ${cases.length}');
  for (final l in lines) {
    summary.writeln(l);
  }

  final text = summary.toString();
  _log(text);
  _result = text.toJS;
}
