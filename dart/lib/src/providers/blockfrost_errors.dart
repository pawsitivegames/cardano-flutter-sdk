/// Errors returned by the Blockfrost provider.
///
/// Each error type corresponds to a specific HTTP response code or network condition.

/// Base exception for all Blockfrost errors.
abstract class BlockfrostException implements Exception {
  final String message;

  BlockfrostException(this.message);

  @override
  String toString() => message;
}

/// Unauthorized access (401) or forbidden (403).
///
/// Indicates the project ID is invalid or has insufficient permissions.
class BlockfrostUnauthorized extends BlockfrostException {
  BlockfrostUnauthorized(super.message);
}

/// Resource not found (404).
///
/// This typically occurs when an address has no UTxOs. The provider
/// treats this as an empty result rather than an error, so this is
/// rarely thrown directly.
class BlockfrostNotFound extends BlockfrostException {
  BlockfrostNotFound(super.message);
}

/// Rate limited (429).
///
/// The client has exceeded the Blockfrost rate limit.
/// The [retryAfter] field, if present, indicates the number of seconds
/// to wait before retrying.
class BlockfrostRateLimited extends BlockfrostException {
  final Duration? retryAfter;

  BlockfrostRateLimited(String message, {this.retryAfter})
      : super(message);

  @override
  String toString() {
    if (retryAfter != null) {
      return '$message (retry after ${retryAfter!.inSeconds}s)';
    }
    return message;
  }
}

/// Bad request (400).
///
/// The request was malformed or invalid. The [responseBody] contains
/// the error details from the API.
class BlockfrostBadRequest extends BlockfrostException {
  final String responseBody;

  BlockfrostBadRequest(String message, this.responseBody)
      : super(message);

  @override
  String toString() => '$message: $responseBody';
}

/// Server error (5xx) after retries.
///
/// The Blockfrost server encountered an error. The SDK will automatically
/// retry 5xx errors with exponential backoff (250ms → 500ms → 1s).
/// If all retries fail, this exception is thrown.
class BlockfrostServerError extends BlockfrostException {
  BlockfrostServerError(super.message);
}

/// Network or connection error.
///
/// Indicates a problem with the network connection or client-side
/// communication with Blockfrost.
class BlockfrostNetworkError extends BlockfrostException {
  BlockfrostNetworkError(super.message);
}
