# Reference example mobile usability audit — 2026-08-03

Scope: native reference-app first run and home-screen capability navigation on a
physical Android phone. This is a focused audit of the highest-impact journey,
not a claim that every secondary screen has been device-verified.

## Acceptance criteria

- A first-time user can distinguish local SDK diagnostics from provider-backed
  network demos before tapping an action.
- A provider-backed action cannot appear enabled when
  `BLOCKFROST_PROJECT_ID` is absent.
- Diagnostics failure remains visible and retryable.
- The home screen remains scrollable and its primary controls meet the existing
  Flutter tap-target checks. WCAG 2.2 target-size guidance is a design input,
  not proof of conformance by itself.
- Device, local widget, provider, store, and production evidence remain
  separate.

## Verification matrix

| Surface | Result | Evidence and limits |
| --- | --- | --- |
| Home / first run | Verified | Widget test at `390x844`; physical CPH2841 Android 16 capture at 411dp. Diagnostics completed and the missing-provider state was visible. |
| Provider action gating | Fixed + verified | With an empty project ID, Send/Mint/Stake/CIP-30/CIP-45/Ledger/Accounts are wired unavailable; widget and physical screenshot verify the Send action is disabled. |
| Diagnostics failure → retry | Verified locally | Injected widget runner covers visible failure, retry, and recovery. No native failure injection was needed for this contract. |
| CIP-45 deep-link lifecycle | Fixed + verified locally | `MyApp` retains the subscription, cancels it in `dispose`, and a stream regression test proves forwarding stops after cancellation. Physical two-peer transport remains external. |
| Narrow layout | Limited | `390x844` widget layout and 411dp physical capture exercised. The 320x568, 375x667, and 430x932 matrix remains pending. |
| Secondary screens, forms, keyboard | Limited | Source and existing tests inspected; no complete physical path was run for every screen or native keyboard state. |
| Provider / transaction journeys | External | Require a live Preview Blockfrost project and intentional testnet operations. No provider or production claim is made here. |

## Fix log

### Fixed: provider-backed actions no longer dead-end

Before: after local diagnostics derived keys, network actions were enabled even
when the project ID was absent. The first physical Android capture showed the
enabled “Open Send ADA demo” control alongside the missing-key warning; the
route could only show a setup snackbar.

After: `example/lib/main.dart` centralizes the readiness predicate and gates all
network-backed home actions. The warning names the affected capabilities and
keeps the setup command visible. Local-only actions retain their own readiness
rules. `example/test/widget_test.dart` covers the predicate and rendered Send
state.

### Fixed: deep-link subscription ownership

Before: the home state listened to the CIP-45 URI stream without retaining the
subscription, so disposing the app could leave the callback attached to the
platform stream. After: `MyApp` owns the subscription and cancels it in
`dispose`; the forwarding helper’s cancellation behavior is regression-tested.

## Deferred findings

- The same Android run reported 109 skipped frames during startup. The initial
  hypothesis that the example called synchronous key derivation was rejected:
  the public async wrapper already dispatches the generated asynchronous FRB
  entrypoint. A frame-timeline/profile investigation is still needed before a
  performance edit is justified.
- Capability grouping and the remaining 320/375/430 viewport checks are useful
  follow-ups, but the current `Wrap` layout did not provide direct evidence of
  clipping in this pass.

## Commands and artifacts

- `PUB_CACHE=/tmp/cardano_flutter_sdk_pub_cache flutter test test/widget_test.dart`
- `PUB_CACHE=/tmp/cardano_flutter_sdk_pub_cache flutter analyze --no-fatal-warnings`
- `PUB_CACHE=/tmp/cardano_flutter_sdk_pub_cache flutter run --no-pub -d 3B165700BKF00000 -t lib/main.dart --dart-define=BLOCKFROST_PROJECT_ID=`
- Physical after capture: `/tmp/cardano-sdk-android-home-after.png`
- Initial candidate review: `/tmp/frontend-experience-review-20260803-cardano-flutter-sdk.html`
