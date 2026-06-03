// CIP-30 dApp connector — high-level wallet API (Phase 4.3).
//
// On mobile the SDK *is* the wallet, so [Cip30Wallet] exposes the CIP-30 method
// surface (getUtxos, getBalance, signTx, signData, …) backed by a key set, a
// [BlockfrostProvider] for chain queries, and the Rust serialization/signing
// primitives in `cip30.dart`.
//
// Outputs follow the CIP-30 spec: addresses and values are returned as hex CBOR,
// `getUtxos` yields CBOR `TransactionUnspentOutput`s, `signTx` yields a
// `transaction_witness_set`, and `signData` yields a COSE `DataSignature`.

import 'dart:convert';
import 'dart:typed_data';

import '../cip30.dart';
import '../tx.dart';
import '../wallet.dart' show KeyDerivationResult;
import '../wrappers.dart';
import '../providers/blockfrost.dart';

export '../cip30.dart' show DataSignature;

/// A CIP-30-compliant wallet backed by a local key set and a chain provider.
///
/// Construct one with [Cip30Wallet.fromMnemonic], then call the CIP-30 methods.
/// This models a single-address wallet (one base address derived from the
/// account's payment + stake credentials), which is the common mobile case.
///
/// Example:
/// ```dart
/// final provider = BlockfrostProvider(
///   projectId: 'your_id',
///   network: Network.testnetPreview,
/// );
/// final wallet = await Cip30Wallet.fromMnemonic(
///   mnemonic: 'test walk nut penalty hip pave soap entry language right filter choice',
///   provider: provider,
/// );
///
/// final netId = await wallet.getNetworkId();        // 0 (testnet) | 1 (mainnet)
/// final utxos = await wallet.getUtxos();            // List<String> CBOR hex
/// final balance = await wallet.getBalance();        // String CBOR hex Value
/// final change = await wallet.getChangeAddress();   // String hex address
/// ```
class Cip30Wallet {
  /// Derived keys for this wallet (signing material lives here — keep private).
  final KeyDerivationResult _keys;

  /// Chain data provider used for UTxO/balance queries and submission.
  final BlockfrostProvider provider;

  /// The wallet's single base address (bech32, `addr…` / `addr_test…`).
  final String baseAddress;

  /// The wallet's reward (stake) address (bech32, `stake…` / `stake_test…`).
  final String rewardAddress;

  Cip30Wallet._({
    required KeyDerivationResult keys,
    required this.provider,
    required this.baseAddress,
    required this.rewardAddress,
  }) : _keys = keys;

  /// CIP-30 network id: 0 = testnet, 1 = mainnet.
  int get networkId => provider.network == Network.mainnet ? 1 : 0;

  /// Build a wallet from a BIP-39 mnemonic and a configured provider.
  ///
  /// The network is inferred from [provider]'s [BlockfrostProvider.network].
  static Future<Cip30Wallet> fromMnemonic({
    required String mnemonic,
    required BlockfrostProvider provider,
    String passphrase = '',
    int accountIndex = 0,
  }) async {
    final isTestnet = provider.network != Network.mainnet;
    final keys = await deriveKeysFromMnemonic(
      mnemonic: mnemonic,
      passphrase: passphrase,
      accountIndex: accountIndex,
      isTestnet: isTestnet,
    );

    final base = computeBaseAddress(
      paymentKeyHashHex: keys.paymentKeyHash,
      stakeKeyHashHex: keys.stakeKeyHash,
      networkId: isTestnet ? 0 : 1,
    );
    final reward = computeStakeAddress(
      stakeKeyHashHex: keys.stakeKeyHash,
      isTestnet: isTestnet,
    );

    return Cip30Wallet._(
      keys: keys,
      provider: provider,
      baseAddress: base,
      rewardAddress: reward,
    );
  }

  // ── CIP-30 API ─────────────────────────────────────────────────────────────

  /// `api.getNetworkId()` — 0 for testnet, 1 for mainnet.
  Future<int> getNetworkId() async => networkId;

  /// `api.getUtxos()` — the wallet's UTxOs as CBOR `TransactionUnspentOutput`
  /// hex strings.
  ///
  /// Returns an empty list if the address holds no UTxOs. Pagination is not yet
  /// implemented; all UTxOs are returned in one page.
  Future<List<String>> getUtxos() async {
    final utxos = await provider.fetchUtxos(baseAddress);
    final inputs = utxosToTxInputs(utxos);
    return inputs.map((i) => utxoToCborHex(input: i)).toList();
  }

  /// `api.getBalance()` — total balance as a CBOR-encoded `Value` hex string.
  ///
  /// Sums every UTxO at the wallet's address (ADA + native tokens).
  Future<String> getBalance() async {
    final utxos = await provider.fetchUtxos(baseAddress);
    final inputs = utxosToTxInputs(utxos);
    if (inputs.isEmpty) {
      return valueToCborHex(value: Value(coin: BigInt.zero, assets: []));
    }
    final total = sumValues(values: inputs.map((i) => i.value).toList());
    return valueToCborHex(value: total);
  }

  /// `api.getChangeAddress()` — the wallet's change address as a hex string.
  Future<String> getChangeAddress() async =>
      addressToHex(addressBech32: baseAddress);

  /// `api.getUsedAddresses()` — addresses that have participated in a tx.
  ///
  /// Returned as hex strings. This single-address wallet reports its base
  /// address as used when it currently holds UTxOs, otherwise an empty list.
  Future<List<String>> getUsedAddresses() async {
    final utxos = await provider.fetchUtxos(baseAddress);
    if (utxos.isEmpty) return [];
    return [addressToHex(addressBech32: baseAddress)];
  }

  /// `api.getUnusedAddresses()` — addresses not yet used.
  ///
  /// Returned as hex strings. Reports the base address as unused when it holds
  /// no UTxOs, otherwise an empty list.
  Future<List<String>> getUnusedAddresses() async {
    final utxos = await provider.fetchUtxos(baseAddress);
    if (utxos.isEmpty) return [addressToHex(addressBech32: baseAddress)];
    return [];
  }

  /// `api.getRewardAddresses()` — the wallet's reward address(es) as hex.
  Future<List<String>> getRewardAddresses() async =>
      [addressToHex(addressBech32: rewardAddress)];

  /// `api.signTx(tx, partialSign)` — sign a full transaction (CBOR hex) and
  /// return the resulting `transaction_witness_set` as CBOR hex.
  ///
  /// Both the payment and stake keys are used, so transactions that include
  /// staking certificates or withdrawals are covered. The dApp merges the
  /// returned witness set with the transaction body before submitting.
  ///
  /// [partialSign] is accepted for CIP-30 signature compatibility; this wallet
  /// always contributes every witness it can produce regardless of the flag.
  Future<String> signTx(String txCborHex, {bool partialSign = false}) async {
    return cip30SignTx(
      txCborHex: txCborHex,
      signingKeysBech32: [_keys.paymentSigningKey, _keys.stakeSigningKey],
    );
  }

  /// `api.signData(addr, payload)` — produce a CIP-8 `COSE_Sign1` data
  /// signature over [payloadHex] (hex bytes) for [addressHex].
  ///
  /// [addressHex] defaults to the wallet's base address. The payment key signs
  /// for the base address; the stake key signs for the reward address.
  Future<DataSignature> signData(String payloadHex,
      {String? addressHex}) async {
    final addr = addressHex ?? addressToHex(addressBech32: baseAddress);
    final rewardHex = addressToHex(addressBech32: rewardAddress);
    final signingKey =
        addr == rewardHex ? _keys.stakeSigningKey : _keys.paymentSigningKey;
    return cip30SignData(
      addressHex: addr,
      payloadHex: payloadHex,
      signingKeyBech32: signingKey,
    );
  }

  /// Convenience: sign a UTF-8 string payload with [signData].
  Future<DataSignature> signString(String message, {String? addressHex}) =>
      signData(_utf8ToHex(message), addressHex: addressHex);

  /// `api.submitTx(tx)` — submit a fully-signed transaction (CBOR hex) and
  /// return its transaction hash.
  Future<String> submitTx(String signedTxCborHex) async {
    return provider.submitTransaction(_hexToBytes(signedTxCborHex));
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static String _utf8ToHex(String s) {
    final bytes = utf8.encode(s);
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) => Uint8List.fromList(
        List.generate(
          hex.length ~/ 2,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
}
