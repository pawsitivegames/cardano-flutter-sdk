# Independent Project Strategy

**Status:** This document supersedes the Catalyst funding strategy. The project is now **fully independent and self-funded**.

---

## Why Independent

- **No external pressure.** Build at sustainable pace, ship when ready.
- **No scope constraints.** Build the SDK that should exist, not the one that fits a grant category.
- **No political coordination.** Skip the "win the vote" calculus. Technical merit is the only metric.
- **No deadline-driven shortcuts.** Quality, correctness, and documentation get the time they deserve.
- **Long-term ownership.** This SDK exists to serve Cardano mobile, not to satisfy milestone payouts.

---

## What Changes vs. Original Plan

### Removed
- ❌ Project Catalyst submission strategy (timing, voter persuasion, proposal positioning)
- ❌ "Phase 1 must ship before submitting" deadline pressure
- ❌ Funding milestone gates (Phase 2.5 mainnet validation no longer driven by audit budget)
- ❌ ADA price assumptions and budget calculations
- ❌ Competitive positioning aimed at voters (technical positioning still matters)

### Retained
- ✅ Architectural thesis: Rust + CSL/CML/Pallas via FFI > pure Dart
- ✅ MIT license + community ownership model
- ✅ Phase-based roadmap structure (timelines now flexible)
- ✅ Verification rigor at each phase
- ✅ Open-source governance (CONTRIBUTING.md, etc.)
- ✅ Technical recommendations from critical review (Android 16KB, CML over CSL, web strategy)

### Added
- ✅ "Ship when ready" milestone gates
- ✅ Optional collaboration with TokeoPay/Vespr (technical only, not political)
- ✅ Permission to take longer to do things right

---

## Revised Approach

### Pace

**No fixed timeline.** Phases ship when:
1. All public APIs have tests
2. Linting passes (clippy, flutter analyze)
3. Integration tests pass on Cardano testnet
4. Example app demonstrates the feature end-to-end
5. Documentation is complete and tested by a fresh clone
6. You're confident enough to recommend it to a stranger

**Realistic personal estimate:** 10-18 months to v1.0 working part-time. Could be faster if dedicated full-time; could be longer if maintenance/learning is heavy. Either is fine.

### Scope

**Build for actual usage, not for completeness.** Specifically:

| Priority | Phase | Reasoning |
|---|---|---|
| **HIGH** | Read-only wallet (Phase 1) | Foundation for everything else |
| **HIGH** | Transaction building (Phase 2) | Vespr's biggest gap; differentiates from pure-Dart competitors |
| **HIGH** | Plutus/NFTs (Phase 3) | No Flutter competitor has this |
| **MEDIUM** | Wallet connectors (Phase 4) | Could integrate with Vespr instead of greenfield |
| **MEDIUM** | Web support (Phase 5) | Lower mobile priority |
| **LOW** | Desktop (Phase 5) | Nice-to-have, not core mission |
| **LOW** | Advanced features (Phase 6) | Build when users ask for them |

### Naming

Since you're not competing for voter attention, the name needs to:
1. **Avoid confusion** with Vespr's `cardano_flutter_sdk` on pub.dev
2. **Signal the architecture** (CSL/CML/FFI is the differentiator)
3. **Be findable** by users searching for "Cardano Flutter"

**Recommended package names (pick one):**
- `cardano_flutter_rs` — explicitly signals Rust/FFI architecture
- `cardano_canon` — "canonical" SDK with CDDL-correct types
- `cardano_native` — implies native (FFI) implementation
- `cardano_csl` — names the architecture differentiator

Whichever you pick, document the rationale in README so users understand the positioning.

### Tech Stack (Updated)

Based on critical review findings:

**Definite:**
- **flutter_rust_bridge v2.x** — best Dart↔Rust FFI option
- **Rust** stable, edition 2021
- **MIT license**

**Recommended switch:**
- **CSL → CML (Cardano Multiplatform Lib)** as primary backend
  - More active maintenance (April 2025 release vs CSL's August 2025)
  - Same correctness story (generated from CDDL spec)
  - Co-maintained by Emurgo + dcSpark
- **Architect for backend swap** — feature flags or trait abstractions so CSL/CML/Pallas can be swapped
- **Plan a Pallas v1.0 migration** before v1.0 (the community is moving here)

**Platform strategy:**
- **Native (iOS/Android/macOS/Linux/Windows):** Rust FFI via flutter_rust_bridge
- **Web:** Dart JS interop to CSL/CML's official npm WASM package (don't tunnel Rust through frb-WASM)
- **Android 16KB page size** compatibility required from Phase 1 (Play Store mandatory since Nov 2025)

### Collaboration (Optional)

**TokeoPay (CardanoKit Swift):**
- They're solving the same architectural problem for Swift
- Potential: extract a shared `cardano_core` Rust crate that powers both Swift (UniFFI) and Dart (frb)
- Reduces duplicate work; benefits both projects
- **Action:** Reach out when Phase 1 is ~50% complete with a concrete proposal

**Vespr Wallet (Dart SDK):**
- They have CIP-30/CIP-45 WalletConnect coverage
- You have (will have) transaction building, Plutus, FFI correctness
- Potential: complementary; users can use both
- **Action:** Skip unless integration becomes useful in Phase 4

**Both collaborations are technical, not political.** No grant proposal in the loop. If they're useful, do them. If not, ship independently.

---

## Sustainability (Without Grants)

### How an independent OSS project survives

1. **Solve a real problem.** If the SDK is genuinely useful, dApp developers will use it. If they use it, they'll file bugs and contribute fixes.

2. **Low maintenance burden.** Strong testing + good architecture means less time spent on regressions. Each hour of upfront testing saves 10 hours of debugging.

3. **Reasonable contribution barrier.** A clear CONTRIBUTING.md, a clean architecture, dartdoc + tests on everything = first-time contributors can land PRs.

4. **Pin to upstream stability.** CSL/CML release cycles are slow. Track them, but don't churn on every minor bump. Major version bumps are deliberate, with testnet validation.

5. **Document the "why."** When future contributors (or future-you) ask "why is this designed this way?", the answer should be in the repo, not in your head.

### Optional revenue streams (if ever needed)

- **Paid support contracts** for wallets/dApps deploying production usage
- **OpenCollective** for community donations (transparent)
- **Sponsorships** from companies using the SDK (no obligation)
- **None of these are required.** The project works fine as pure OSS.

---

## Decision Framework

**When in doubt, ask:**

1. **Does this serve actual users?** If yes, do it. If "it might attract a grant," skip.
2. **Is this technically right?** If you'd be embarrassed to recommend it to a friend, redo it.
3. **Is this maintainable?** If it requires constant babysitting, refactor or remove.
4. **Is the architecture right?** Cheap shortcuts now become expensive later. Pay the upfront cost.

---

## What This Means for Existing Documents

- **`docs/project-plan.md`** — Section 7 (Catalyst strategy) is now obsolete. Mark it deprecated; keep for historical context.
- **`.claude/goals/PHASES_WITH_VERIFICATION.md`** — Timeline table is now flexible. Remove Catalyst funding column. Phases ship when ready.
- **`.claude/goals/CRITICAL_REVIEW.md`** — Issues 1 and 2 (naming, tech stack) still apply. Issue 3 (funding) is now moot.
- **`.claude/goals/OPEN_SOURCE_STRATEGY.md`** — Drop "Catalyst Grants" section from funding model. Keep open-source governance and community sustainability.
- **`CONTRIBUTING.md`** — No changes needed.

---

## Immediate Next Steps (When You Resume)

1. **Pick a package name** (recommend `cardano_flutter_rs` or `cardano_canon`)
2. **Choose initial backend** (recommend CML, structure for swap)
3. **Start Phase 0** (FFI bootstrap, Android 16KB compat verified, hello-world end-to-end)
4. **No urgency.** Take the time to do Phase 0 right.

---

**Created:** 2026-05-24
**Supersedes:** Catalyst funding strategy in project-plan.md §7 and OPEN_SOURCE_STRATEGY.md §7
