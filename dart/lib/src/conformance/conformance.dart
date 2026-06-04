// Phase 6: CSL↔CML cross-backend conformance harness.
//
// The SDK has two serialization backends:
//   • native  — CSL via Rust FFI (iOS/Android/macOS/Linux/Windows)
//   • web      — CML via Dart JS interop (no Rust FFI on web; Rust→WASM is banned)
//
// For the two backends to be interchangeable behind one Dart API, the bytes they
// produce for the same input **must** be identical wherever the protocol requires
// canonical encoding (addresses, CBOR `Value`, `PlutusData`, witness sets, COSE).
//
// This file defines that contract as data + an executable runner:
//   • [ConformanceBackend]  — the scoped, deterministic subset both backends implement.
//   • [ConformanceCase]     — one (op, input, expected-output) golden vector.
//   • [runConformanceCase]  — dispatches a case against a backend, returns its output.
//   • [NativeConformanceBackend] — the CSL/FFI implementation.
//
// The golden vectors live in `test/conformance/golden_cbor.json`; the native
// backend generated them and the conformance test freezes them. A future
// [CmlWebBackend] (see `cml_web_backend.dart`) must reproduce the same outputs
// byte-for-byte — that is the Phase 6 web gate.
library;

import 'dart:convert';

import '../cip30.dart' as cip30;
import '../hardware.dart' as hw;
import '../message.dart' as msg;
import '../plutus.dart' as plutus;
import '../tx.dart' show NativeAsset, Value;
import '../wallet.dart' as wallet;

/// A native-asset entry used by [ConformanceBackend.valueToCborHex], expressed
/// with plain types so the interface never leaks a backend-specific class.
typedef ConformanceAsset = ({String policyId, String assetName, BigInt quantity});

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

  String plutusDataInt(int n);
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
      return backend.plutusDataInt(i['n'] as int);
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

/// The CSL-backed (Rust FFI) implementation. This is the reference backend that
/// produced the golden vectors; on native platforms it is always conformant by
/// construction. A web (CML-JS) backend is validated against the same vectors.
class NativeConformanceBackend implements ConformanceBackend {
  const NativeConformanceBackend();

  @override
  String get name => 'csl-ffi';

  @override
  ConformanceKeys deriveKeys({
    required String mnemonic,
    required String passphrase,
    required int accountIndex,
    required bool isTestnet,
  }) {
    final k = wallet.deriveKeysFromMnemonic(
      mnemonic: mnemonic,
      passphrase: passphrase,
      accountIndex: accountIndex,
      isTestnet: isTestnet,
    );
    return (
      accountKey: k.accountKey,
      paymentKeyHash: k.paymentKeyHash,
      stakeKeyHash: k.stakeKeyHash,
      paymentSigningKey: k.paymentSigningKey,
      stakeSigningKey: k.stakeSigningKey,
    );
  }

  @override
  ConformanceAddress deriveAddress({
    required String accountKey,
    required int role,
    required int index,
    required int networkId,
  }) {
    final a = wallet.deriveAddress(
      accountKey: accountKey,
      role: role,
      index: index,
      networkId: networkId,
    );
    return (address: a.address, paymentKeyHash: a.paymentKeyHash);
  }

  @override
  String computeBaseAddress({
    required String paymentKeyHashHex,
    required String stakeKeyHashHex,
    required int networkId,
  }) =>
      cip30.computeBaseAddress(
        paymentKeyHashHex: paymentKeyHashHex,
        stakeKeyHashHex: stakeKeyHashHex,
        networkId: networkId,
      );

  @override
  String addressToHex({required String addressBech32}) =>
      cip30.addressToHex(addressBech32: addressBech32);

  @override
  String valueToCborHex({
    required BigInt coin,
    required List<ConformanceAsset> assets,
  }) =>
      cip30.valueToCborHex(
        value: Value(
          coin: coin,
          assets: assets
              .map((a) => NativeAsset(
                    policyId: a.policyId,
                    assetName: a.assetName,
                    quantity: a.quantity,
                  ))
              .toList(),
        ),
      );

  @override
  String plutusDataInt(int n) => plutus.plutusDataInt(n: n);

  @override
  String plutusDataBytes(String hexData) =>
      plutus.plutusDataBytes(hexData: hexData);

  @override
  String plutusDataConstr(BigInt constructor, List<String> fieldsCborHex) =>
      plutus.plutusDataConstr(
          constructor: constructor, fieldsCborHex: fieldsCborHex);

  @override
  String plutusDataList(List<String> itemsCborHex) =>
      plutus.plutusDataList(itemsCborHex: itemsCborHex);

  @override
  String assembleVkeyWitnessSet(List<ConformanceWitness> witnesses) =>
      hw.assembleVkeyWitnessSet(
        witnesses: witnesses
            .map((w) => hw.HardwareVkeyWitness(
                  vkeyHex: w.vkeyHex,
                  signatureHex: w.signatureHex,
                ))
            .toList(),
      );

  @override
  ConformanceSignature signData({
    required String addressHex,
    required String payloadHex,
    required String signingKeyBech32,
  }) {
    final s = cip30.cip30SignData(
      addressHex: addressHex,
      payloadHex: payloadHex,
      signingKeyBech32: signingKeyBech32,
    );
    return (signature: s.signature, key: s.key);
  }

  @override
  bool verifyData({
    required String signature,
    required String key,
    String? expectedPayloadHex,
  }) =>
      cip30.cip30VerifyData(
        dataSignature: cip30.DataSignature(signature: signature, key: key),
        expectedPayloadHex: expectedPayloadHex,
      );

  @override
  String signMessageCose({
    required String message,
    required String signingKeyBech32,
    String? address,
  }) =>
      msg
          .signMessage(
            message: message,
            signingKeyBech32: signingKeyBech32,
            address: address,
          )
          .coseSign1Hex;
}
