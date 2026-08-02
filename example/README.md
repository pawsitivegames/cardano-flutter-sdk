# Reference Flutter example

This non-publishable app exercises the public `cardano_flutter_rs` package on
native platforms and demonstrates the scoped CML-JS/CIP-30 web entrypoint. It
is a reference and verification app, not a production wallet.

## Run the native example

From the repository root:

```bash
cd dart && flutter pub get
cd ../example && flutter pub get
flutter run
```

The app runs native SDK diagnostics on startup and exposes the address, key,
transaction, provider, CIP-30, CIP-45, seed-vault, account, staking, minting,
message, and experimental hardware-wallet demos. If native diagnostics fail,
the app reports a recoverable error and exposes **Retry diagnostics**.

Provider-backed screens require a Cardano Preview Blockfrost project ID:

```bash
flutter run --dart-define=BLOCKFROST_PROJECT_ID=your_project_id
```

Without that value, local diagnostics still run, but provider-backed actions
remain unavailable. Never commit a real project ID or other credentials.

## Run the scoped web example

The native `main.dart` imports `dart:ffi`, so browser builds must use the
web-safe target:

```bash
flutter run -d chrome -t lib/main_web.dart
flutter build web -t lib/main_web.dart
```

The web host page initializes the CML and message-signing WASM bridge. See
[`web/index.html`](web/index.html) and the [web backend guide](../docs/web-backend.md)
for the supported web boundary and limitations.

## Verify the example

```bash
flutter analyze --no-fatal-warnings
flutter test
```

Analysis warnings for the example's explicitly experimental hardware-wallet
and scoped web APIs are expected and remain visible; new analyzer errors or
unexpected warnings must be investigated.

For the repository-wide release contract, platform evidence, and external
gates, start with the [documentation index](../docs/README.md) and
[`docs/PLAN.md`](../docs/PLAN.md).
