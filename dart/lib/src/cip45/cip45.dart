// CIP-45 dApp↔wallet connector — protocol core (Phase 4.4).
//
// CIP-45 establishes a peer-to-peer channel between a mobile dApp and a wallet
// using WebTorrent trackers for discovery and WebRTC for the data channel (see
// the `bugout` library referenced by the spec). The connection identifier is an
// Ed25519 public key shared as a CIP-13 Cardano URI; once connected, the dApp
// invokes CIP-30 method names as RPCs and the wallet responds.
//
// This file ships the **transport-agnostic** core:
//   • [Cip45ConnectionUri] — build/parse the CIP-13 `web+cardano://` URI.
//   • [Cip45WalletHandler] — bridge incoming RPC calls to a [Cip30Wallet] and
//     produce the API-announcement payload sent during the handshake.
//   • [Cip45Transport] — the interface a WebTorrent/WebRTC backend implements.
//
// Wiring an actual transport (peer-discovery keypair, trackers, WebRTC) and the
// platform deep-link registration for `web+cardano://` is intentionally left to
// an integration layer; the protocol logic here is fully unit-tested.

import '../cip30/cip30_wallet.dart';

/// Error thrown when a dApp requests a CIP-45 RPC method the wallet does not
/// expose.
class Cip45UnsupportedMethod implements Exception {
  final String method;
  Cip45UnsupportedMethod(this.method);
  @override
  String toString() => 'Cip45UnsupportedMethod: $method';
}

/// Error thrown when an RPC request is missing required parameters.
class Cip45InvalidParams implements Exception {
  final String message;
  Cip45InvalidParams(this.message);
  @override
  String toString() => 'Cip45InvalidParams: $message';
}

/// A CIP-45 connection identifier encoded as a CIP-13 Cardano URI.
///
/// Format (CIP-13): `web+cardano://connect/v1?identifier=<public_key>`, where
/// `<public_key>` is the hex Ed25519 public key used for peer discovery.
///
/// Example:
/// ```dart
/// final uri = Cip45ConnectionUri(identifier: pubKeyHex);
/// print(uri.toUriString()); // web+cardano://connect/v1?identifier=...
///
/// final parsed = Cip45ConnectionUri.parse(scanned);
/// print(parsed.identifier);
/// ```
class Cip45ConnectionUri {
  /// The URI scheme defined by CIP-13.
  static const String scheme = 'web+cardano';

  /// The authority segment for a CIP-45 connection URI.
  static const String authority = 'connect';

  /// Hex-encoded Ed25519 public key used as the peer-discovery identifier.
  final String identifier;

  /// Protocol version segment (default `v1`).
  final String version;

  const Cip45ConnectionUri({
    required this.identifier,
    this.version = 'v1',
  });

  /// Serialize to the canonical CIP-13 URI string.
  String toUriString() =>
      '$scheme://$authority/$version?identifier=$identifier';

  /// Parse a CIP-13 connection URI, validating scheme, authority, and path.
  ///
  /// Throws [FormatException] if the URI is not a valid CIP-45 connection URI.
  static Cip45ConnectionUri parse(String input) {
    // Uri.parse treats `web+cardano` as the scheme and `connect` as the host.
    final uri = Uri.parse(input.trim());
    if (uri.scheme != scheme) {
      throw FormatException('Expected scheme "$scheme"', input);
    }
    if (uri.host != authority) {
      throw FormatException('Expected authority "$authority"', input);
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) {
      throw FormatException('Expected a single version path segment', input);
    }
    final id = uri.queryParameters['identifier'];
    if (id == null || id.isEmpty) {
      throw FormatException('Missing "identifier" query parameter', input);
    }
    return Cip45ConnectionUri(identifier: id, version: segments.first);
  }

  @override
  String toString() => toUriString();

  @override
  bool operator ==(Object other) =>
      other is Cip45ConnectionUri &&
      other.identifier == identifier &&
      other.version == version;

  @override
  int get hashCode => Object.hash(identifier, version);
}

/// A transport for CIP-45 (WebTorrent discovery + WebRTC data channel).
///
/// The protocol core is transport-agnostic: a concrete implementation handles
/// peer discovery (announcing/looking up the identifier on trackers), the WebRTC
/// connection, and delivering RPC frames. It should forward each inbound request
/// to the handler registered via [onRequest] and send back the returned result.
abstract class Cip45Transport {
  /// Begin announcing/listening for the peer identified by [Cip45ConnectionUri].
  Future<void> start();

  /// Register the callback invoked for each inbound RPC request.
  ///
  /// The callback receives the method name and positional params and must return
  /// a JSON-encodable result (or throw to signal an error to the peer).
  void onRequest(
    Future<Object?> Function(String method, List<dynamic> params) handler,
  );

  /// Tear down the connection and stop announcing.
  Future<void> close();
}

/// Wallet-side CIP-45 request handler.
///
/// Bridges incoming CIP-45 RPC calls (which use CIP-30 method names) to a
/// [Cip30Wallet], and produces the API-announcement payload a wallet sends to
/// the dApp during the handshake.
///
/// Wire it to a [Cip45Transport] like so:
/// ```dart
/// final handler = Cip45WalletHandler(wallet: cip30Wallet, name: 'MyWallet');
/// transport.onRequest(handler.handleRequest);
/// await transport.start();
/// // ... and send handler.apiAnnouncement() to the dApp on connect.
/// ```
class Cip45WalletHandler {
  /// The underlying CIP-30 wallet that fulfils requests.
  final Cip30Wallet wallet;

  /// Human-readable wallet name announced to the dApp.
  final String name;

  /// API version announced to the dApp.
  final String version;

  Cip45WalletHandler({
    required this.wallet,
    this.name = 'cardano_flutter_rs',
    this.version = '1.0.0',
  });

  /// The CIP-30 method names exposed over CIP-45.
  static const List<String> methods = [
    'getNetworkId',
    'getUtxos',
    'getBalance',
    'getUsedAddresses',
    'getUnusedAddresses',
    'getChangeAddress',
    'getRewardAddresses',
    'signTx',
    'signData',
    'submitTx',
  ];

  /// The CIP-30 method names this wallet exposes over CIP-45.
  List<String> get supportedMethods => methods;

  /// The API-announcement payload sent to the dApp during the handshake.
  ///
  /// Mirrors the CIP-45 proof-of-concept shape:
  /// `{ "api": { "version": ..., "name": ..., "methods": [...] } }`.
  Map<String, dynamic> apiAnnouncement() => {
        'api': {
          'version': version,
          'name': name,
          'methods': supportedMethods,
        },
      };

  /// Whether [method] is supported by this wallet.
  bool supports(String method) => methods.contains(method);

  /// Dispatch an inbound CIP-45 RPC request to the wallet.
  ///
  /// [params] are positional, matching the CIP-30 method signatures:
  /// - `signTx`: `[txCborHex, partialSign?]`
  /// - `signData`: `[addressHex, payloadHex]`
  /// - `submitTx`: `[signedTxCborHex]`
  /// - all `get*` methods take no params.
  ///
  /// Returns a JSON-encodable result. `signData` returns
  /// `{ "signature": ..., "key": ... }`.
  ///
  /// Throws [Cip45UnsupportedMethod] for unknown methods and
  /// [Cip45InvalidParams] for missing/invalid parameters.
  Future<Object?> handleRequest(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    switch (method) {
      case 'getNetworkId':
        return wallet.getNetworkId();
      case 'getUtxos':
        return wallet.getUtxos();
      case 'getBalance':
        return wallet.getBalance();
      case 'getUsedAddresses':
        return wallet.getUsedAddresses();
      case 'getUnusedAddresses':
        return wallet.getUnusedAddresses();
      case 'getChangeAddress':
        return wallet.getChangeAddress();
      case 'getRewardAddresses':
        return wallet.getRewardAddresses();
      case 'signTx':
        final tx = _stringParam(params, 0, 'txCborHex');
        final partialSign =
            params.length > 1 ? (params[1] as bool? ?? false) : false;
        return wallet.signTx(tx, partialSign: partialSign);
      case 'signData':
        final addr = _stringParam(params, 0, 'addressHex');
        final payload = _stringParam(params, 1, 'payloadHex');
        final sig = await wallet.signData(payload, addressHex: addr);
        return {'signature': sig.signature, 'key': sig.key};
      case 'submitTx':
        final tx = _stringParam(params, 0, 'signedTxCborHex');
        return wallet.submitTx(tx);
      default:
        throw Cip45UnsupportedMethod(method);
    }
  }

  static String _stringParam(List<dynamic> params, int index, String name) {
    if (params.length <= index || params[index] is! String) {
      throw Cip45InvalidParams('Expected string param "$name" at index $index');
    }
    return params[index] as String;
  }
}
