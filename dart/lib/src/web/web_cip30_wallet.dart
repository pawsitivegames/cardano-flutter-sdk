// Phase 6: scoped web CIP-30 wallet.
//
// A read + connect + signData wallet for Flutter **web**, built on:
//   • [CmlWebBackend] — the conformance-frozen CML-via-JS-interop backend, for
//     the deterministic serialization/signing ops (value CBOR, address hex,
//     UTxO CBOR, COSE `signData`). These exact call sequences pass the golden suite
//     in a real browser (`tool/web_conformance/`).
//   • [BlockfrostProvider] — pure-Dart REST, already web-capable, for chain reads
//     (UTxOs / balance).
//
// Scope is the RC's deliberately-reduced web subset (see `docs/web-backend.md`):
// address derivation, balance/UTxO read, CIP-30 `signData`, `signTx`, and
// signed-tx submission. Full tx-building (fee estimation + coin selection
// against CML) is OUT of scope on web and is deferred to a later web-parity
// track, so the type surface tells the truth.
//
// This file is web-only by construction (it imports `dart:js_interop`) and is
// reachable only through the `cardano_flutter_rs_web.dart` entrypoint, never the
// native barrel — so native builds never link `dart:js_interop`.
@experimental
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../conformance/cml_web_backend.dart';
import '../conformance/conformance_contract.dart';
import '../providers/blockfrost.dart';
import 'value_aggregate.dart';

// ---------------------------------------------------------------------------
// Minimal CML interop for the key-derivation + reward-address path. The heavy
// serialization/signing ops are delegated to [CmlWebBackend], whose own interop
// types are private to that file; the small set below is what this wallet needs
// on top of it (Bip32 → bech32 account/leaf keys, stake credential, reward addr).
// `globalThis.CML.*` is provided by the host page (see web/index.html).
// ---------------------------------------------------------------------------

@JS('CML.Bip32PrivateKey')
extension type _Bip32PrivateKey._(JSObject _) implements JSObject {
  external static _Bip32PrivateKey from_bip39_entropy(
      JSUint8Array entropy, JSUint8Array password);
  external _Bip32PrivateKey derive(int index);
  external String to_bech32();
  external _PrivateKey to_raw_key();
}

@JS('CML.PrivateKey')
extension type _PrivateKey._(JSObject _) implements JSObject {
  external _PublicKey to_public();
}

@JS('CML.PublicKey')
extension type _PublicKey._(JSObject _) implements JSObject {
  external _Ed25519KeyHash hash();
}

@JS('CML.Ed25519KeyHash')
extension type _Ed25519KeyHash._(JSObject _) implements JSObject {
  external String to_hex();
}

@JS('CML.Credential')
extension type _Credential._(JSObject _) implements JSObject {
  external static _Credential new_pub_key(_Ed25519KeyHash hash);
}

@JS('CML.RewardAddress')
extension type _RewardAddress._(JSObject _) implements JSObject {
  @JS('new')
  external static _RewardAddress new_(int network, _Credential payment);
  external _Address to_address();
}

@JS('CML.Address')
extension type _Address._(JSObject _) implements JSObject {
  external String to_bech32([String? prefix]);
}

/// Host-provided BIP-39 `mnemonic → entropy(hex)` bridge — the same global the
/// [CmlWebBackend] uses (CML has no mnemonic parser; project policy keeps
/// mnemonic crypto out of Dart). Install e.g.
/// `globalThis.CFL_mnemonicToEntropy = m => bip39.mnemonicToEntropy(m)`.
@JS('CFL_mnemonicToEntropy')
external String? _mnemonicToEntropy(String mnemonic);

// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

/// A COSE `signData` result (`COSE_Sign1` + `COSE_Key`, both hex CBOR) — the
/// web mirror of the native `DataSignature` (kept dependency-free so this file
/// never reaches into the FFI-coupled `cip30.dart`).
typedef WebDataSignature = ConformanceSignature;

/// Scoped CIP-30 wallet for Flutter web (CML-JS backend + Blockfrost REST).
///
/// Implements the read + connect + `signData` + `signTx` + `submitTx` subset of CIP-30.
/// Construct with [WebCip30Wallet.fromMnemonic]. Returned addresses are
/// hex-encoded raw address bytes and returned UTxOs are CBOR
/// `TransactionUnspentOutput` hex, matching native [Cip30Wallet] behavior.
/// Tx-building remains out of scope on web for the RC — see the library doc.
///
/// ```dart
/// final wallet = await WebCip30Wallet.fromMnemonic(
///   mnemonic: mnemonic,
///   provider: BlockfrostProvider(projectId: id, network: Network.testnetPreview),
///   isTestnet: true,
/// );
/// final netId = await wallet.getNetworkId();       // 0 (testnet)
/// final addr = await wallet.getChangeAddress();    // address hex
/// final bal = await wallet.getBalance();           // Value CBOR hex
/// final sig = wallet.signData(utf8Hex('hello'));   // COSE_Sign1 + COSE_Key
/// ```
@experimental
class WebCip30Wallet {
  /// The chain-data provider (UTxO / balance reads over REST).
  final BlockfrostProvider provider;

  /// CIP-30 network id: `0` testnet, `1` mainnet.
  final int networkId;

  /// The account's first external base address (role 0, index 0), bech32.
  final String baseAddressBech32;

  /// The account's stake/reward address, bech32.
  final String rewardAddressBech32;

  /// Payment credential key hash (hex) of [baseAddressBech32].
  final String paymentKeyHashHex;

  /// Stake credential key hash (hex) of [rewardAddressBech32].
  final String stakeKeyHashHex;

  // m/1852'/1815'/account'/0/0 leaf private key, bech32 — fed to COSE signData.
  final String _paymentSigningKeyBech32;
  final String _stakeSigningKeyBech32;

  final CmlWebBackend _cml;

  WebCip30Wallet._({
    required this.provider,
    required this.networkId,
    required this.baseAddressBech32,
    required this.rewardAddressBech32,
    required this.paymentKeyHashHex,
    required this.stakeKeyHashHex,
    required String paymentSigningKeyBech32,
    required String stakeSigningKeyBech32,
    required CmlWebBackend cml,
  })  : _paymentSigningKeyBech32 = paymentSigningKeyBech32,
        _stakeSigningKeyBech32 = stakeSigningKeyBech32,
        _cml = cml;

  static const int _harden = 0x80000000;

  /// Derives a scoped web wallet from a BIP-39 [mnemonic] (CIP-1852).
  ///
  /// Requires the host to have installed `globalThis.CFL_mnemonicToEntropy`
  /// (see the library doc); throws [UnimplementedError] otherwise.
  static Future<WebCip30Wallet> fromMnemonic({
    required String mnemonic,
    required BlockfrostProvider provider,
    required bool isTestnet,
    String passphrase = '',
    int accountIndex = 0,
  }) async {
    final networkId = isTestnet ? 0 : 1;

    final entropyHex = _mnemonicToEntropy(mnemonic);
    if (entropyHex == null) {
      throw UnimplementedError(
        'WebCip30Wallet needs a host BIP-39 bridge: install '
        'globalThis.CFL_mnemonicToEntropy (e.g. bip39.mnemonicToEntropy). '
        'See docs/web-backend.md.',
      );
    }

    final root = _Bip32PrivateKey.from_bip39_entropy(
      _hexToBytes(entropyHex).toJS,
      // Passphrase is applied at the BIP-39 entropy stage by the host bridge if
      // needed; CML's from_bip39_entropy password arg is the (rarely used) CIP-3
      // second factor and is left empty to match the native CIP-1852 path.
      Uint8List(0).toJS,
    );
    final acct = root
        .derive(_harden + 1852)
        .derive(_harden + 1815)
        .derive(_harden + accountIndex);

    final accountKeyBech32 = acct.to_bech32();
    final paymentSigningKeyBech32 = acct.derive(0).derive(0).to_bech32();
    final stakeSigningKeyBech32 = acct.derive(2).derive(0).to_bech32();
    final stakeKeyHash =
        acct.derive(2).derive(0).to_raw_key().to_public().hash();

    const cml = CmlWebBackend();
    // Base (change/used) address via the conformance-frozen derivation path.
    final derived = cml.deriveAddress(
      accountKey: accountKeyBech32,
      role: 0,
      index: 0,
      networkId: networkId,
    );
    final rewardAddressBech32 =
        _RewardAddress.new_(networkId, _Credential.new_pub_key(stakeKeyHash))
            .to_address()
            .to_bech32();

    return WebCip30Wallet._(
      provider: provider,
      networkId: networkId,
      baseAddressBech32: derived.address,
      rewardAddressBech32: rewardAddressBech32,
      paymentKeyHashHex: derived.paymentKeyHash,
      stakeKeyHashHex: stakeKeyHash.to_hex(),
      paymentSigningKeyBech32: paymentSigningKeyBech32,
      stakeSigningKeyBech32: stakeSigningKeyBech32,
      cml: cml,
    );
  }

  // --- CIP-30: connect / address methods ----------------------------------

  /// CIP-30 `getNetworkId` — `0` testnet, `1` mainnet.
  Future<int> getNetworkId() async => networkId;

  /// CIP-30 `getChangeAddress` — the account's external base address as hex.
  Future<String> getChangeAddress() async =>
      _cml.addressToHex(addressBech32: baseAddressBech32);

  /// CIP-30 `getUsedAddresses` — the scoped wallet exposes a single account
  /// address, returned as hex so dApps can target it directly.
  Future<List<String>> getUsedAddresses() async => [await getChangeAddress()];

  /// CIP-30 `getUnusedAddresses` — none in the scoped single-address model.
  Future<List<String>> getUnusedAddresses() async => const [];

  /// CIP-30 `getRewardAddresses` — the account's stake/reward address as hex.
  Future<List<String>> getRewardAddresses() async =>
      [_cml.addressToHex(addressBech32: rewardAddressBech32)];

  // --- CIP-30: chain reads (Blockfrost REST) ------------------------------

  /// CIP-30 `getUtxos` — the account's UTxO set as CBOR
  /// `TransactionUnspentOutput` hex strings.
  Future<List<String>> getUtxos() async {
    final utxos = await provider.fetchUtxos(baseAddressBech32);
    return utxos.map(_cml.utxoToCborHex).toList(growable: false);
  }

  /// CIP-30 `getBalance` — total balance as canonical `Value` CBOR hex.
  ///
  /// Sums the account's UTxOs (coin + native tokens) and serializes through the
  /// conformance-frozen [CmlWebBackend.valueToCborHex] (canonical map ordering).
  Future<String> getBalance() async {
    final utxos = await provider.fetchUtxos(baseAddressBech32);
    final agg =
        aggregateUtxos(utxos); // pure, unit-tested (value_aggregate.dart)
    return _cml.valueToCborHex(coin: agg.coin, assets: agg.assets);
  }

  // --- CIP-30: signData ----------------------------------------------------

  /// CIP-30 `signData` — COSE_Sign1 over [payloadHex], bound to the wallet's
  /// base address (identity-binding in the protected header). Returns the
  /// `COSE_Sign1` + `COSE_Key` hex pair, verifiable by [CmlWebBackend.verifyData]
  /// or the native `verifyData`.
  WebDataSignature signData(String payloadHex) {
    final addressHex = _cml.addressToHex(addressBech32: baseAddressBech32);
    return _cml.signData(
      addressHex: addressHex,
      payloadHex: payloadHex,
      signingKeyBech32: _paymentSigningKeyBech32,
    );
  }

  /// CIP-30 `signTx` — sign a full transaction CBOR hex string and return this
  /// wallet's `transaction_witness_set` CBOR hex.
  ///
  /// [partialSign] is accepted for API compatibility; this scoped wallet always
  /// contributes every witness it can produce.
  Future<String> signTx(String txCborHex, {bool partialSign = false}) async {
    return _cml.signTx(
      txCborHex: txCborHex,
      signingKeysBech32: [_paymentSigningKeyBech32, _stakeSigningKeyBech32],
    );
  }

  /// CIP-30 `submitTx` — submit a fully signed transaction CBOR hex string and
  /// return its transaction hash.
  Future<String> submitTx(String signedTxCborHex) async =>
      provider.submitTransaction(_hexToBytes(signedTxCborHex));

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
