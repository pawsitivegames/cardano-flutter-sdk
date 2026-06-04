// Hardware-wallet abstraction (Phase 4.5).
//
// The core SDK stays free of any device transport (BLE/USB, APDU). It defines a
// small, device-agnostic [HardwareWallet] contract that a concrete adapter
// implements outside the package — in the example app, backed by
// `ledger_cardano_plus` / `ledger_flutter_plus`.
//
// Two pure Rust primitives make a device usable once it exposes an xpub and can
// return raw witnesses:
//   * [xpubToAccount]          — addresses + key hashes from the account xpub
//   * [assembleVkeyWitnessSet] — device witnesses → CBOR witness set
// both re-exported from `hardware.dart` (generated bindings).

import '../hardware.dart' show HardwareVkeyWitness;

/// What a hardware device must be asked to sign.
///
/// The core does not reconstruct a device's wire format from CBOR; an adapter
/// translates the transaction into its own protocol. This request therefore
/// carries both the CBOR needed for *final assembly* ([txBodyCborHex]) and the
/// information a device needs to *produce* the witnesses ([signerPaths], and the
/// full unsigned tx for libraries that parse it).
class HardwareSignRequest {
  /// CBOR hex of the transaction **body** to be signed. Used to assemble the
  /// final signed transaction once the device returns witnesses.
  final String txBodyCborHex;

  /// CBOR hex of the full unsigned transaction (body + empty witness set).
  ///
  /// Optional: some device libraries parse this to reconstruct the signing
  /// structure; others are driven entirely by structured inputs the adapter
  /// already holds.
  final String? unsignedTxCborHex;

  /// BIP-32 derivation paths the device must produce vkey witnesses for.
  ///
  /// Each path is the full segment list with hardened segments already marked
  /// (i.e. `n | 0x80000000`). Typically the payment path
  /// `[1852', 1815', account', 0, 0]` and, for staking/withdrawals, the stake
  /// path `[1852', 1815', account', 2, 0]`.
  final List<List<int>> signerPaths;

  /// CIP-30 network id the transaction targets (0 = testnet, 1 = mainnet).
  ///
  /// Optional. A device that reconstructs the transaction (e.g. Ledger) needs to
  /// know the network to validate addresses and pick protocol parameters; a
  /// transaction body does not always carry a network id of its own.
  final int? networkId;

  const HardwareSignRequest({
    required this.txBodyCborHex,
    this.unsignedTxCborHex,
    this.signerPaths = const [],
    this.networkId,
  });
}

/// A device-agnostic hardware-wallet transport.
///
/// Implement this for a specific device (Ledger, Trezor) outside the core SDK.
/// The SDK consumes it through [HardwareCip30Wallet], which derives addresses
/// from [getAccountXpub] and assembles the witnesses [signTransaction] returns
/// into submittable transactions.
abstract class HardwareWallet {
  /// Human-readable device identifier (model + connection), for UI/logs.
  String get deviceName;

  /// Fetch the BIP-32 account-level extended public key (xpub) for
  /// [accountIndex] at `m/1852'/1815'/accountIndex'`.
  ///
  /// Returned as 128-char hex of the 64-byte key (32-byte raw Ed25519 public
  /// key followed by a 32-byte chain code) — exactly what [xpubToAccount]
  /// consumes.
  Future<String> getAccountXpub({int accountIndex = 0});

  /// Ask the device to sign [request] and return its raw vkey witnesses.
  ///
  /// The adapter is responsible for translating the transaction into its device
  /// protocol, prompting the user, and collecting the `(publicKey, signature)`
  /// pairs.
  Future<List<HardwareVkeyWitness>> signTransaction(
      HardwareSignRequest request);
}
