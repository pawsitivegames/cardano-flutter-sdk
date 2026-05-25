# Task: Phase 2 Blockfrost Provider Agent (Dart)

**Assigned to:** Blockfrost Provider Agent
**Deliverable:** `dart/lib/src/providers/blockfrost.dart` + tests
**Blocked by:** none (parallel with Rust work)
**Unblocks:** Test & Verification Agent, Example & Docs Agent

## Objective

Implement a pure-Dart Blockfrost client. Per CLAUDE.md, network I/O
stays on the Dart side; we do not put HTTP calls through Rust FFI.

## Scope (only what Phase 2 needs)

- `GET /addresses/{address}/utxos`
- `GET /epochs/latest/parameters`
- `POST /tx/submit` (Content-Type: `application/cbor`, body: raw bytes)

Anything else (asset metadata, account history, etc.) is out of scope.

## API

```dart
class BlockfrostProvider {
  BlockfrostProvider({
    required this.projectId,    // from BLOCKFROST_PROJECT_ID env
    this.network = Network.testnetPreview,
    http.Client? client,
  });

  final String projectId;
  final Network network;

  Future<List<Utxo>> fetchUtxos(String address);
  Future<ProtocolParameters> fetchProtocolParameters();
  Future<String> submitTransaction(Uint8List txCbor); // returns tx hash
}

enum Network { testnetPreview, mainnet }
```

## Requirements

- Base URL derived from `Network`. Mainnet routing exists but is not
  used in Phase 2 — gate it behind a debug-only assertion or a
  `--enable-mainnet` flag.
- `project_id` sent as the `project_id` header on every request.
- Retry policy: 3 retries on 5xx with exponential backoff
  (250ms → 500ms → 1s); no retries on 4xx; surface as typed errors.
- Typed errors:
  - `BlockfrostUnauthorized` (401, 403)
  - `BlockfrostNotFound` (404)
  - `BlockfrostRateLimited` (429) — include `retry-after` if present
  - `BlockfrostBadRequest` (400) — include response body
  - `BlockfrostServerError` (5xx after retries)
- Never log `projectId`. Treat it as a secret.
- Reading `BLOCKFROST_PROJECT_ID` is the caller's responsibility;
  the class just accepts a string. Don't reach into `Platform.environment`
  inside the provider.

## Tests

Mocked-HTTP unit tests (using `package:mockito` or `package:http`'s
`MockClient`):
- `fetchUtxos_parses_response` against a recorded JSON fixture
- `fetchProtocolParameters_maps_fields` to the Dart class
- `submitTransaction_posts_cbor_with_correct_headers`
- `retries_on_500_then_succeeds`
- `does_not_retry_on_400`
- `surfaces_typed_error_for_401`

One live integration test (gated by `BLOCKFROST_PROJECT_ID` env var):
- `fetchProtocolParameters_live_testnet_preview` — hits the real API
  and verifies the response shape. Skipped if env var absent.

## Acceptance

- [ ] `flutter test` passes
- [ ] All mocked tests cover the listed cases
- [ ] Live test is present and is skipped (not failed) when env var
      is missing
- [ ] No `projectId` ever logged
- [ ] Dartdoc on every public method with at least one usage example
