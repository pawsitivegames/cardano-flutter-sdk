/// Resolves the Blockfrost project id for the example app (SEC-1).
///
/// Resolution order:
/// 1. `--dart-define=BLOCKFROST_PROJECT_ID=...` (use this for real runs / release).
/// 2. Otherwise returns `''` — no key is embedded in shipped binaries, so callers
///    must handle the empty case and fail loudly.
///
/// SECURITY: the previous debug dev key is already in git history; rotate it on
/// Blockfrost before any public release.
String resolveBlockfrostProjectId() {
  const envKey = String.fromEnvironment('BLOCKFROST_PROJECT_ID');
  if (envKey.isNotEmpty) return envKey;
  return '';
}
