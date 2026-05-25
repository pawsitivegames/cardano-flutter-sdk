import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'blockfrost_errors.dart';

/// Network selection for Blockfrost API.
enum Network { testnetPreview, mainnet }

extension _NetworkExt on Network {
  /// Returns the base URL for the Blockfrost API.
  String get baseUrl {
    switch (this) {
      case Network.testnetPreview:
        return 'https://cardano-preview.blockfrost.io/api/v0';
      case Network.mainnet:
        return 'https://cardano-mainnet.blockfrost.io/api/v0';
    }
  }
}

/// Represents a UTXO (unspent transaction output).
class Utxo {
  /// Transaction hash of the UTXO.
  final String txHash;

  /// Output index within the transaction.
  final int outputIndex;

  /// Address holding this UTXO.
  final String address;

  /// Amount in lovelace (ADA base unit).
  final BigInt coin;

  /// Native tokens in this UTXO.
  /// Map structure: policy_id (hex string) -> asset_name (hex string) -> quantity
  final Map<String, Map<String, BigInt>> assets;

  Utxo({
    required this.txHash,
    required this.outputIndex,
    required this.address,
    required this.coin,
    required this.assets,
  });

  @override
  String toString() =>
      'Utxo(txHash: $txHash, index: $outputIndex, coin: $coin, assets: ${assets.length})';
}

/// Blockfrost protocol parameters.
class ProtocolParameters {
  /// Coefficient for transaction fee calculation (per-byte).
  final int minFeeA;

  /// Constant for transaction fee calculation.
  final int minFeeB;

  /// Lovelace per UTxO byte for min ADA calculation.
  final int coinsPerUtxoByte;

  /// Maximum transaction size in bytes.
  final int maxTxSize;

  /// Maximum value size in bytes.
  final int maxValueSize;

  /// Deposit required to register a new stake address (in lovelace).
  final int keyDeposit;

  /// Deposit required to register a new pool (in lovelace).
  final int poolDeposit;

  ProtocolParameters({
    required this.minFeeA,
    required this.minFeeB,
    required this.coinsPerUtxoByte,
    required this.maxTxSize,
    required this.maxValueSize,
    required this.keyDeposit,
    required this.poolDeposit,
  });

  @override
  String toString() =>
      'ProtocolParameters(minFeeA: $minFeeA, minFeeB: $minFeeB, '
      'coinsPerUtxoByte: $coinsPerUtxoByte, maxTxSize: $maxTxSize)';
}

/// Blockfrost HTTP provider for fetching UTxOs, protocol parameters, and submitting transactions.
///
/// This provider communicates with the Blockfrost API to query blockchain data.
/// Network I/O is handled entirely in Dart (not through Rust FFI).
///
/// Example:
/// ```dart
/// final provider = BlockfrostProvider(
///   projectId: 'your_blockfrost_project_id',
///   network: Network.testnetPreview,
/// );
///
/// final utxos = await provider.fetchUtxos('addr_test1q...');
/// final params = await provider.fetchProtocolParameters();
/// ```
class BlockfrostProvider {
  /// Blockfrost project ID (API key). Must not be logged or exposed.
  final String projectId;

  /// Network to query.
  final Network network;

  /// HTTP client for making requests.
  final http.Client _httpClient;

  /// Creates a new Blockfrost provider.
  ///
  /// [projectId]: Your Blockfrost project ID. Treated as a secret and never logged.
  /// [network]: The Cardano network to query (default: testnetPreview).
  /// [client]: Optional custom HTTP client (used for testing with mocks).
  BlockfrostProvider({
    required this.projectId,
    this.network = Network.testnetPreview,
    http.Client? client,
  }) : _httpClient = client ?? http.Client();

  /// Fetches all UTxOs for a given address.
  ///
  /// Returns a list of UTxOs held by the address. If the address has no UTxOs,
  /// returns an empty list.
  ///
  /// Throws [BlockfrostUnauthorized] if the project ID is invalid.
  /// Throws [BlockfrostRateLimited] if rate-limited.
  /// Throws [BlockfrostServerError] if the API fails after retries.
  /// Throws [BlockfrostNetworkError] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final utxos = await provider.fetchUtxos('addr_test1q...');
  /// for (final utxo in utxos) {
  ///   print('UTXO: \${utxo.txHash}#\${utxo.outputIndex} = \${utxo.coin} lovelace');
  /// }
  /// ```
  Future<List<Utxo>> fetchUtxos(String address) async {
    final uri = Uri.parse('${network.baseUrl}/addresses/$address/utxos');
    final response = await _makeRequest('GET', uri);

    // 404 means address has no UTxOs, treat as empty list
    if (response.statusCode == 404) {
      return [];
    }

    final List<dynamic> jsonList = jsonDecode(response.body);
    return jsonList.map((json) => _parseUtxo(json)).toList();
  }

  /// Fetches the current protocol parameters from the network.
  ///
  /// These parameters define transaction fees, size limits, and other protocol
  /// constraints. They should be queried once per session.
  ///
  /// Throws [BlockfrostUnauthorized] if the project ID is invalid.
  /// Throws [BlockfrostRateLimited] if rate-limited.
  /// Throws [BlockfrostServerError] if the API fails after retries.
  /// Throws [BlockfrostNetworkError] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final params = await provider.fetchProtocolParameters();
  /// print('Min fee A: \${params.minFeeA}');
  /// print('Min fee B: \${params.minFeeB}');
  /// ```
  Future<ProtocolParameters> fetchProtocolParameters() async {
    final uri = Uri.parse('${network.baseUrl}/epochs/latest/parameters');
    final response = await _makeRequest('GET', uri);

    final json = jsonDecode(response.body);
    return _parseProtocolParameters(json);
  }

  /// Submits a signed transaction to the network.
  ///
  /// [txCbor]: Raw CBOR-encoded transaction bytes (from `Transaction.to_bytes()`).
  /// Returns the transaction hash (64 hex characters).
  ///
  /// Throws [BlockfrostBadRequest] if the transaction is invalid (bad witnesses,
  /// fee too low, UTxO already spent, etc.). The error body contains the ledger's
  /// rejection reason.
  /// Throws [BlockfrostUnauthorized] if the project ID is invalid.
  /// Throws [BlockfrostRateLimited] if rate-limited.
  /// Throws [BlockfrostServerError] if the API fails after retries.
  /// Throws [BlockfrostNetworkError] on network errors.
  ///
  /// Example:
  /// ```dart
  /// final txHash = await provider.submitTransaction(signedTxBytes);
  /// print('Transaction submitted: \$txHash');
  /// ```
  Future<String> submitTransaction(Uint8List txCbor) async {
    final uri = Uri.parse('${network.baseUrl}/tx/submit');
    final response = await _makeRequest(
      'POST',
      uri,
      body: txCbor,
      contentType: 'application/cbor',
    );

    final json = jsonDecode(response.body);
    return json as String;
  }

  /// Makes an HTTP request with retry logic and error handling.
  ///
  /// Returns a successful response or throws an appropriate [BlockfrostException].
  /// Note: 404 responses are returned as-is; the caller handles them.
  Future<http.Response> _makeRequest(
    String method,
    Uri uri, {
    Uint8List? body,
    String contentType = 'application/json',
  }) async {
    const maxRetries = 3;
    const baseDelayMs = 250;

    int attemptCount = 0;

    while (true) {
      attemptCount++;
      try {
        http.Response response;

        switch (method) {
          case 'GET':
            response = await _httpClient
                .get(uri, headers: _getHeaders(contentType))
                .timeout(const Duration(seconds: 30));
          case 'POST':
            response = await _httpClient
                .post(
              uri,
              headers: _getHeaders(contentType),
              body: body,
            )
                .timeout(const Duration(seconds: 30));
          default:
            throw BlockfrostNetworkError('Unsupported HTTP method: $method');
        }

        // Special handling for 404 - return as-is without error
        if (response.statusCode == 404) {
          return response;
        }

        return _handleResponse(response);
      } on BlockfrostException catch (e) {
        // If it's a 5xx error and we haven't exhausted retries, retry
        if (e is BlockfrostServerError && attemptCount <= maxRetries) {
          final delayMs =
              baseDelayMs * (1 << (attemptCount - 1)); // exponential backoff
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        rethrow;
      } on TimeoutException {
        if (attemptCount <= maxRetries) {
          final delayMs = baseDelayMs * (1 << (attemptCount - 1));
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        throw BlockfrostNetworkError('Request timeout after $maxRetries retries');
      } catch (e) {
        throw BlockfrostNetworkError('Network error: $e');
      }
    }
  }

  /// Handles HTTP responses and throws appropriate exceptions.
  http.Response _handleResponse(http.Response response) {
    switch (response.statusCode) {
      case 200 || 201:
        return response;

      case 400:
        throw BlockfrostBadRequest(
          'Bad request',
          response.body,
        );

      case 401 || 403:
        throw BlockfrostUnauthorized(
          'Unauthorized: invalid or expired project ID',
        );

      case 404:
        throw BlockfrostNotFound('Resource not found');

      case 429:
        final retryAfter = _parseRetryAfter(response);
        throw BlockfrostRateLimited(
          'Rate limited',
          retryAfter: retryAfter,
        );

      case >= 500:
        throw BlockfrostServerError(
          'Server error (${response.statusCode})',
        );

      default:
        throw BlockfrostNetworkError(
          'HTTP ${response.statusCode}: ${response.body}',
        );
    }
  }

  /// Parses the Retry-After header from a rate-limit response.
  Duration? _parseRetryAfter(http.Response response) {
    final retryAfter = response.headers['retry-after'];
    if (retryAfter == null) return null;

    try {
      final seconds = int.parse(retryAfter);
      return Duration(seconds: seconds);
    } catch (_) {
      return null;
    }
  }

  /// Constructs HTTP headers for requests.
  Map<String, String> _getHeaders(String contentType) {
    return {
      'project_id': projectId,
      'Content-Type': contentType,
    };
  }

  /// Parses a UTXO from Blockfrost JSON response.
  Utxo _parseUtxo(dynamic json) {
    final address = json['address'] as String;
    final txHash = json['tx_hash'] as String;
    final outputIndex = json['output_index'] as int;

    final assets = <String, Map<String, BigInt>>{};
    BigInt coin = BigInt.zero;

    final amount = json['amount'] as List<dynamic>;
    for (final asset in amount) {
      final unit = asset['unit'] as String;
      final quantity = BigInt.parse(asset['quantity'] as String);

      if (unit == 'lovelace') {
        coin = quantity;
      } else {
        // Multi-asset: unit = policyId (28 bytes) + assetName (variable)
        // Split at 56 hex chars (28 bytes)
        final policyId = unit.substring(0, 56);
        final assetName = unit.substring(56);

        assets.putIfAbsent(policyId, () => {});
        assets[policyId]![assetName] = quantity;
      }
    }

    return Utxo(
      txHash: txHash,
      outputIndex: outputIndex,
      address: address,
      coin: coin,
      assets: assets,
    );
  }

  /// Parses protocol parameters from Blockfrost JSON response.
  ProtocolParameters _parseProtocolParameters(dynamic json) {
    return ProtocolParameters(
      minFeeA: json['min_fee_a'] as int,
      minFeeB: json['min_fee_b'] as int,
      coinsPerUtxoByte:
          int.parse(json['coins_per_utxo_size'] as String),
      maxTxSize: json['max_tx_size'] as int,
      maxValueSize: int.parse(json['max_val_size'] as String),
      keyDeposit: int.parse(json['key_deposit'] as String),
      poolDeposit: int.parse(json['pool_deposit'] as String),
    );
  }
}
