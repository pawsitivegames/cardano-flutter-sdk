import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'blockfrost_errors.dart';

/// Network selection for Blockfrost API.
enum Network { testnetPreview, mainnet }

/// Status of a submitted transaction as reported by Blockfrost.
class TransactionStatus {
  /// Transaction hash (64 hex chars).
  final String hash;

  /// Whether the transaction has been included in a block.
  final bool confirmed;

  /// Block height at which the transaction was confirmed, if available.
  final int? blockHeight;

  TransactionStatus({
    required this.hash,
    required this.confirmed,
    this.blockHeight,
  });

  @override
  String toString() =>
      'TransactionStatus(hash: ${hash.substring(0, 8)}…, confirmed: $confirmed'
      '${blockHeight != null ? ', block: $blockHeight' : ''})';
}

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

/// Information about a stake account (reward address).
class AccountInfo {
  /// Bech32 stake address.
  final String stakeAddress;

  /// Whether the stake key is currently registered on-chain.
  final bool isRegistered;

  /// Total controlled stake in lovelace (delegated + rewards).
  final BigInt controlledStake;

  /// Lifetime rewards sum in lovelace.
  final BigInt rewardsSum;

  /// Withdrawable rewards in lovelace (available for withdrawal right now).
  final BigInt withdrawableReward;

  /// Bech32 pool ID of the currently delegated pool, or null if not delegated.
  final String? poolId;

  const AccountInfo({
    required this.stakeAddress,
    required this.isRegistered,
    required this.controlledStake,
    required this.rewardsSum,
    required this.withdrawableReward,
    this.poolId,
  });

  @override
  String toString() =>
      'AccountInfo(stake: $stakeAddress, registered: $isRegistered, '
      'withdrawable: $withdrawableReward, pool: $poolId)';
}

/// On-chain usage summary for a single address, from Blockfrost
/// `GET /addresses/{address}`.
///
/// Used for BIP-44 gap-limit scanning and HD account discovery: an address is
/// "used" if it has ever appeared in a transaction ([txCount] > 0), even if its
/// current UTxO balance is zero. A never-seen address returns 404 from
/// Blockfrost, surfaced as `null` from [BlockfrostProvider.fetchAddressMetadata].
class AddressMetadata {
  /// The bech32 address this metadata describes.
  final String address;

  /// Number of transactions this address has appeared in. 0 means unused.
  final int txCount;

  /// Lifetime lovelace received by this address.
  final BigInt totalReceived;

  /// Lifetime lovelace sent from this address.
  final BigInt totalSent;

  const AddressMetadata({
    required this.address,
    required this.txCount,
    required this.totalReceived,
    required this.totalSent,
  });

  /// Whether this address has ever been used on-chain.
  bool get isUsed => txCount > 0;

  @override
  String toString() => 'AddressMetadata(address: $address, txCount: $txCount, '
      'received: $totalReceived, sent: $totalSent)';
}

/// Information about a stake pool.
class PoolInfo {
  /// Bech32 pool ID.
  final String poolId;

  /// Ticker symbol (e.g. "TICKER").
  final String? ticker;

  /// Human-readable pool name.
  final String? name;

  /// Fixed cost in lovelace (as a string to avoid precision loss).
  final String? fixedCost;

  /// Pool margin as a fraction 0.0–1.0.
  final double? margin;

  /// Pool saturation level 0.0–1.0 (>1 = oversaturated).
  final double? saturation;

  const PoolInfo({
    required this.poolId,
    this.ticker,
    this.name,
    this.fixedCost,
    this.margin,
    this.saturation,
  });

  @override
  String toString() =>
      'PoolInfo(id: $poolId, ticker: $ticker, margin: $margin)';
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

  /// Fetches the current chain tip's absolute slot (`/blocks/latest`).
  ///
  /// Use it to set a transaction TTL (e.g. `tip + 7200` ≈ 2h) so the tx expires
  /// rather than remaining submittable forever (TX-3). Returns the slot number.
  Future<int> fetchTipSlot() async {
    final uri = Uri.parse('${network.baseUrl}/blocks/latest');
    final response = await _makeRequest('GET', uri);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final slot = json['slot'];
    if (slot is int) return slot;
    if (slot is num) return slot.toInt();
    throw const FormatException('blocks/latest: missing or non-numeric slot');
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

  /// Fetches the current status of a submitted transaction.
  ///
  /// Returns [TransactionStatus] with [TransactionStatus.confirmed] = false if the
  /// transaction is not yet in a block (Blockfrost returns 404 for pending TXs).
  ///
  /// Throws [BlockfrostUnauthorized], [BlockfrostRateLimited], [BlockfrostServerError],
  /// or [BlockfrostNetworkError] on API errors.
  ///
  /// Example:
  /// ```dart
  /// final status = await provider.fetchTransactionStatus(txHash);
  /// if (status.confirmed) {
  ///   print('Confirmed in block \${status.blockHeight}');
  /// } else {
  ///   print('Still pending…');
  /// }
  /// ```
  Future<TransactionStatus> fetchTransactionStatus(String txHash) async {
    final uri = Uri.parse('${network.baseUrl}/txs/$txHash');
    final response = await _makeRequest('GET', uri);

    if (response.statusCode == 404) {
      return TransactionStatus(hash: txHash, confirmed: false);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return TransactionStatus(
      hash: txHash,
      confirmed: true,
      blockHeight: json['block_height'] as int?,
    );
  }

  /// Polls Blockfrost until [txHash] is confirmed or [timeout] expires.
  ///
  /// Queries [fetchTransactionStatus] every [pollInterval] (default 10 s).
  /// Returns the confirmed [TransactionStatus] on success.
  ///
  /// Throws [TimeoutException] if the transaction is not confirmed within [timeout].
  /// Other [BlockfrostException] subtypes are propagated immediately (no retry).
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   final status = await provider.pollTransactionConfirmation(
  ///     txHash,
  ///     pollInterval: const Duration(seconds: 10),
  ///     timeout: const Duration(minutes: 5),
  ///   );
  ///   print('Confirmed in block \${status.blockHeight}');
  /// } on TimeoutException {
  ///   print('Not confirmed yet — check the explorer');
  /// }
  /// ```
  Future<TransactionStatus> pollTransactionConfirmation(
    String txHash, {
    Duration pollInterval = const Duration(seconds: 10),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (true) {
      final status = await fetchTransactionStatus(txHash);
      if (status.confirmed) return status;

      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'Transaction $txHash not confirmed within ${timeout.inSeconds}s',
          timeout,
        );
      }

      final delay = remaining < pollInterval ? remaining : pollInterval;
      await Future.delayed(delay);
    }
  }

  // ── Staking queries (Phase 4.1) ────────────────────────────────────────────

  /// Fetches account info for a stake address.
  ///
  /// Returns null if the stake address is not yet registered on-chain (404).
  ///
  /// Throws [BlockfrostUnauthorized], [BlockfrostRateLimited],
  /// [BlockfrostServerError], or [BlockfrostNetworkError] on API errors.
  ///
  /// Example:
  /// ```dart
  /// final info = await provider.fetchAccountInfo('stake_test1u...');
  /// if (info == null) print('Not yet registered');
  /// else print('Withdrawable: ${info.withdrawableReward} lovelace');
  /// ```
  Future<AccountInfo?> fetchAccountInfo(String stakeAddress) async {
    final uri = Uri.parse('${network.baseUrl}/accounts/$stakeAddress');
    final response = await _makeRequest('GET', uri);

    if (response.statusCode == 404) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AccountInfo(
      stakeAddress: json['stake_address'] as String,
      isRegistered: json['active'] as bool? ?? false,
      controlledStake:
          BigInt.parse((json['controlled_amount'] as String?) ?? '0'),
      rewardsSum: BigInt.parse((json['rewards_sum'] as String?) ?? '0'),
      withdrawableReward:
          BigInt.parse((json['withdrawable_amount'] as String?) ?? '0'),
      poolId: json['pool_id'] as String?,
    );
  }

  /// Fetches lifetime usage stats for an address via
  /// `GET /addresses/{address}/total` (this is the endpoint that carries
  /// `tx_count` — `/addresses/{address}` only returns the current balance).
  ///
  /// Returns `null` if the address has never been seen on-chain (Blockfrost
  /// 404). Use [isAddressUsed] for a simple boolean, or this for the counts.
  ///
  /// Example:
  /// ```dart
  /// final meta = await provider.fetchAddressMetadata(addr);
  /// final used = meta?.isUsed ?? false;
  /// ```
  Future<AddressMetadata?> fetchAddressMetadata(String address) async {
    final uri = Uri.parse('${network.baseUrl}/addresses/$address/total');
    final response = await _makeRequest('GET', uri);

    if (response.statusCode == 404) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    BigInt lovelaceOf(dynamic sumList) {
      if (sumList is List) {
        for (final entry in sumList) {
          if (entry is Map && entry['unit'] == 'lovelace') {
            return BigInt.parse((entry['quantity'] as String?) ?? '0');
          }
        }
      }
      return BigInt.zero;
    }

    return AddressMetadata(
      address: json['address'] as String? ?? address,
      txCount: json['tx_count'] as int? ?? 0,
      totalReceived: lovelaceOf(json['received_sum']),
      totalSent: lovelaceOf(json['sent_sum']),
    );
  }

  /// Whether [address] has ever been used on-chain (`tx_count > 0`).
  ///
  /// A never-seen address (Blockfrost 404) counts as unused. This is the lookup
  /// [HdWalletDiscovery] uses for gap-limit scanning; pass `provider.isAddressUsed`.
  Future<bool> isAddressUsed(String address) async {
    final meta = await fetchAddressMetadata(address);
    return meta?.isUsed ?? false;
  }

  /// Fetches a page of active pool IDs (bech32 strings).
  ///
  /// Example:
  /// ```dart
  /// final pools = await provider.fetchPoolIds(page: 1, count: 20);
  /// ```
  Future<List<String>> fetchPoolIds({int page = 1, int count = 20}) async {
    final uri = Uri.parse(
        '${network.baseUrl}/pools?page=$page&count=$count&order=desc');
    final response = await _makeRequest('GET', uri);

    final List<dynamic> jsonList = jsonDecode(response.body);
    return jsonList.cast<String>();
  }

  /// Fetches details for a specific stake pool.
  ///
  /// Throws [BlockfrostNotFound] if the pool does not exist.
  ///
  /// Example:
  /// ```dart
  /// final info = await provider.fetchPoolInfo('pool1...');
  /// print('${info.ticker}: margin ${info.margin}');
  /// ```
  Future<PoolInfo> fetchPoolInfo(String poolId) async {
    final uri = Uri.parse('${network.baseUrl}/pools/$poolId');
    final response = await _makeRequest('GET', uri);

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final marginStr = json['margin_cost'] as String?;
    final saturationStr = json['live_saturation'] as String?;
    return PoolInfo(
      poolId: poolId,
      fixedCost: json['fixed_cost'] as String?,
      margin: marginStr != null ? double.tryParse(marginStr) : null,
      saturation: saturationStr != null ? double.tryParse(saturationStr) : null,
    );
  }

  /// Fetches pool metadata (name, ticker) for a specific stake pool.
  ///
  /// Returns an empty map if the pool has no metadata.
  ///
  /// Example:
  /// ```dart
  /// final meta = await provider.fetchPoolMetadata('pool1...');
  /// print(meta['name']);
  /// ```
  Future<Map<String, String?>> fetchPoolMetadata(String poolId) async {
    final uri = Uri.parse('${network.baseUrl}/pools/$poolId/metadata');
    final response = await _makeRequest('GET', uri);

    if (response.statusCode == 404) return {};

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'name': json['name'] as String?,
      'ticker': json['ticker'] as String?,
      'description': json['description'] as String?,
      'homepage': json['homepage'] as String?,
    };
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
        throw BlockfrostNetworkError(
            'Request timeout after $maxRetries retries');
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
      coinsPerUtxoByte: int.parse(json['coins_per_utxo_size'] as String),
      maxTxSize: json['max_tx_size'] as int,
      maxValueSize: int.parse(json['max_val_size'] as String),
      keyDeposit: int.parse(json['key_deposit'] as String),
      poolDeposit: int.parse(json['pool_deposit'] as String),
    );
  }
}
