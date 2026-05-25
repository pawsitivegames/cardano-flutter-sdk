// Convenience wrappers for generated RustLibApi methods.
// These provide direct access to Rust functions via simpler names.

// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'frb_generated.dart';
import 'wallet.dart';
import 'address.dart';
import 'tx.dart';
import 'coin_selection.dart';
import 'sign.dart';

/// Returns the SDK version string.
Future<String> getSdkVersion() {
  return Future.value(RustLib.instance.api.crateSdkVersion());
}

/// Validates a Bech32 address string.
Future<bool> isValidBech32(String addr) {
  return Future.value(
      RustLib.instance.api.crateAddressIsValidBech32(addr: addr));
}

/// Validates an address and returns detailed info.
Future<AddressInfo> validateAddress(String address) {
  return RustLib.instance.api
      .crateAddressValidateAddressInternal(addressStr: address);
}

/// Derives keys from a BIP39 mnemonic.
///
/// Derives a payment key and stake key from a BIP39 mnemonic phrase using CIP-1852
/// hierarchical deterministic derivation.
///
/// Example:
/// ```dart
/// final keys = await deriveKeysFromMnemonic(
///   mnemonic: 'test walk nut penalty hip pave soap entry language right filter choice',
///   passphrase: '',
///   accountIndex: 0,
///   isTestnet: true,
/// );
/// print('Payment key: ${keys.paymentKey}');
/// print('Stake key: ${keys.stakeKey}');
/// ```
Future<KeyDerivationResult> deriveKeysFromMnemonic({
  required String mnemonic,
  required String passphrase,
  required int accountIndex,
  required bool isTestnet,
}) {
  return RustLib.instance.api.crateWalletDeriveKeysFromMnemonicInternal(
    mnemonic: mnemonic,
    passphrase: passphrase,
    accountIndex: accountIndex,
    isTestnet: isTestnet,
  );
}

/// Derives a child key from an account key.
Future<String> deriveAccountKey({
  required String accountKey,
  required int role,
  required int index,
}) {
  return Future.value(RustLib.instance.api.crateWalletDeriveAccountKey(
    accountKey: accountKey,
    role: role,
    index: index,
  ));
}

/// Performs coin selection using CIP-2 largest-first algorithm.
///
/// Selects a minimal set of UTXOs that cover the target outputs, computed fees,
/// and minimum change ADA. Prioritizes larger inputs to minimize the number of
/// UTXOs consumed. Returns selected inputs, change outputs, and computed fee.
///
/// Example:
/// ```dart
/// final provider = BlockfrostProvider(projectId: 'your_id');
/// final utxos = await provider.fetchUtxos(myAddress);
/// final params = await provider.fetchProtocolParameters();
///
/// final targets = [
///   TxOutput(
///     address: recipientAddress,
///     value: Value(coin: BigInt.from(2_000_000), assets: []),
///   ),
/// ];
///
/// final coinSelection = await selectCoinsForTransaction(
///   availableUtxos: utxos.map((u) => TxInput(
///     txHash: u.txHash,
///     outputIndex: u.outputIndex,
///     address: myAddress,
///     value: Value(coin: u.coin, assets: []),
///   )).toList(),
///   targetOutputs: targets,
///   changeAddress: myAddress,
///   protocolParams: params,
/// );
/// print('Selected ${coinSelection.selectedInputs.length} inputs');
/// print('Fee: ${coinSelection.fee} lovelace');
/// ```
Future<CoinSelectionResult> selectCoinsForTransaction({
  required List<TxInput> availableUtxos,
  required List<TxOutput> targetOutputs,
  required String changeAddress,
  required ProtocolParams protocolParams,
}) {
  return RustLib.instance.api.crateCoinSelectionLargestFirst(
    availableUtxos: availableUtxos,
    targetOutputs: targetOutputs,
    changeAddress: changeAddress,
    params: protocolParams,
  );
}

/// Builds a transaction with given inputs and outputs.
///
/// Constructs a transaction body from selected inputs and outputs, computes
/// change automatically, and returns the serialized body ready for signing.
/// The computed fee is included in the result.
///
/// Example:
/// ```dart
/// final coinSelection = ...; // from selectCoinsForTransaction
/// final params = ...; // from BlockfrostProvider
///
/// final builtTx = await buildTransaction(
///   inputs: coinSelection.selectedInputs,
///   outputs: [...targetOutputs, ...coinSelection.changeOutputs],
///   changeAddress: myAddress,
///   ttl: null,
///   protocolParams: params,
/// );
/// print('Transaction hash: ${builtTx.txHash}');
/// print('Fee: ${builtTx.fee} lovelace');
/// ```
/// Convenience wrapper for buildTx that wraps it as async.
Future<BuiltTx> buildTransaction({
  required List<TxInput> inputs,
  required List<TxOutput> outputs,
  required String changeAddress,
  BigInt? ttl,
  required ProtocolParams protocolParams,
}) {
  return Future.value(buildTx(
    inputs: inputs,
    outputs: outputs,
    changeAddress: changeAddress,
    ttl: ttl,
    params: protocolParams,
  ));
}

/// Signs a transaction body with payment keys.
///
/// Takes a transaction body (hex-encoded CBOR) and bech32-encoded payment keys,
/// derives public keys, and produces vkey witnesses. Returns a complete signed
/// transaction ready for submission to the blockchain.
///
/// Example:
/// ```dart
/// final builtTx = ...; // from buildTransaction
/// final keys = ...; // from deriveKeysFromMnemonic
///
/// final signedTx = await signTransaction(
///   txBodyCborHex: builtTx.txBodyCborHex,
///   paymentKeys: [keys.paymentKey],
/// );
/// print('Signed tx: ${signedTx.txHash}');
/// ```
Future<SignedTx> signTransaction({
  required String txBodyCborHex,
  required List<String> paymentKeys,
}) {
  return RustLib.instance.api.crateSignSignTxInternal(
    txBodyCborHex: txBodyCborHex,
    paymentKeysHex: paymentKeys,
  );
}

/// Converts a signed transaction from hex to CBOR bytes.
///
/// Converts the hex-encoded CBOR transaction from [SignedTx] to raw bytes
/// for submission to Blockfrost or other providers.
Uint8List signedTxToBytes(SignedTx signedTx) {
  return Uint8List.fromList(List<int>.from(
    List.generate(
      signedTx.txCborHex.length ~/ 2,
      (i) => int.parse(signedTx.txCborHex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  ));
}
