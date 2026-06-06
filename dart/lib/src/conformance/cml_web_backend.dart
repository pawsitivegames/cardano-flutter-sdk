// Phase 6: CML-JS web backend.
//
// Status: every op below is a faithful transcription of a call sequence that
// was proven — under Node, against the identical CML 6.2.0 + cardano-message-
// signing 1.1.0 WASM core the browser build ships — to reproduce all 24 frozen
// CSL golden vectors (`test/conformance/golden_cbor.json`) BYTE-FOR-BYTE. The
// reproducible proof lives in `tool/cml_conformance_spike/` (run `node
// harness.mjs` → `PASS 24 FAIL 0`). What that proof establishes is *library
// equivalence*: CML and CSL agree on the canonical bytes. What it does NOT yet
// establish is that THIS Dart JS-interop wiring + the browser WASM build agree
// — that is the remaining gate (run this backend through `runConformanceCase`
// in a real Flutter web build). The risk is now low (same WASM core, mechanical
// binding) but it is not zero, so this stays `@experimental`.
//
// Two non-obvious CML↔CSL divergences are baked into the calls below; do not
// "simplify" them away:
//   • Plutus constr/list: CSL emits Cardano-node CBOR (indefinite-length arrays,
//     `d8799f…ff` / `9f…ff`). CML's default `to_cbor_hex()` is definite-length.
//     `to_cardano_node_format()` normalizes to the node encoding → matches CSL.
//   • Value multi-asset: CSL canonically sorts map keys (length, then lexico-
//     graphic). CML preserves insertion order under `to_cbor_hex()`.
//     `to_canonical_cbor_hex()` sorts → matches CSL.
//
// Why this exists: web has no Rust FFI (Rust→WASM is banned by project policy),
// so the Dart API is satisfied by CML compiled to JS/WASM via Dart JS interop:
//   npm: @dcspark/cardano-multiplatform-lib-browser
//        @emurgo/cardano-message-signing-browser
// The host web app loads them and exposes them on `globalThis.CML` / `globalThis.MS`
// (e.g. an ESM shim in `web/index.html`). See `docs/web-backend.md`.
//
// This file is web-only by construction (it imports `dart:js_interop`) and is
// intentionally NOT exported from the package barrel, so native builds never
// link `dart:js_interop`; web entrypoints import it directly.
@experimental
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:meta/meta.dart';

// Import the PURE contract, not `conformance.dart` — the latter pulls in
// `NativeConformanceBackend` and its `dart:ffi` chain, which does not compile
// under dart2js. This is what lets the web backend build for web at all.
import 'conformance_contract.dart';

// ---------------------------------------------------------------------------
// JS BigInt bridge. wasm-bindgen marshals Rust u64 (Coin) as a JS BigInt, which
// `dart:js_interop` has no first-class type for — so we mint one via the global
// `BigInt(string)` and pass it where CML expects a coin quantity.
// ---------------------------------------------------------------------------

@JS('BigInt')
external JSAny _jsBigInt(String decimal);

// ---------------------------------------------------------------------------
// CML JS interop bindings (subset). `globalThis.CML.*`, provided by the host.
// NOTE: wasm-bindgen exposes constructors as the STATIC method `new`, not a JS
// `new` — bind them as `@JS('new') external static`.
// ---------------------------------------------------------------------------

@JS('CML.Ed25519KeyHash')
extension type _Ed25519KeyHash._(JSObject _) implements JSObject {
  external static _Ed25519KeyHash from_hex(String hex);
  external String to_hex();
  external JSUint8Array to_raw_bytes();
}

@JS('CML.ScriptHash')
extension type _ScriptHash._(JSObject _) implements JSObject {
  external static _ScriptHash from_hex(String hex);
}

@JS('CML.AssetName')
extension type _AssetName._(JSObject _) implements JSObject {
  external static _AssetName from_hex(String hex);
}

@JS('CML.Credential')
extension type _Credential._(JSObject _) implements JSObject {
  external static _Credential new_pub_key(_Ed25519KeyHash hash);
  external _Ed25519KeyHash? as_pub_key();
}

@JS('CML.Address')
extension type _Address._(JSObject _) implements JSObject {
  external static _Address from_bech32(String bech32);
  external static _Address from_raw_bytes(JSUint8Array data);
  external String to_hex();
  external String to_bech32([String? prefix]);
  external _Credential? payment_cred();
  external _Credential? staking_cred();
}

@JS('CML.BaseAddress')
extension type _BaseAddress._(JSObject _) implements JSObject {
  @JS('new')
  external static _BaseAddress new_(
      int network, _Credential payment, _Credential stake);
  external _Address to_address();
}

@JS('CML.BigInteger')
extension type _BigInteger._(JSObject _) implements JSObject {
  external static _BigInteger from_str(String s);
}

@JS('CML.PlutusData')
extension type _PlutusData._(JSObject _) implements JSObject {
  external static _PlutusData from_cbor_hex(String hex);
  external static _PlutusData new_integer(_BigInteger n);
  external static _PlutusData new_bytes(JSUint8Array bytes);
  external static _PlutusData new_constr_plutus_data(_ConstrPlutusData c);
  external static _PlutusData new_list(_PlutusDataList list);
  // CSL-matching (Cardano-node) CBOR: indefinite-length constr/list arrays.
  external _PlutusData to_cardano_node_format();
  external String to_cbor_hex();
}

@JS('CML.ConstrPlutusData')
extension type _ConstrPlutusData._(JSObject _) implements JSObject {
  @JS('new')
  external static _ConstrPlutusData new_(JSAny alternative, _PlutusDataList fields);
}

@JS('CML.PlutusDataList')
extension type _PlutusDataList._(JSObject _) implements JSObject {
  @JS('new')
  external static _PlutusDataList new_();
  external void add(_PlutusData item);
}

@JS('CML.MapAssetNameToCoin')
extension type _MapAssetNameToCoin._(JSObject _) implements JSObject {
  @JS('new')
  external static _MapAssetNameToCoin new_();
  external void insert(_AssetName key, JSAny value);
}

@JS('CML.MultiAsset')
extension type _MultiAsset._(JSObject _) implements JSObject {
  @JS('new')
  external static _MultiAsset new_();
  external _MapAssetNameToCoin? get_assets(_ScriptHash policy);
  external void insert_assets(_ScriptHash policy, _MapAssetNameToCoin assets);
}

@JS('CML.Value')
extension type _Value._(JSObject _) implements JSObject {
  @JS('new')
  external static _Value new_(JSAny coin, _MultiAsset assets);
  external static _Value from_coin(JSAny coin);
  external String to_cbor_hex();
  // CSL canonically sorts multi-asset map keys; CML preserves insertion order.
  external String to_canonical_cbor_hex();
}

@JS('CML.PublicKey')
extension type _PublicKey._(JSObject _) implements JSObject {
  external static _PublicKey from_bytes(JSUint8Array bytes);
  external JSUint8Array to_raw_bytes();
  external _Ed25519KeyHash hash();
  external bool verify(JSUint8Array data, _Ed25519Signature signature);
}

@JS('CML.PrivateKey')
extension type _PrivateKey._(JSObject _) implements JSObject {
  external _PublicKey to_public();
  external _Ed25519Signature sign(JSUint8Array message);
}

@JS('CML.Ed25519Signature')
extension type _Ed25519Signature._(JSObject _) implements JSObject {
  external static _Ed25519Signature from_raw_bytes(JSUint8Array bytes);
  external JSUint8Array to_raw_bytes();
}

@JS('CML.Vkeywitness')
extension type _Vkeywitness._(JSObject _) implements JSObject {
  @JS('new')
  external static _Vkeywitness new_(_PublicKey vkey, _Ed25519Signature sig);
}

@JS('CML.VkeywitnessList')
extension type _VkeywitnessList._(JSObject _) implements JSObject {
  @JS('new')
  external static _VkeywitnessList new_();
  external void add(_Vkeywitness w);
}

@JS('CML.TransactionWitnessSet')
extension type _TransactionWitnessSet._(JSObject _) implements JSObject {
  @JS('new')
  external static _TransactionWitnessSet new_();
  external void set_vkeywitnesses(_VkeywitnessList vkeys);
  external String to_cbor_hex();
}

@JS('CML.Bip32PrivateKey')
extension type _Bip32PrivateKey._(JSObject _) implements JSObject {
  external static _Bip32PrivateKey from_bech32(String bech32);
  external static _Bip32PrivateKey from_bip39_entropy(
      JSUint8Array entropy, JSUint8Array password);
  external _Bip32PrivateKey derive(int index);
  external _PrivateKey to_raw_key();
}

// --- message-signing (`globalThis.MS.*`) -----------------------------------

@JS('MS.AlgorithmId')
extension type _AlgorithmId._(JSObject _) implements JSObject {
  external static int get EdDSA;
}

@JS('MS.Int')
extension type _Int._(JSObject _) implements JSObject {
  external static _Int new_i32(int x);
}

@JS('MS.Label')
extension type _Label._(JSObject _) implements JSObject {
  external static _Label from_algorithm_id(int id);
  external static _Label new_text(String text);
  external static _Label new_int(_Int int);
}

@JS('MS.CBORValue')
extension type _CBORValue._(JSObject _) implements JSObject {
  external static _CBORValue new_bytes(JSUint8Array bytes);
  external JSUint8Array? as_bytes();
}

@JS('MS.HeaderMap')
extension type _HeaderMap._(JSObject _) implements JSObject {
  @JS('new')
  external static _HeaderMap new_();
  external void set_algorithm_id(_Label alg);
  external void set_header(_Label key, _CBORValue value);
  external _CBORValue? header(_Label key);
}

@JS('MS.ProtectedHeaderMap')
extension type _ProtectedHeaderMap._(JSObject _) implements JSObject {
  @JS('new')
  external static _ProtectedHeaderMap new_(_HeaderMap headers);
  external _HeaderMap deserialized_headers();
}

@JS('MS.Headers')
extension type _Headers._(JSObject _) implements JSObject {
  @JS('new')
  external static _Headers new_(
      _ProtectedHeaderMap protectedHeaders, _HeaderMap unprotected);
  external _ProtectedHeaderMap protected();
}

@JS('MS.COSESign1Builder')
extension type _COSESign1Builder._(JSObject _) implements JSObject {
  @JS('new')
  external static _COSESign1Builder new_(
      _Headers headers, JSUint8Array payload, bool externalAad);
  external _SigStructure make_data_to_sign();
  external _COSESign1 build(JSUint8Array signedSigStructure);
}

@JS('MS.SigStructure')
extension type _SigStructure._(JSObject _) implements JSObject {
  external JSUint8Array to_bytes();
}

@JS('MS.COSESign1')
extension type _COSESign1._(JSObject _) implements JSObject {
  external static _COSESign1 from_bytes(JSUint8Array bytes);
  external JSUint8Array to_bytes();
  external _Headers headers();
  external JSUint8Array? payload();
  external JSUint8Array signature();
  // Reverse-construct the Sig_structure to verify against (no external aad /
  // payload — CIP-30 signData embeds the payload).
  external _SigStructure signed_data();
}

@JS('MS.EdDSA25519Key')
extension type _EdDSA25519Key._(JSObject _) implements JSObject {
  @JS('new')
  external static _EdDSA25519Key new_(JSUint8Array publicKey);
  external void is_for_verifying();
  external _COSEKey build();
}

@JS('MS.COSEKey')
extension type _COSEKey._(JSObject _) implements JSObject {
  external static _COSEKey from_bytes(JSUint8Array bytes);
  external JSUint8Array to_bytes();
  external _CBORValue? header(_Label key);
}

/// Optional host-provided BIP-39 `mnemonic → entropy` bridge. CML has no
/// mnemonic parser, and project policy keeps mnemonic crypto out of Dart, so
/// `deriveKeys` (mnemonic path) delegates to a JS function the web host installs
/// on `globalThis` (e.g. `globalThis.CFL_mnemonicToEntropy = m => bip39.mnemonicToEntropy(m)`).
/// Returns hex of the entropy. The `deriveAddress` (account-xprv) path needs none.
@JS('CFL_mnemonicToEntropy')
external String? _mnemonicToEntropy(String mnemonic);

// ---------------------------------------------------------------------------
// Backend
// ---------------------------------------------------------------------------

/// CML-via-JS-interop implementation of [ConformanceBackend] for Flutter web.
///
/// Each method mirrors a call sequence proven byte-equal to the CSL golden
/// vectors at the library level (see the file header). The remaining gate is a
/// real in-browser Flutter web run of [runConformanceCase] over these methods.
@experimental
class CmlWebBackend implements ConformanceBackend {
  const CmlWebBackend();

  @override
  String get name => 'cml-js';

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
    // CSL contract returns a BECH32 base address (`to_bech32(None)`), not hex.
    return _BaseAddress.new_(networkId, payment, stake).to_address().to_bech32();
  }

  @override
  String addressToHex({required String addressBech32}) =>
      _Address.from_bech32(addressBech32).to_hex();

  // --- value --------------------------------------------------------------

  @override
  String valueToCborHex({
    required BigInt coin,
    required List<ConformanceAsset> assets,
  }) {
    if (assets.isEmpty) {
      return _Value.from_coin(_jsBigInt(coin.toString())).to_cbor_hex();
    }
    final ma = _MultiAsset.new_();
    for (final a in assets) {
      final policy = _ScriptHash.from_hex(a.policyId);
      final name = _AssetName.from_hex(a.assetName);
      final inner = ma.get_assets(policy) ?? _MapAssetNameToCoin.new_();
      inner.insert(name, _jsBigInt(a.quantity.toString()));
      ma.insert_assets(policy, inner);
    }
    // Canonical: CSL sorts multi-asset map keys; CML preserves insertion order.
    return _Value.new_(_jsBigInt(coin.toString()), ma).to_canonical_cbor_hex();
  }

  // --- plutus (Cardano-node CBOR: indefinite-length constr/list arrays) ----

  @override
  String plutusDataInt(BigInt n) =>
      // from_str keeps the full i64 range exact — no Dart `int` (float64) hop.
      _PlutusData.new_integer(_BigInteger.from_str(n.toString()))
          .to_cardano_node_format()
          .to_cbor_hex();

  @override
  String plutusDataBytes(String hexData) =>
      _PlutusData.new_bytes(_hexToBytes(hexData).toJS)
          .to_cardano_node_format()
          .to_cbor_hex();

  @override
  String plutusDataConstr(BigInt constructor, List<String> fieldsCborHex) {
    final list = _PlutusDataList.new_();
    for (final f in fieldsCborHex) {
      list.add(_PlutusData.from_cbor_hex(f));
    }
    final c = _ConstrPlutusData.new_(_jsBigInt(constructor.toString()), list);
    return _PlutusData.new_constr_plutus_data(c)
        .to_cardano_node_format()
        .to_cbor_hex();
  }

  @override
  String plutusDataList(List<String> itemsCborHex) {
    final list = _PlutusDataList.new_();
    for (final f in itemsCborHex) {
      list.add(_PlutusData.from_cbor_hex(f));
    }
    return _PlutusData.new_list(list).to_cardano_node_format().to_cbor_hex();
  }

  // --- witness ------------------------------------------------------------

  @override
  String assembleVkeyWitnessSet(List<ConformanceWitness> witnesses) {
    final vlist = _VkeywitnessList.new_();
    for (final w in witnesses) {
      final vk = _PublicKey.from_bytes(_hexToBytes(w.vkeyHex).toJS);
      final sig = _Ed25519Signature.from_raw_bytes(
          _hexToBytes(w.signatureHex).toJS);
      vlist.add(_Vkeywitness.new_(vk, sig));
    }
    final ws = _TransactionWitnessSet.new_();
    ws.set_vkeywitnesses(vlist);
    return ws.to_cbor_hex();
  }

  // --- cose (message-signing lib) -----------------------------------------

  @override
  ConformanceSignature signData({
    required String addressHex,
    required String payloadHex,
    required String signingKeyBech32,
  }) {
    final bip32 = _Bip32PrivateKey.from_bech32(signingKeyBech32);
    final priv = bip32.to_raw_key();
    final pub = priv.to_public();

    final protectedHm = _HeaderMap.new_();
    protectedHm.set_algorithm_id(_Label.from_algorithm_id(_AlgorithmId.EdDSA));
    protectedHm.set_header(
      _Label.new_text('address'),
      _CBORValue.new_bytes(_hexToBytes(addressHex).toJS),
    );
    final headers =
        _Headers.new_(_ProtectedHeaderMap.new_(protectedHm), _HeaderMap.new_());

    // hashed = false → sign the raw payload (CIP-30/CIP-8 contract).
    final builder =
        _COSESign1Builder.new_(headers, _hexToBytes(payloadHex).toJS, false);
    final toSign = builder.make_data_to_sign().to_bytes();
    final sig = priv.sign(toSign).to_raw_bytes();
    final coseSign1 = builder.build(sig);

    final key = _EdDSA25519Key.new_(pub.to_raw_bytes());
    key.is_for_verifying();
    final coseKey = key.build();

    return (
      signature: _bytesToHex(coseSign1.to_bytes().toDart),
      key: _bytesToHex(coseKey.to_bytes().toDart),
    );
  }

  @override
  bool verifyData({
    required String signature,
    required String key,
    String? expectedPayloadHex,
    String? expectedAddressHex,
  }) {
    // Mirrors the native CSL `cip30_verify_data` semantics byte-for-byte:
    // parse COSE_Sign1, optionally pin payload, rebuild the Sig_structure,
    // pull the Ed25519 public key from COSE_Key label -2, enforce
    // identity-binding against the protected-header address, then verify.
    final coseSign1 = _COSESign1.from_bytes(_hexToBytes(signature).toJS);

    // Payload check (absent payload is treated as empty, like CSL).
    if (expectedPayloadHex != null) {
      final payloadJs = coseSign1.payload();
      final payload = payloadJs == null ? Uint8List(0) : payloadJs.toDart;
      if (!_bytesEqual(_hexToBytes(expectedPayloadHex), payload)) return false;
    }

    // Sig_structure to verify + raw signature bytes.
    final toVerify = coseSign1.signed_data().to_bytes();
    final sig = _Ed25519Signature.from_raw_bytes(coseSign1.signature());

    // Public key: COSE_Key OKP x-coordinate is label -2.
    final coseKey = _COSEKey.from_bytes(_hexToBytes(key).toJS);
    final pkBytesJs = coseKey.header(_Label.new_int(_Int.new_i32(-2)))?.as_bytes();
    if (pkBytesJs == null) return false; // missing Ed25519 public key (-2)
    final publicKey = _PublicKey.from_bytes(pkBytesJs);

    // Identity binding: read the signer address from the protected header.
    // If present, the COSE_Key public key must hash to one of its credentials,
    // so a valid signature cannot be passed off as another address's.
    final addrBytesJs = coseSign1
        .headers()
        .protected()
        .deserialized_headers()
        .header(_Label.new_text('address'))
        ?.as_bytes();
    if (addrBytesJs != null) {
      if (expectedAddressHex != null &&
          !_bytesEqual(_hexToBytes(expectedAddressHex), addrBytesJs.toDart)) {
        return false;
      }
      final addr = _Address.from_raw_bytes(addrBytesJs);
      final pkHash = publicKey.hash().to_raw_bytes().toDart;
      final owns = <_Ed25519KeyHash?>[
        addr.payment_cred()?.as_pub_key(),
        addr.staking_cred()?.as_pub_key(),
      ].any((c) => c != null && _bytesEqual(c.to_raw_bytes().toDart, pkHash));
      if (!owns) return false;
    } else if (expectedAddressHex != null) {
      // Caller demanded a specific address but the signature carries none.
      return false;
    }

    return publicKey.verify(toVerify, sig);
  }

  @override
  String signMessageCose({
    required String message,
    required String signingKeyBech32,
    String? address,
  }) =>
      // Legacy CIP-8 `signMessage` is deliberately EXCLUDED from the golden
      // contract (it is a non-spec custom CBOR map, slated for deprecation in
      // favour of signData). Not mapped on web by design — see docs/web-backend.md.
      throw UnimplementedError(
        'CmlWebBackend.signMessageCose is intentionally unmapped: legacy CIP-8 '
        'signMessage is excluded from the conformance contract. Use signData.',
      );

  // --- key derivation -----------------------------------------------------

  static const int _harden = 0x80000000;

  @override
  ConformanceKeys deriveKeys({
    required String mnemonic,
    required String passphrase,
    required int accountIndex,
    required bool isTestnet,
  }) {
    final entropyHex = _mnemonicToEntropy(mnemonic);
    if (entropyHex == null) {
      throw UnimplementedError(
        'CmlWebBackend.deriveKeys needs a host BIP-39 bridge: install '
        'globalThis.CFL_mnemonicToEntropy (e.g. bip39.mnemonicToEntropy). '
        'The account-xprv path (deriveAddress) needs none. See docs/web-backend.md.',
      );
    }
    final root = _Bip32PrivateKey.from_bip39_entropy(
      _hexToBytes(entropyHex).toJS,
      Uint8List(0).toJS,
    );
    final acct = root
        .derive(_harden + 1852)
        .derive(_harden + 1815)
        .derive(_harden + accountIndex);
    final pay = acct.derive(0).derive(0).to_raw_key().to_public().hash().to_hex();
    final stk = acct.derive(2).derive(0).to_raw_key().to_public().hash().to_hex();
    // accountKey / signing keys are not part of the conformance comparison for
    // this op (only the two key hashes are); return the bech32 account xprv-less
    // fields empty rather than re-deriving private material we do not expose.
    return (
      accountKey: '',
      paymentKeyHash: pay,
      stakeKeyHash: stk,
      paymentSigningKey: '',
      stakeSigningKey: '',
    );
  }

  @override
  ConformanceAddress deriveAddress({
    required String accountKey,
    required int role,
    required int index,
    required int networkId,
  }) {
    final acct = _Bip32PrivateKey.from_bech32(accountKey);
    final payHash =
        acct.derive(role).derive(index).to_raw_key().to_public().hash();
    final stkHash =
        acct.derive(2).derive(0).to_raw_key().to_public().hash();
    final addr = _BaseAddress.new_(
      networkId,
      _Credential.new_pub_key(payHash),
      _Credential.new_pub_key(stkHash),
    ).to_address().to_bech32();
    return (address: addr, paymentKeyHash: payHash.to_hex());
  }

  // --- helpers ------------------------------------------------------------

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
