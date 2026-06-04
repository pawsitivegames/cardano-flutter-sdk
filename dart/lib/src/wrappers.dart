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
import 'message.dart';
import 'minting.dart';
import 'metadata.dart';
import 'staking.dart';
import 'providers/blockfrost.dart';

/// Returns the SDK version string.
Future<String> getSdkVersion() {
  return Future.value(RustLib.instance.api.crateSdkVersion());
}

/// Converts a Blockfrost [ProtocolParameters] into the Rust [ProtocolParams]
/// used by the transaction builders.
///
/// Example:
/// ```dart
/// final raw = await provider.fetchProtocolParameters();
/// final params = raw.toProtocolParams();
/// ```
extension ProtocolParametersConvert on ProtocolParameters {
  /// Map this Blockfrost result to the FFI [ProtocolParams] struct.
  ProtocolParams toProtocolParams() => ProtocolParams(
        minFeeA: BigInt.from(minFeeA),
        minFeeB: BigInt.from(minFeeB),
        coinsPerUtxoByte: BigInt.from(coinsPerUtxoByte),
        maxTxSize: maxTxSize,
        poolDeposit: BigInt.from(poolDeposit),
        keyDeposit: BigInt.from(keyDeposit),
        maxValSize: maxValueSize,
      );
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

/// Derives a base address (and its payment key hash) at a specific
/// `(role, index)` within an account, from the account-level xprv
/// ([KeyDerivationResult.accountKey]).
///
/// - [role]: 0 = external/receive chain, 1 = internal/change chain.
/// - [index]: address index on that chain.
/// - [networkId]: 0 = testnet, 1 = mainnet.
///
/// Used for HD multi-account discovery and BIP-44 gap-limit scanning
/// (see [HdWalletDiscovery]). Every address in an account shares the account's
/// single stake credential, per CIP-1852.
///
/// Example:
/// ```dart
/// final keys = await deriveKeysFromMnemonic(
///   mnemonic: mnemonic, passphrase: '', accountIndex: 0, isTestnet: true);
/// final receive0 = await deriveAddress(
///   accountKey: keys.accountKey, role: 0, index: 0, networkId: 0);
/// print(receive0.address); // addr_test1…
/// ```
Future<DerivedAddress> deriveAddress({
  required String accountKey,
  required int role,
  required int index,
  required int networkId,
}) {
  return Future.value(RustLib.instance.api.crateWalletDeriveAddress(
    accountKey: accountKey,
    role: role,
    index: index,
    networkId: networkId,
  ));
}

/// Converts a Blockfrost [Utxo] to a [TxInput] for coin selection.
///
/// Preserves all native token holdings from the UTXO. This is the correct
/// way to convert UTXOs — using a manual mapping that drops assets will cause
/// multi-asset coin selection to silently fail.
///
/// Example:
/// ```dart
/// final utxos = await provider.fetchUtxos(myAddress);
/// final inputs = utxos.map(utxoToTxInput).toList();
/// ```
TxInput utxoToTxInput(Utxo utxo) {
  final assets = <NativeAsset>[];
  utxo.assets.forEach((policyId, assetMap) {
    assetMap.forEach((assetName, qty) {
      assets.add(NativeAsset(
        policyId: policyId,
        assetName: assetName,
        quantity: qty,
      ));
    });
  });
  return TxInput(
    txHash: utxo.txHash,
    outputIndex: utxo.outputIndex,
    address: utxo.address,
    value: Value(coin: utxo.coin, assets: assets),
  );
}

/// Converts a list of Blockfrost [Utxo]s to [TxInput]s for coin selection.
///
/// Convenience wrapper around [utxoToTxInput].
List<TxInput> utxosToTxInputs(List<Utxo> utxos) =>
    utxos.map(utxoToTxInput).toList();

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
      (i) =>
          int.parse(signedTx.txCborHex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  ));
}

// ── Phase 3: Minting + Metadata ─────────────────────────────────────────────

/// Build a CIP-25 NFT minting transaction in one call.
///
/// Convenience wrapper that:
/// 1. Builds CIP-25 metadata CBOR from [nftName], [nftImage], etc.
/// 2. Calls [buildMintTx] with the metadata attached.
///
/// Pass the returned [BuiltMintTx] to [signMintTransaction] to complete signing.
///
/// Example:
/// ```dart
/// final keys = await deriveKeysFromMnemonic(...);
/// final params = await provider.fetchProtocolParameters();
/// final utxos = await provider.fetchUtxos(keys.baseAddress);
///
/// final builtMintTx = await buildNftMintTransaction(
///   inputs: utxos,
///   changeAddress: keys.baseAddress,
///   policyScript: makePubkeyScript(keyHashHex: keys.paymentKeyHash),
///   assetNameHex: hex.encode(utf8.encode('MyNFT')),
///   nftName: 'My NFT',
///   nftImage: 'ipfs://QmYourImageHash',
///   mediaType: 'image/png',
///   ttl: currentSlot + 1000,
///   params: params,
/// );
/// ```
Future<BuiltMintTx> buildNftMintTransaction({
  required List<TxInput> inputs,
  required List<TxOutput> outputs,
  required String changeAddress,
  required String policyScript,
  required String assetNameHex,
  required String policyIdHex,
  required String nftName,
  required String nftImage,
  String? mediaType,
  String? description,
  BigInt? ttl,
  required ProtocolParams params,
}) async {
  final auxDataHex = buildCip25Metadata(
    policies: [
      Cip25Policy(
        policyIdHex: policyIdHex,
        assets: [
          Cip25Asset(
            assetNameHex: assetNameHex,
            name: nftName,
            image: nftImage,
            mediaType: mediaType,
            description: description,
          ),
        ],
      ),
    ],
  );

  return Future.value(buildMintTx(
    inputs: inputs,
    outputs: outputs,
    changeAddress: changeAddress,
    mintSpecs: [
      MintSpec(
        policyScriptCborHex: policyScript,
        assets: [MintAsset(assetNameHex: assetNameHex, quantity: 1)],
      ),
    ],
    auxDataCborHex: auxDataHex,
    ttl: ttl,
    params: params,
  ));
}

// ── Phase 4.1: Staking ──────────────────────────────────────────────────────

/// Compute the bech32 stake (reward) address for a stake key hash.
///
/// Example:
/// ```dart
/// final keys = await deriveKeysFromMnemonic(...);
/// final stakeAddr = computeStakeAddress(
///   stakeKeyHashHex: keys.stakeKeyHash,
///   isTestnet: true,
/// );
/// // "stake_test1u..."
/// ```
String computeStakeAddress({
  required String stakeKeyHashHex,
  required bool isTestnet,
}) {
  return RustLib.instance.api.crateStakingComputeStakeAddress(
    stakeKeyHashHex: stakeKeyHashHex,
    isTestnet: isTestnet,
  );
}

/// Build a stake key registration transaction.
///
/// [params] must be a [ProtocolParams] from [fetchProtocolParameters].
Future<BuiltStakingTx> buildStakeRegistrationTx({
  required String stakeKeyHashHex,
  required List<TxInput> inputs,
  required String changeAddress,
  required int networkId,
  BigInt? ttl,
  required ProtocolParams params,
}) {
  return Future.value(
    RustLib.instance.api.crateStakingBuildStakeRegistrationTx(
      stakeKeyHashHex: stakeKeyHashHex,
      inputs: inputs,
      changeAddress: changeAddress,
      networkId: networkId,
      ttl: ttl,
      params: params,
    ),
  );
}

/// Build a stake delegation transaction.
///
/// The stake key must already be registered before calling this.
Future<BuiltStakingTx> buildDelegationTx({
  required String stakeKeyHashHex,
  required String poolKeyhashHex,
  required List<TxInput> inputs,
  required String changeAddress,
  required int networkId,
  BigInt? ttl,
  required ProtocolParams params,
}) {
  return Future.value(
    RustLib.instance.api.crateStakingBuildDelegationTx(
      stakeKeyHashHex: stakeKeyHashHex,
      poolKeyhashHex: poolKeyhashHex,
      inputs: inputs,
      changeAddress: changeAddress,
      networkId: networkId,
      ttl: ttl,
      params: params,
    ),
  );
}

/// Build a reward withdrawal transaction.
///
/// [rewardAmount] must match the exact on-chain withdrawable balance.
Future<BuiltStakingTx> buildRewardWithdrawalTx({
  required String stakeKeyHashHex,
  required BigInt rewardAmount,
  required List<TxInput> inputs,
  required String changeAddress,
  required int networkId,
  BigInt? ttl,
  required ProtocolParams params,
}) {
  return Future.value(
    RustLib.instance.api.crateStakingBuildRewardWithdrawalTx(
      stakeKeyHashHex: stakeKeyHashHex,
      rewardAmount: rewardAmount,
      inputs: inputs,
      changeAddress: changeAddress,
      networkId: networkId,
      ttl: ttl,
      params: params,
    ),
  );
}

/// Build a stake key deregistration transaction.
///
/// Returns the key deposit to the change address.
Future<BuiltStakingTx> buildStakeDeregistrationTx({
  required String stakeKeyHashHex,
  required List<TxInput> inputs,
  required String changeAddress,
  required int networkId,
  BigInt? ttl,
  required ProtocolParams params,
}) {
  return Future.value(
    RustLib.instance.api.crateStakingBuildStakeDeregistrationTx(
      stakeKeyHashHex: stakeKeyHashHex,
      inputs: inputs,
      changeAddress: changeAddress,
      networkId: networkId,
      ttl: ttl,
      params: params,
    ),
  );
}

/// Sign a staking transaction with both payment and stake keys.
///
/// Staking certificates and withdrawals require the stake key witness.
/// Regular inputs require the payment key witness.
Future<SignedTx> signStakingTransaction({
  required String txBodyCborHex,
  required String paymentSigningKey,
  required String stakeSigningKey,
}) {
  return Future.value(
    RustLib.instance.api.crateSignSignTxInternal(
      txBodyCborHex: txBodyCborHex,
      paymentKeysHex: [paymentSigningKey, stakeSigningKey],
    ),
  );
}

/// Sign a minting transaction that carries auxiliary data (CIP-25/68 metadata).
///
/// Use instead of [signTransaction] when the transaction was built by
/// [buildMintTx] with a non-null [BuiltMintTx.auxDataCborHex].
///
/// Example:
/// ```dart
/// final signedTx = await signMintTransaction(
///   builtMintTx: builtMintTx,
///   paymentKeys: [keys.paymentKey],
/// );
/// await provider.submitTransaction(signedTxToBytes(signedTx));
/// ```
Future<SignedTx> signMintTransaction({
  required BuiltMintTx builtMintTx,
  required List<String> paymentKeys,
}) {
  return Future.value(
    RustLib.instance.api.crateSignSignTxWithMetadata(
      txBodyCborHex: builtMintTx.txBodyCborHex,
      paymentKeysHex: paymentKeys,
      auxDataCborHex: builtMintTx.auxDataCborHex,
      // Carry the builder's witness set (with the minting policy's native
      // script) into signing so the script isn't dropped — otherwise the tx is
      // rejected on submission with MissingScriptWitnessesUTXOW.
      baseWitnessSetCborHex: builtMintTx.witnessSetCborHex,
    ),
  );
}

// ── Phase 4.2: Message Signing (CIP-8) ──────────────────────────────────────

/// Sign an arbitrary message with a payment or stake key (CIP-8).
///
/// Creates a COSE Sign1 signed message that can be verified independently.
/// Use for authentication, proof-of-key ownership, or dApp login flows.
///
/// Example:
/// ```dart
/// final keys = await deriveKeysFromMnemonic(...);
/// final messageHex = hex.encode(utf8.encode('I own this wallet'));
///
/// final signedMsg = await signMessage(
///   message: messageHex,
///   signingKey: keys.paymentSigningKey,
///   address: keys.baseAddress,
/// );
/// print('Signature: ${signedMsg.publicKeyHex}');
/// ```
Future<SignedMessage> signMessage({
  required String message,
  required String signingKey,
  String? address,
}) {
  return Future.value(
    RustLib.instance.api.crateMessageSignMessage(
      message: message,
      signingKeyBech32: signingKey,
      address: address,
    ),
  );
}

/// Verify a CIP-8 signed message.
///
/// Checks that the signature is valid for the public key in the message.
/// Optionally verifies that the message came from an expected address.
///
/// Returns true if the signature is valid, false otherwise.
///
/// Example:
/// ```dart
/// final isValid = await verifyMessage(
///   signedMessage: signedMsg,
///   expectedAddress: keys.baseAddress,
/// );
/// if (isValid) {
///   print('Message is authentic!');
/// }
/// ```
Future<bool> verifyMessage({
  required SignedMessage signedMessage,
  String? expectedAddress,
}) {
  return Future.value(
    RustLib.instance.api.crateMessageVerifyMessage(
      signedMessage: signedMessage,
      expectedAddress: expectedAddress,
    ),
  );
}
