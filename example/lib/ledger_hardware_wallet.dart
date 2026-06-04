// Ledger hardware-wallet adapter (Phase 4.5, example only).
//
// Implements the SDK's device-agnostic [HardwareWallet] contract on top of
// Vespr's MIT-licensed `ledger_cardano_plus` (the Cardano Ledger-app APDU
// protocol) + `ledger_flutter_plus` (BLE/USB transport). It lives in the example
// app so the core SDK stays free of device dependencies.
//
// Status: the read path (connect → account xpub → addresses/balance/UTxOs via
// [HardwareCip30Wallet]) is complete. On-device transaction signing
// ([signTransaction]) is now implemented: it decomposes the SDK transaction body
// (via the SDK's CSL-backed `decomposeTxBody`), maps it into
// `ledger_cardano_plus`'s structured `ParsedSigningRequest`, drives the device,
// and reconstructs each `(publicKey, signature)` witness by re-deriving the
// signing path's public key from the account xpub (`xpubDerivePublicKey`).
//
// IMPORTANT: this mapping has NOT yet been verified against a physical Ledger
// (none available). The v1.0 gate stays open until a preview round-trip
// (build → sign on device → submit → confirm) succeeds — see
// docs/hardware-wallets.md → "On-device signing checklist". Only the
// ordinary-payment shape is mapped; bodies with certificates/withdrawals/mint/
// collateral are refused (see `HardwareTxBody.hasUnsupportedFeatures`).

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:ledger_cardano_plus/ledger_cardano_plus.dart';

/// A [HardwareWallet] backed by a Ledger device over BLE.
class LedgerHardwareWallet implements HardwareWallet {
  final CardanoLedger _connector;
  CardanoLedgerConnection? _connection;
  LedgerDevice? _device;
  CardanoVersion? _version;

  final Map<int, String> _xpubCache = {};

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
    final cached = _xpubCache[accountIndex];
    if (cached != null) return cached;
    final connection = _requireConnection();
    final xpub = await connection.getExtendedPublicKey(
      request: ExtendedPublicKeyRequest.shelley(accountIndex: accountIndex),
    );
    // The SDK's xpubToAccount expects the 64-byte BIP-32 key: 32-byte raw public
    // key followed by the 32-byte chain code.
    final hex = '${xpub.publicKeyHex}${xpub.chainCodeHex}';
    _xpubCache[accountIndex] = hex;
    return hex;
  }

  @override
  Future<List<HardwareVkeyWitness>> signTransaction(
      HardwareSignRequest request) async {
    final connection = _requireConnection();

    if (request.signerPaths.isEmpty) {
      throw ArgumentError('signTransaction requires at least one signer path.');
    }

    // 1. Decompose the SDK transaction body (authoritative CSL parse).
    final body = decomposeTxBody(txBodyCborHex: request.txBodyCborHex);
    if (body.hasUnsupportedFeatures) {
      throw UnsupportedError(
        'This Ledger adapter only signs ordinary payment transactions. The body '
        'carries features (certificates / withdrawals / mint / collateral / '
        'reference inputs / governance votes) that are not yet mapped.',
      );
    }

    // 2. Map → ledger_cardano_plus ParsedSigningRequest.
    //    Inputs are all spent from the wallet's payment path (the first signer
    //    path); any further signer paths become additional witness paths.
    final paymentPath = LedgerSigningPath.custom(request.signerPaths.first);
    final parsedInputs = body.inputs
        .map((i) => ParsedInput(
              txHashHex: i.txHashHex,
              outputIndex: i.outputIndex,
              path: paymentPath,
            ))
        .toList();

    // CSL serialises plain outputs (no inline datum/script) in the legacy array
    // format, so we map them to ParsedOutput.alonzo to keep the device's
    // re-serialised body byte-identical to ours.
    final parsedOutputs = body.outputs.map((o) {
      return ParsedOutput.alonzo(
        destination:
            ParsedOutputDestination.thirdParty(addressHex: o.addressHex),
        amount: BigInt.parse(o.coin),
        tokenBundle: _toAssetGroups(o.assets),
      );
    }).toList();

    final network = (request.networkId ?? 0) == 1
        ? CardanoNetwork.mainnet()
        : CardanoNetwork.preview();

    final parsedTx = ParsedTransaction(
      network: network,
      inputs: parsedInputs,
      outputs: parsedOutputs,
      fee: BigInt.parse(body.fee),
      ttl: body.ttl == null ? null : BigInt.parse(body.ttl!),
      validityIntervalStart:
          body.validityStart == null ? null : BigInt.parse(body.validityStart!),
    );

    final additionalWitnessPaths = request.signerPaths
        .skip(1)
        .map((p) => LedgerSigningPath.custom(p))
        .toList();

    final signingRequest = ParsedSigningRequest(
      tx: parsedTx,
      signingMode: TransactionSigningModes.ordinaryTransaction,
      additionalWitnessPaths: additionalWitnessPaths,
    );

    // 3. Drive the device.
    final signed = await connection.signTransaction(signingRequest);

    // 4. Rebuild full vkey witnesses: the device returns (path, signature) with
    //    no public key, so re-derive each path's pubkey from the account xpub.
    final witnesses = <HardwareVkeyWitness>[];
    for (final w in signed.witnesses) {
      final path = w.path.signingPath;
      if (path.length < 5) {
        throw StateError('Unexpected Ledger signing path: $path');
      }
      final account = path[2] & 0x7FFFFFFF; // un-harden the account segment
      final role = path[3];
      final index = path[4];
      final xpub = await getAccountXpub(accountIndex: account);
      final vkeyHex = xpubDerivePublicKey(
        accountXpubHex: xpub,
        role: role,
        index: index,
      );
      witnesses.add(HardwareVkeyWitness(
        vkeyHex: vkeyHex,
        signatureHex: w.witnessSignatureHex,
      ));
    }
    return witnesses;
  }

  /// Group flat [HardwareTxAsset]s by policy id into Ledger [ParsedAssetGroup]s.
  static List<ParsedAssetGroup> _toAssetGroups(List<HardwareTxAsset> assets) {
    final byPolicy = <String, List<ParsedToken>>{};
    for (final a in assets) {
      byPolicy.putIfAbsent(a.policyIdHex, () => []).add(
            ParsedToken(assetNameHex: a.assetNameHex, amount: BigInt.parse(a.amount)),
          );
    }
    return byPolicy.entries
        .map((e) => ParsedAssetGroup(policyIdHex: e.key, tokens: e.value))
        .toList();
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
