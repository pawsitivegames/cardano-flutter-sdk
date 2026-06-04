// Phase 6: CML-JS web backend (SCAFFOLD — browser-verify PENDING).
//
// ⚠️  HONESTY NOTICE: none of the code in this file has executed in a browser
//     yet. It is the architectural seam for the web backend, not a verified
//     implementation. The acceptance gate is the golden-CBOR conformance suite
//     (`conformance.dart` + `test/conformance/golden_cbor.json`): a method is
//     only "done" once it reproduces the frozen native vectors byte-for-byte
//     when driven through `runConformanceCase` in a real browser. Methods whose
//     CML mapping is not yet pinned down throw [UnimplementedError] rather than
//     return plausible-but-unverified bytes — failing loud beats failing silent.
//
// Why this exists: web has no Rust FFI (Rust→WASM is banned by project policy),
// so the Dart API must be satisfied by **CML compiled to JS/WASM** via Dart JS
// interop. This binds the browser build of CML:
//   npm: @dcspark/cardano-multiplatform-lib-browser
// The host web app is expected to load it and expose it on `globalThis.CML`
// (e.g. via an ESM shim in `web/index.html`). See `docs/web-backend.md`.
//
// This file is web-only by construction (it imports `dart:js_interop`). It is
// intentionally NOT exported from the package barrel so native consumers never
// link it; web entrypoints import it directly.
@experimental
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'conformance.dart';

// ---------------------------------------------------------------------------
// CML JS interop bindings (subset). `globalThis.CML.*`, provided by the host.
// ---------------------------------------------------------------------------

@JS('CML.Ed25519KeyHash')
extension type _Ed25519KeyHash._(JSObject _) implements JSObject {
  external static _Ed25519KeyHash from_hex(String hex);
}

@JS('CML.Credential')
extension type _Credential._(JSObject _) implements JSObject {
  external static _Credential new_pub_key(_Ed25519KeyHash hash);
}

@JS('CML.Address')
extension type _Address._(JSObject _) implements JSObject {
  external static _Address from_bech32(String bech32);
  external String to_hex();
  external String to_bech32([String? prefix]);
}

@JS('CML.BaseAddress')
extension type _BaseAddress._(JSObject _) implements JSObject {
  external factory _BaseAddress(
      int network, _Credential payment, _Credential stake);
  external _Address to_address();
}

@JS('CML.BigInteger')
extension type _BigInteger._(JSObject _) implements JSObject {
  external static _BigInteger from_str(String s);
}

@JS('CML.PlutusData')
extension type _PlutusData._(JSObject _) implements JSObject {
  external static _PlutusData new_integer(_BigInteger n);
  external static _PlutusData new_bytes(JSUint8Array bytes);
  external String to_cbor_hex();
}

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

/// CML-via-JS-interop implementation of [ConformanceBackend] for Flutter web.
///
/// SCAFFOLD: see the file header. Verified methods reproduce the golden vectors
/// in a browser; unverified methods throw [UnimplementedError].
@experimental
class CmlWebBackend implements ConformanceBackend {
  const CmlWebBackend();

  @override
  String get name => 'cml-js';

  static Never _pending(String what, String cmlHint) => throw UnimplementedError(
        'CmlWebBackend.$what is browser-verify pending. '
        'Map via CML ($cmlHint), then validate against golden_cbor.json '
        'in a real browser before claiming parity. See docs/web-backend.md.',
      );

  // --- address ------------------------------------------------------------

  @override
  String computeBaseAddress({
    required String paymentKeyHashHex,
    required String stakeKeyHashHex,
    required int networkId,
  }) {
    final payment =
        _Credential.new_pub_key(_Ed25519KeyHash.from_hex(paymentKeyHashHex));
    final stake =
        _Credential.new_pub_key(_Ed25519KeyHash.from_hex(stakeKeyHashHex));
    // The native contract returns a BECH32 base address (CSL `to_bech32(None)`),
    // NOT hex — return bech32 here too or this can never pass conformance. The
    // bech32 HRP/network mapping must still match CSL exactly; the conformance
    // gate is what proves it. Do not trust this until it passes in a browser.
    return _BaseAddress(networkId, payment, stake).to_address().to_bech32();
  }

  @override
  String addressToHex({required String addressBech32}) =>
      _Address.from_bech32(addressBech32).to_hex();

  // --- value --------------------------------------------------------------

  @override
  String valueToCborHex({
    required BigInt coin,
    required List<ConformanceAsset> assets,
  }) =>
      _pending('valueToCborHex',
          'Value.new(BigNum, MultiAsset) — multiasset ordering must match CSL');

  // --- plutus -------------------------------------------------------------

  @override
  String plutusDataInt(int n) =>
      _PlutusData.new_integer(_BigInteger.from_str(n.toString())).to_cbor_hex();

  @override
  String plutusDataBytes(String hexData) {
    final bytes = _hexToBytes(hexData);
    return _PlutusData.new_bytes(bytes.toJS).to_cbor_hex();
  }

  @override
  String plutusDataConstr(BigInt constructor, List<String> fieldsCborHex) =>
      _pending('plutusDataConstr',
          'ConstrPlutusData.new(BigNum, PlutusList) + PlutusData.new_constr_plutus_data');

  @override
  String plutusDataList(List<String> itemsCborHex) => _pending(
      'plutusDataList', 'PlutusList.new()/.add + PlutusData.new_list');

  // --- witness ------------------------------------------------------------

  @override
  String assembleVkeyWitnessSet(List<ConformanceWitness> witnesses) => _pending(
      'assembleVkeyWitnessSet',
      'Vkeywitness.new(Vkey, Ed25519Signature) into a TransactionWitnessSet');

  // --- cose (needs the message-signing lib, not CML core) -----------------

  @override
  ConformanceSignature signData({
    required String addressHex,
    required String payloadHex,
    required String signingKeyBech32,
  }) =>
      _pending('signData',
          '@emurgo/cardano-message-signing-browser COSE_Sign1 + COSE_Key');

  @override
  bool verifyData({
    required String signature,
    required String key,
    String? expectedPayloadHex,
  }) =>
      _pending('verifyData', '@emurgo/cardano-message-signing-browser');

  @override
  String signMessageCose({
    required String message,
    required String signingKeyBech32,
    String? address,
  }) =>
      _pending('signMessageCose',
          '@emurgo/cardano-message-signing-browser (Blake2b-256 + EdDSA)');

  // --- key derivation -----------------------------------------------------

  @override
  ConformanceKeys deriveKeys({
    required String mnemonic,
    required String passphrase,
    required int accountIndex,
    required bool isTestnet,
  }) =>
      _pending('deriveKeys',
          'Bip32PrivateKey.from_bip39_entropy + CIP-1852 path 1852H/1815H/accountH');

  @override
  ConformanceAddress deriveAddress({
    required String accountKey,
    required int role,
    required int index,
    required int networkId,
  }) =>
      _pending('deriveAddress',
          'Bip32PrivateKey.derive(role).derive(index) → BaseAddress');

  // --- helpers ------------------------------------------------------------

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
