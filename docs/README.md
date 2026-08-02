# Documentation index

Use this index to find the shortest verified path for a repository task. The
release contract and roadmap live in [`PLAN.md`](PLAN.md); the other pages below
support that contract and do not replace it.

## Start here

- [Project plan and release gates](PLAN.md) — current architecture, roadmap,
  platform matrix, verification boundaries, blockers, and version gates.
- [Web backend](web-backend.md) — CML-JS scope, CSL↔CML byte-parity contract,
  browser harness, and web limitations.
- [Android verification](android-verification.md) — ARM64 emulator and 16 KB
  page-size evidence, with the physical-device gap called out explicitly.
- [macOS packaging](macos-packaging.md) — framework packaging, codesigning,
  embedded-runtime verification, and known provider limitations.

## Feature and integration guides

- [CIP-45 transport](cip45-transport.md) — supported WebView transport and the
  intentionally incomplete native WebRTC scaffold.
- [CIP-45 testing](cip45-testing.md) — two-peer test procedure and recovery
  guidance for tracker/WebRTC failures.
- [Cross-wallet verification](cross-wallet-verify.md) — how to capture and
  verify third-party CIP-30 `signData` output without exposing credentials.
- [Fixture data contract](fixture-data-contract.md) — executable shape,
  identity, provenance, and coverage guarantees for interoperability JSON.
- [Feature verification ledger](FEATURE_VERIFICATION_LEDGER.md) — contracts,
  failure states, acceptance criteria, and evidence boundaries by feature.
- [Property-based testing](property-testing.md) — generated invariants,
  shrinking scope, and the limits of randomized evidence.
- [Mutation testing](mutation-testing.md) — reversible high-risk mutations,
  killed-test evidence, and the limits of the local mutation audit.
- [Hardware wallets](hardware-wallets.md) — xpub/read/sign seams and the
  physical-device evidence still required before promotion.
- [Seed encryption](seed-encryption.md) — CFS1 format, Rust crypto boundary,
  secure-storage composition, and zeroization limitations.

## Security, research, and historical verification

- [Security review](security-review-phase7.md) — historical findings and fixes;
  treat `PLAN.md` and current code as the present-state authority.
- [Pallas feasibility](pallas-feasibility.md) — backend-swap research and its
  conformance-first recommendation.
- [0.12.0 RC verification](RC_0_12_0_RELEASE_VERIFICATION.md) — dated local
  release evidence and external gates; it is a historical report, not a live
  status dashboard.
- [Phase verification reports](PHASE_1_VERIFICATION.md) — historical phase 1,
  [phase 2](PHASE_2_VERIFICATION.md), and [phase 3](PHASE_3_VERIFICATION.md)
  implementation evidence.
- [CSL transaction-builder research](research/phase-2-csl-tx-builder.md) —
  historical protocol and API research; current behavior is governed by code
  and the release plan.

When a page contains a dated verification result, preserve its historical date
and scope. Update current claims in `PLAN.md` and the package README instead of
rewriting old evidence to look current.
