import 'dart:async';

/// Platform-agnostic CIP-30 wallet contract.
///
/// Native CSL/FFI and web CML/JS wallets are adapters behind this interface.
/// The [Signature] type stays generic because the native generated bridge uses
/// [DataSignature], while the web-safe entrypoint uses a plain record. The
/// wallet method surface and its asynchronous chain operations remain shared.
///
/// Implementations must preserve CIP-30's hex/CBOR result encodings and must
/// fail rather than silently inventing addresses, balances, or signatures.
abstract interface class Cip30WalletApi<Signature> {
  /// Returns `0` for testnet and `1` for mainnet.
  Future<int> getNetworkId();

  /// Returns the wallet's UTxOs as CBOR `TransactionUnspentOutput` hex.
  Future<List<String>> getUtxos();

  /// Returns the wallet balance as canonical `Value` CBOR hex.
  Future<String> getBalance();

  /// Returns the change address as raw address bytes encoded in hex.
  Future<String> getChangeAddress();

  /// Returns used addresses as raw address bytes encoded in hex.
  Future<List<String>> getUsedAddresses();

  /// Returns unused addresses as raw address bytes encoded in hex.
  Future<List<String>> getUnusedAddresses();

  /// Returns reward addresses as raw address bytes encoded in hex.
  Future<List<String>> getRewardAddresses();

  /// Signs a full transaction and returns a witness-set CBOR hex string.
  Future<String> signTx(String txCborHex, {bool partialSign = false});

  /// Signs a payload using the address's credential and returns a CIP-8 result.
  ///
  /// Implementations may complete synchronously when the signing backend is
  /// local and synchronous, or asynchronously when the backend requires it.
  FutureOr<Signature> signData(String payloadHex, {String? addressHex});

  /// Submits a fully signed transaction and returns its transaction hash.
  Future<String> submitTx(String signedTxCborHex);
}
