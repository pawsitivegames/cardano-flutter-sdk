# Cardano Flutter SDK — Project Memory

> This file is read by Claude Code at the start of every session. Keep it under 200 lines.

## Project overview

A production-grade, open-source Flutter SDK for the Cardano blockchain. Architecture: thin Dart API → `flutter_rust_bridge` → Rust wrapper crate → `cardano-multiplatform-lib` (CML). Targets iOS, Android, macOS, Linux, Windows via Rust FFI; web via direct JS interop to CML's npm package (not via Rust FFI).

**Why CML over CSL:** CML is co-maintained by Emurgo + dcSpark, more actively released (last update April 2025 vs CSL's August 2025), uses the same CDDL-spec generation approach, and has better CBOR preservation. Architect the Rust wrapper to make the backend swappable (CSL/CML/Pallas) via feature flags or trait abstractions — Pallas v1.0 may become the strategic long-term choice.

**Why FFI:** Generated from Cardano's official CDDL spec. By wrapping in Rust and exposing via FFI, we get correctness for free and protocol upgrades flow downstream automatically rather than requiring SDK rewrites.

**The plan:** see `docs/project-plan.md` and `.claude/goals/INDEPENDENT_PROJECT_STRATEGY.md`. Critical review of stack choices in `.claude/goals/CRITICAL_REVIEW.md`.

## Current state

Phase 0 and Phase 1 shipped. Phase 2 (transaction building, signing,
Blockfrost submission, multi-asset outputs) is in planning — see
`.claude/goals/phase-2.md` and `.claude/tasks/phase-2-*`.

Decisions made:
- **Package name:** `cardano_flutter_rs` (pub.dev) + crate name `cardano_flutter_rs` (crates.io)
- **Active backend:** **CSL** (`cardano-serialization-lib` v15.0). The original plan named CML as primary; Phase 1 shipped on CSL instead. A backend swap to CML or Pallas remains a long-term option (trait abstraction not yet introduced — add when a second backend lands). Do not switch mid-phase.
- **FFI:** flutter_rust_bridge v2.12 (pinned)
- **iOS binary:** dynamic framework (`dart/ios/Libs/cardano_flutter_rs.framework`), not the static `.a` originally planned
- **Platform strategy:** Native via Rust FFI; web via JS interop to CML/CSL npm (not Rust)
- **Independent project, no Catalyst funding** — see `.claude/goals/INDEPENDENT_PROJECT_STRATEGY.md`

When you start a session, the next task is likely:
- **Phase 2:** dispatch the agents in `.claude/tasks/phase-2-*` —
  Research → TX Builder + Coin Selection + Blockfrost Provider (parallel)
  → Signing → Test & Verification → Example & Docs

## Tech stack (planned versions; verify against latest at install time)

- **Rust:** stable, edition 2021
- **`cardano-multiplatform-lib` (CML):** `6.2.x` or latest (primary backend)
- **`cardano-serialization-lib` (CSL):** optional feature flag for compatibility
- **`pallas` (txpipe):** v1.0+; planned migration target before v1.0
- **`flutter_rust_bridge`:** `2.12.x` or latest 2.x (pin exact version; breaking changes occur)
- **Flutter:** `>=3.19.0`
- **Dart:** `>=3.3.0 <4.0.0`
- **Android NDK:** r28+ (required for 16KB page size compatibility, mandatory since Nov 2025)
- **Android AGP:** 8.7.3+ (required for 16KB page size)
- **Provider APIs:** Blockfrost (primary), Maestro, Koios (added later)

## Repository conventions

- All Rust code lives in `rust/` with `cardano_flutter_rs` as the crate name.
- All Dart code lives in `dart/` with `cardano_flutter_rs` as the package name (avoids collision with Vespr's `cardano_flutter_sdk` on pub.dev; signals the Rust/FFI architecture).
- Generated bindings go in `dart/lib/src/bridge_generated.dart` — **never edit by hand**.
- The reference Flutter app lives in `example/` and depends on the local `dart/` package via path.
- Use MIT license throughout (matches CML/CSL upstream).
- Semantic versioning. Pre-1.0 = `0.x.y`. v1.0 = first version that's safe to recommend for production mainnet usage (definition is technical readiness, not feature checklist).

## Style rules

- **Rust:** `cargo fmt` and `cargo clippy --all-targets -- -D warnings` must pass.
- **Dart:** follow `flutter_lints`. Public APIs need dartdoc comments with example usage.
- **Async:** Dart side uses `Future`/`Stream` exclusively. Rust side uses `tokio` only where network I/O is involved; signing/serialization stays sync.
- **Errors:** never panic in Rust public API. Use `thiserror`-derived error types; map to Dart exceptions via `flutter_rust_bridge`.
- **Tests:** every public function needs at least one test. Cardano testnet preview is the integration target — test mnemonics in `tests/fixtures/`.

## Build / test / lint commands

These are placeholders until the project is bootstrapped — update with real commands as you go.

```bash
# Generate Dart bindings from Rust
flutter_rust_bridge_codegen generate

# Run Rust tests
cd rust && cargo test

# Run Dart tests
cd dart && flutter test

# Lint everything
cd rust && cargo clippy --all-targets -- -D warnings && cd ../dart && flutter analyze

# Run the example app
cd example && flutter run
```

## Important external references

- **CML repo (primary):** https://github.com/dcSpark/cardano-multiplatform-lib
- **CSL repo (compat backend):** https://github.com/Emurgo/cardano-serialization-lib
- **Pallas repo (migration target):** https://github.com/txpipe/pallas
- **flutter_rust_bridge:** https://cjycode.com/flutter_rust_bridge
- **Android 16KB page size docs:** https://developer.android.com/guide/practices/page-sizes
- **Cardano developer portal:** https://developers.cardano.org
- **Blockfrost API:** https://blockfrost.io
- **CIP-30 (dApp connector):** https://cips.cardano.org/cip/CIP-30
- **CIP-45 (mobile WalletConnect):** https://cips.cardano.org/cip/CIP-45
- **CIP-1852 (HD derivation):** https://cips.cardano.org/cip/CIP-1852
- **Reference: CardanoKit (Swift, same architecture pattern):** https://github.com/TokeoPay/CardanoKit
- **Reference: Vespr's Dart SDK (pure-Dart competitor):** https://github.com/vespr-wallet/cardano_dart_sdk

## Project context

This is an **independent, self-funded, open-source project**. No external funders, no milestone deadlines, no votes to win. The driver is pure technical merit and long-term value to the Cardano mobile ecosystem.

What this means in practice:
1. **Quality over speed.** No artificial timeline pressure. Ship Phase N when it's actually production-ready.
2. **Scope is yours to set.** Build what serves the SDK's mission, not what fits an external funding category.
3. **Differentiation is technical.** Win by being the most correct, well-tested, well-documented SDK — not by being first or loudest.
4. **Coordination is optional.** Reach out to TokeoPay (CardanoKit) or Vespr if technical collaboration helps; otherwise focus on shipping.
5. **Sustainability via utility.** If real dApps adopt the SDK, contributors appear and maintain it organically. No grant dependency.

## Things NOT to do

- Do not reimplement Cardano cryptography in pure Dart. Use CML (or CSL/Pallas) via FFI.
- Do not put on-chain data through the Rust layer if it can be fetched in Dart via REST. Keep the FFI surface minimal.
- Do not wrap every CML type for v0.1. Wrap only what the example app needs.
- Do not skip tests against testnet preview before a CML/CSL major-version bump.
- Do not edit `bridge_generated.dart` by hand — re-run codegen.
- Do not tunnel Rust through frb-WASM for web. Use CML's official npm package via Dart JS interop instead.
- Do not skip Android 16KB page size verification — it's mandatory for Play Store since Nov 2025.
- Do not hardcode a single backend. Use feature flags / trait abstractions so CSL/CML/Pallas can be swapped.

## Communication style preferences for Claude Code

- Be concise. Skip preamble.
- When proposing a change, show the diff or the exact file contents you'd write.
- Push back on bad ideas. Don't agree to architectural choices that violate the project plan without flagging it.
- If a CSL API has changed since the project plan was written, surface the discrepancy rather than working around it.
