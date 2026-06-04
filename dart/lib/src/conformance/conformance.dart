// Phase 6: CSL↔CML cross-backend conformance harness — native backend.
//
// The SDK has two serialization backends:
//   • native  — CSL via Rust FFI (iOS/Android/macOS/Linux/Windows)
//   • web      — CML via Dart JS interop (no Rust FFI on web; Rust→WASM is banned)
//
// For the two backends to be interchangeable behind one Dart API, the bytes they
// produce for the same input **must** be identical wherever the protocol requires
// canonical encoding (addresses, CBOR `Value`, `PlutusData`, witness sets, COSE).
//
// The shared, **platform-agnostic** contract — [ConformanceBackend],
// [ConformanceCase], [runConformanceCase] — lives in `conformance_contract.dart`
// (pure Dart, no FFI / no `dart:js_interop`) and is re-exported below so existing
// consumers keep importing it from here. This file adds the CSL/FFI reference
// backend, which is **native-only** (it imports `dart:ffi` transitively).
//
// The golden vectors live in `test/conformance/golden_cbor.json`; this native
// backend generated them and `test/conformance_test.dart` freezes them.
// `CmlWebBackend` (see `cml_web_backend.dart`) reproduces the same outputs — that
// is the Phase 6 web gate.
library;

import '../cip30.dart' as cip30;
import '../hardware.dart' as hw;
import '../message.dart' as msg;
import '../plutus.dart' as plutus;
import '../tx.dart' show NativeAsset, Value;
import '../wallet.dart' as wallet;

import 'conformance_contract.dart';

export 'conformance_contract.dart';

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
  String plutusDataInt(BigInt n) => plutus.plutusDataInt(n: n.toInt());

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
    String? expectedAddressHex,
  }) =>
      cip30.cip30VerifyData(
        dataSignature: cip30.DataSignature(signature: signature, key: key),
        expectedPayloadHex: expectedPayloadHex,
        expectedAddressHex: expectedAddressHex,
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
