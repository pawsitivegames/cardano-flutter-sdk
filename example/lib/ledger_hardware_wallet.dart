// Ledger hardware-wallet adapter (Phase 4.5, example only).
//
// Implements the SDK's device-agnostic [HardwareWallet] contract on top of
// Vespr's MIT-licensed `ledger_cardano_plus` (the Cardano Ledger-app APDU
// protocol) + `ledger_flutter_plus` (BLE/USB transport). It lives in the example
// app so the core SDK stays free of device dependencies.
//
// Status: the read path (connect → account xpub → addresses/balance/UTxOs via
// [HardwareCip30Wallet]) is complete. On-device transaction signing
// ([signTransaction]) requires translating the SDK's transaction into
// `ledger_cardano_plus`'s structured `ParsedSigningRequest`, which must be
// validated against a physical device — see docs/hardware-wallets.md. Until that
// is verified on hardware it throws, rather than ship an unverified mapping.

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:ledger_cardano_plus/ledger_cardano_plus.dart';

/// A [HardwareWallet] backed by a Ledger device over BLE.
class LedgerHardwareWallet implements HardwareWallet {
  final CardanoLedger _connector;
  CardanoLedgerConnection? _connection;
  LedgerDevice? _device;
  CardanoVersion? _version;

  LedgerHardwareWallet._(this._connector);

  /// Create a BLE-based Ledger adapter.
  ///
  /// [onPermissionRequest] is invoked when the platform needs Bluetooth/location
  /// permissions; return `true` once they are granted.
  factory LedgerHardwareWallet.ble({
    required Future<bool> Function({required bool unsupported}) onPermissionRequest,
  }) {
    return LedgerHardwareWallet._(
      CardanoLedger.ble(onPermissionRequest: onPermissionRequest),
    );
  }

  /// Scan for nearby Ledger devices.
  Stream<LedgerDevice> scanForDevices() => _connector.scanForDevices();

  /// Connect to [device] and fetch its Cardano-app version.
  Future<CardanoVersion> connect(LedgerDevice device) async {
    final connection = await _connector.connect(device);
    _connection = connection;
    _device = device;
    final version = await connection.getVersion();
    _version = version;
    return version;
  }

  /// The connected device's Cardano-app version, once [connect] has run.
  CardanoVersion? get version => _version;

  @override
  String get deviceName {
    final d = _device;
    final v = _version;
    final base = d == null ? 'Ledger' : 'Ledger ${d.name}';
    return v == null ? base : '$base (Cardano app ${v.versionName})';
  }

  @override
  Future<String> getAccountXpub({int accountIndex = 0}) async {
    final connection = _requireConnection();
    final xpub = await connection.getExtendedPublicKey(
      request: ExtendedPublicKeyRequest.shelley(accountIndex: accountIndex),
    );
    // The SDK's xpubToAccount expects the 64-byte BIP-32 key: 32-byte raw public
    // key followed by the 32-byte chain code.
    return '${xpub.publicKeyHex}${xpub.chainCodeHex}';
  }

  @override
  Future<List<HardwareVkeyWitness>> signTransaction(
      HardwareSignRequest request) async {
    // Implementing this means mapping the SDK transaction in `request` into a
    // ledger_cardano_plus `ParsedSigningRequest` (ParsedTransaction: inputs with
    // their address-derivation params, outputs, fee, ttl, certificates, …),
    // calling `_connection.signTransaction(parsed)`, then turning each returned
    // `Witness` (a signing path + signature, with NO public key) back into a
    // [HardwareVkeyWitness] by deriving that path's public key from the account
    // xpub. That structured mapping must be validated on a physical Ledger
    // before we claim it works, so it is intentionally not shipped unverified.
    //
    // See docs/hardware-wallets.md → "On-device signing checklist".
    throw UnimplementedError(
      'Ledger transaction signing is implemented at the protocol level in the '
      'SDK (assembleVkeyWitnessSet) but the device-side ParsedSigningRequest '
      'mapping is pending on-device verification. See docs/hardware-wallets.md.',
    );
  }

  /// Disconnect and release the device.
  Future<void> disconnect() async {
    await _connection?.disconnect();
    _connection = null;
  }

  /// Release all transport resources.
  Future<void> dispose() async {
    await _connector.dispose();
  }

  CardanoLedgerConnection _requireConnection() {
    final c = _connection;
    if (c == null) {
      throw StateError('Ledger not connected — call connect() first.');
    }
    return c;
  }
}
