// CIP-30-shaped wallet backed by a hardware device (Phase 4.5).
//
// Mirrors [Cip30Wallet], but the signing material lives on a [HardwareWallet]
// (Ledger/Trezor) instead of in a local key set. Addresses are derived from the
// device's account xpub (no private keys ever leave the device); chain queries
// go through a [BlockfrostProvider]; signing is delegated to the device and the
// returned witnesses are assembled into a submittable transaction.

import 'dart:typed_data';

import '../cip30.dart';
import '../tx.dart' show Value;
import '../hardware.dart'
    show HardwareAccount, xpubToAccount, assembleVkeyWitnessSet;
import '../wrappers.dart';
import '../providers/blockfrost.dart';
import 'hardware_wallet.dart';

export 'hardware_wallet.dart';
export '../hardware.dart' show HardwareAccount, HardwareVkeyWitness;

/// A CIP-30-style wallet whose keys live on a hardware device.
///
/// Construct one with [HardwareCip30Wallet.fromDevice], which reads the account
/// xpub off the device and derives the wallet's addresses locally (so address
/// listing and balance/UTxO queries need no further device round-trips). Use
/// [signTransaction] to have the device sign and get back a submittable tx.
///
/// Example:
/// ```dart
/// final wallet = await HardwareCip30Wallet.fromDevice(
///   device: ledgerHardwareWallet,            // your HardwareWallet adapter
///   provider: BlockfrostProvider(projectId: '…', network: Network.testnetPreview),
/// );
/// final utxos = await wallet.getUtxos();
/// final balance = await wallet.getBalance();
/// final signedTx = await wallet.signTransaction(HardwareSignRequest(
///   txBodyCborHex: bodyHex,
///   signerPaths: [wallet.paymentPath],
/// ));
/// final txId = await wallet.submitTx(signedTx);
/// ```
class HardwareCip30Wallet {
  /// The underlying hardware device transport.
  final HardwareWallet device;

  /// Chain data provider for UTxO/balance queries and submission.
  final BlockfrostProvider provider;

  /// The account this wallet operates on (`m/1852'/1815'/accountIndex'`).
  final int accountIndex;

  /// Addresses + key hashes derived from the device's account xpub.
  final HardwareAccount account;

  HardwareCip30Wallet._({
    required this.device,
    required this.provider,
    required this.accountIndex,
    required this.account,
  });

  /// CIP-30 network id: 0 = testnet, 1 = mainnet.
  int get networkId => provider.network == Network.mainnet ? 1 : 0;

  /// The wallet's base address (bech32).
  String get baseAddress => account.baseAddress;

  /// The wallet's reward (stake) address (bech32).
  String get rewardAddress => account.rewardAddress;

  /// BIP-32 payment path `m/1852'/1815'/accountIndex'/0/0` (hardened segments
  /// already marked), for [HardwareSignRequest.signerPaths].
  List<int> get paymentPath => [_h(1852), _h(1815), _h(accountIndex), 0, 0];

  /// BIP-32 stake path `m/1852'/1815'/accountIndex'/2/0`.
  List<int> get stakePath => [_h(1852), _h(1815), _h(accountIndex), 2, 0];

  static int _h(int i) => i | 0x80000000;

  /// Build a wallet by reading the account xpub off [device].
  ///
  /// The network is inferred from [provider]. No private keys are involved; the
  /// addresses are derived from the xpub via [xpubToAccount].
  static Future<HardwareCip30Wallet> fromDevice({
    required HardwareWallet device,
    required BlockfrostProvider provider,
    int accountIndex = 0,
  }) async {
    final xpub = await device.getAccountXpub(accountIndex: accountIndex);
    final account = xpubToAccount(
      accountXpubHex: xpub,
      networkId: provider.network == Network.mainnet ? 1 : 0,
    );
    return HardwareCip30Wallet._(
      device: device,
      provider: provider,
      accountIndex: accountIndex,
      account: account,
    );
  }

  // ── CIP-30 read surface (no device round-trips) ────────────────────────────

  /// `api.getNetworkId()` — 0 for testnet, 1 for mainnet.
  Future<int> getNetworkId() async => networkId;

  /// `api.getUtxos()` — the wallet's UTxOs as CBOR `TransactionUnspentOutput`
  /// hex strings.
  Future<List<String>> getUtxos() async {
    final utxos = await provider.fetchUtxos(baseAddress);
    final inputs = utxosToTxInputs(utxos);
    return inputs.map((i) => utxoToCborHex(input: i)).toList();
  }

  /// `api.getBalance()` — total balance as a CBOR-encoded `Value` hex string.
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

  /// `api.getUsedAddresses()` — base address as hex when it holds UTxOs.
  Future<List<String>> getUsedAddresses() async {
    final utxos = await provider.fetchUtxos(baseAddress);
    if (utxos.isEmpty) return [];
    return [addressToHex(addressBech32: baseAddress)];
  }

  /// `api.getUnusedAddresses()` — base address as hex when it holds no UTxOs.
  Future<List<String>> getUnusedAddresses() async {
    final utxos = await provider.fetchUtxos(baseAddress);
    if (utxos.isEmpty) return [addressToHex(addressBech32: baseAddress)];
    return [];
  }

  /// `api.getRewardAddresses()` — the wallet's reward address as hex.
  Future<List<String>> getRewardAddresses() async =>
      [addressToHex(addressBech32: rewardAddress)];

  // ── Signing (device round-trip) ────────────────────────────────────────────

  /// Have the device sign [request] and return the full signed transaction as
  /// CBOR hex, ready for [submitTx].
  ///
  /// The device produces raw vkey witnesses, which are folded into a
  /// `transaction_witness_set` ([assembleVkeyWitnessSet]) and combined with
  /// [HardwareSignRequest.txBodyCborHex] ([cip30AssembleTx]).
  Future<String> signTransaction(HardwareSignRequest request) async {
    final witnesses = await device.signTransaction(request);
    final witnessSetHex = assembleVkeyWitnessSet(witnesses: witnesses);
    return cip30AssembleTx(
      txBodyCborHex: request.txBodyCborHex,
      witnessSetCborHex: witnessSetHex,
    );
  }

  /// `api.signTx(tx)` — CIP-30 shape: sign and return just the
  /// `transaction_witness_set` (the dApp merges it with the body).
  ///
  /// [signerPaths] defaults to the payment path; pass [stakePath] too for
  /// transactions with staking certificates or withdrawals.
  Future<String> signTx(
    String txBodyCborHex, {
    List<List<int>>? signerPaths,
  }) async {
    final witnesses = await device.signTransaction(HardwareSignRequest(
      txBodyCborHex: txBodyCborHex,
      signerPaths: signerPaths ?? [paymentPath],
    ));
    return assembleVkeyWitnessSet(witnesses: witnesses);
  }

  /// `api.submitTx(tx)` — submit a fully-signed transaction (CBOR hex) and
  /// return its transaction hash.
  Future<String> submitTx(String signedTxCborHex) async {
    return provider.submitTransaction(_hexToBytes(signedTxCborHex));
  }

  static Uint8List _hexToBytes(String hex) => Uint8List.fromList(
        List.generate(
          hex.length ~/ 2,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
}
