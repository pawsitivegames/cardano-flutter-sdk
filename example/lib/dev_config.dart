import 'package:flutter/foundation.dart';

/// Resolves the Blockfrost project id for the example app (SEC-1).
///
/// Resolution order:
/// 1. `--dart-define=BLOCKFROST_PROJECT_ID=...` (use this for real runs / release).
/// 2. In **debug builds only**, a known preview-testnet dev key, with a warning.
/// 3. In **release builds**, returns `''` — no key is embedded in shipped binaries,
///    so callers must handle the empty case and fail loudly.
///
/// SECURITY: the debug dev key is already in git history; rotate it on Blockfrost
/// before any public release. It is never compiled into a release build.
String resolveBlockfrostProjectId() {
  const envKey = String.fromEnvironment('BLOCKFROST_PROJECT_ID');
  if (envKey.isNotEmpty) return envKey;
  if (kDebugMode) {
    debugPrint(
      '[Cardano SDK] WARNING: BLOCKFROST_PROJECT_ID not set — using the '
      'debug-only dev key. Pass --dart-define=BLOCKFROST_PROJECT_ID=<key> '
      'for real use; release builds embed no key.',
    );
    return _devKeyDebugOnly;
  }
  return '';
}

// Debug-only convenience key (Blockfrost preview testnet). Never used in release.
// TODO(SEC-1): rotate before public release — this value is in git history.
const String _devKeyDebugOnly = 'previewAmnr5VzpgWZkHMg8BibEiC4Vqkcq4G7e';
