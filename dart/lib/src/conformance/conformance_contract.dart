// Phase 6: the web-safe core of the CSL↔CML conformance contract.
//
// This file is **pure Dart** — it imports no FFI and no `dart:js_interop`, so it
// compiles on **every** platform (native AND web). It holds the parts both
// backends share:
//   • [ConformanceBackend]  — the scoped, deterministic op subset.
//   • [ConformanceCase]     — one (op, input, expected-output) golden vector.
//   • [runConformanceCase]  — backend-agnostic dispatcher.
//
// The backends themselves live in sibling files and are deliberately kept OUT of
// here so importing the contract never drags in a backend's platform deps:
//   • `conformance.dart`        → [NativeConformanceBackend] (CSL via Rust FFI;
//                                  pulls in `dart:ffi` — native only).
//   • `cml_web_backend.dart`    → `CmlWebBackend` (CML via `dart:js_interop`;
//                                  web only).
//
// Splitting this out is what lets `CmlWebBackend` (and an in-browser conformance
// harness) compile under dart2js without the FFI bridge — see `docs/web-backend.md`.
library;

import 'dart:convert';

/// A native-asset entry used by [ConformanceBackend.valueToCborHex], expressed
/// with plain types so the interface never leaks a backend-specific class.
typedef ConformanceAsset = ({
  String policyId,
  String assetName,
  BigInt quantity
});

/// A `(public key, signature)` pair for witness-set assembly.
typedef ConformanceWitness = ({String vkeyHex, String signatureHex});

/// Derived key material returned by [ConformanceBackend.deriveKeys].
typedef ConformanceKeys = ({
  String accountKey,
  String paymentKeyHash,
  String stakeKeyHash,
  String paymentSigningKey,
  String stakeSigningKey,
});

/// A derived base address plus its payment-key hash.
typedef ConformanceAddress = ({String address, String paymentKeyHash});

/// A COSE `signData` result (`COSE_Sign1` + `COSE_Key`, both hex CBOR).
typedef ConformanceSignature = ({String signature, String key});

/// The deterministic serialization/derivation subset that every backend must
/// implement identically. Every method here is a *pure function of its inputs*
/// (Ed25519 signing included — it is deterministic), so two conformant backends
/// always agree byte-for-byte.
///
/// Intentionally excluded: anything non-deterministic (random nonces, network
/// I/O) or not yet web-scoped (full tx fee/coin-selection — deferred to a later
/// web-parity track per `docs/PLAN.md`).
abstract interface class ConformanceBackend {
  /// Short identifier, e.g. `csl-ffi` or `cml-js`.
  String get name;

  ConformanceKeys deriveKeys({
    required String mnemonic,
    required String passphrase,
    required int accountIndex,
    required bool isTestnet,
  });

  ConformanceAddress deriveAddress({
    required String accountKey,
    required int role,
    required int index,
    required int networkId,
  });

  String computeBaseAddress({
    required String paymentKeyHashHex,
    required String stakeKeyHashHex,
    required int networkId,
  });

  String addressToHex({required String addressBech32});

  String valueToCborHex({
    required BigInt coin,
    required List<ConformanceAsset> assets,
  });

  // BigInt, not int: on web (dart2js) a Dart `int` is a float64, so an i64
  // Plutus integer like 0x112210f47de98115 would be silently rounded. BigInt
  // keeps it exact on every platform.
  String plutusDataInt(BigInt n);
  String plutusDataBytes(String hexData);
  String plutusDataConstr(BigInt constructor, List<String> fieldsCborHex);
  String plutusDataList(List<String> itemsCborHex);

  String assembleVkeyWitnessSet(List<ConformanceWitness> witnesses);

  ConformanceSignature signData({
    required String addressHex,
    required String payloadHex,
    required String signingKeyBech32,
  });

  bool verifyData({
    required String signature,
    required String key,
    String? expectedPayloadHex,
    String? expectedAddressHex,
  });

  /// CIP-8 message signing; returns the `COSE_Sign1` hex (deterministic).
  String signMessageCose({
    required String message,
    required String signingKeyBech32,
    String? address,
  });
}

/// One golden vector: an operation, its inputs (as JSON), and the expected
/// output string a conformant backend must produce.
class ConformanceCase {
  final String id;
  final String category;
  final String op;
  final Map<String, dynamic> input;
  final String expected;

  const ConformanceCase({
    required this.id,
    required this.category,
    required this.op,
    required this.input,
    required this.expected,
  });

  factory ConformanceCase.fromJson(Map<String, dynamic> j) => ConformanceCase(
        id: j['id'] as String,
        category: j['category'] as String,
        op: j['op'] as String,
        input: Map<String, dynamic>.from(j['input'] as Map),
        expected: j['expected'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'op': op,
        'input': input,
        'expected': expected,
      };

  /// A copy with [expected] replaced — used by the golden generator.
  ConformanceCase withExpected(String value) => ConformanceCase(
        id: id,
        category: category,
        op: op,
        input: input,
        expected: value,
      );
}

/// Parse a golden-vector JSON document into [ConformanceCase]s.
List<ConformanceCase> parseConformanceCases(String jsonText) {
  final list = jsonDecode(jsonText) as List<dynamic>;
  return list
      .map((e) => ConformanceCase.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList(growable: false);
}

/// Serialize [ConformanceCase]s back to a stable, pretty JSON document.
String encodeConformanceCases(List<ConformanceCase> cases) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(cases.map((c) => c.toJson()).toList())}\n';
}

/// Execute one [ConformanceCase] against [backend] and return the output string
/// to be compared against [ConformanceCase.expected].
///
/// This single dispatch table is what makes the suite backend-agnostic: the
/// native test and a future in-browser CML run drive the *same* cases through
/// the *same* runner — only the [backend] differs.
String runConformanceCase(ConformanceBackend backend, ConformanceCase c) {
  final i = c.input;
  switch (c.op) {
    case 'keyDerivation':
      final k = backend.deriveKeys(
        mnemonic: i['mnemonic'] as String,
        passphrase: i['passphrase'] as String? ?? '',
        accountIndex: i['accountIndex'] as int,
        isTestnet: i['isTestnet'] as bool? ?? true,
      );
      return '${k.paymentKeyHash}|${k.stakeKeyHash}';
    case 'deriveAddress':
      final a = backend.deriveAddress(
        accountKey: i['accountKey'] as String,
        role: i['role'] as int,
        index: i['index'] as int,
        networkId: i['networkId'] as int,
      );
      return '${a.address}|${a.paymentKeyHash}';
    case 'computeBaseAddress':
      return backend.computeBaseAddress(
        paymentKeyHashHex: i['paymentKeyHashHex'] as String,
        stakeKeyHashHex: i['stakeKeyHashHex'] as String,
        networkId: i['networkId'] as int,
      );
    case 'addressToHex':
      return backend.addressToHex(addressBech32: i['addressBech32'] as String);
    case 'valueToCbor':
      final assets = (i['assets'] as List<dynamic>)
          .map((e) => (
                policyId: e['policyId'] as String,
                assetName: e['assetName'] as String,
                quantity: BigInt.parse(e['quantity'] as String),
              ))
          .toList();
      return backend.valueToCborHex(
        coin: BigInt.parse(i['coin'] as String),
        assets: assets,
      );
    case 'plutusInt':
      // `n` is stored as a decimal STRING so it survives dart2js JSON parsing
      // (where a JSON number would be a lossy float64) — see plutusDataInt.
      return backend.plutusDataInt(BigInt.parse(i['n'] as String));
    case 'plutusBytes':
      return backend.plutusDataBytes(i['hexData'] as String);
    case 'plutusConstr':
      return backend.plutusDataConstr(
        BigInt.parse(i['constructor'] as String),
        (i['fieldsCborHex'] as List<dynamic>).cast<String>(),
      );
    case 'plutusList':
      return backend
          .plutusDataList((i['itemsCborHex'] as List<dynamic>).cast<String>());
    case 'witnessSet':
      final witnesses = (i['witnesses'] as List<dynamic>)
          .map((e) => (
                vkeyHex: e['vkeyHex'] as String,
                signatureHex: e['signatureHex'] as String,
              ))
          .toList();
      return backend.assembleVkeyWitnessSet(witnesses);
    case 'signData':
      final s = backend.signData(
        addressHex: i['addressHex'] as String,
        payloadHex: i['payloadHex'] as String,
        signingKeyBech32: i['signingKeyBech32'] as String,
      );
      return '${s.signature}|${s.key}';
    case 'verifyData':
      // Returns the boolean verdict as 'true'/'false' so it compares as a plain
      // golden string. A conformant backend must agree on accept AND reject.
      return backend
          .verifyData(
            signature: i['signature'] as String,
            key: i['key'] as String,
            expectedPayloadHex: i['expectedPayloadHex'] as String?,
            expectedAddressHex: i['expectedAddressHex'] as String?,
          )
          .toString();
    case 'signMessage':
      return backend.signMessageCose(
        message: i['message'] as String,
        signingKeyBech32: i['signingKeyBech32'] as String,
        address: i['address'] as String?,
      );
    default:
      throw ArgumentError('Unknown conformance op: ${c.op}');
  }
}
