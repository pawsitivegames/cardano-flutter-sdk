# Mutation testing scope

Mutation testing checks whether a test fails when a meaningful implementation
decision is deliberately broken. The authoritative `cargo-mutants` workflow
uses generated mutants and reports killed, missed, and untested mutations; see
the [getting-started guide](https://mutants.rs/getting-started.html) and
[result interpretation](https://mutants.rs/using-results.html).

## Current local audit

`cargo-mutants` is not installed in this checkout (`RUSTUP_TOOLCHAIN=stable
cargo mutants --version` reports `no such command`). A reversible, manually
scoped audit covered the highest-risk seams instead of claiming a mutation
score:

| Mutation | Verification | Result |
| --- | --- | --- |
| Disable the strict odd-length guard in `decodeHex` | `flutter test test/hex_test.dart` | Killed by the malformed-input test |
| Discard assets during greedy coin selection | `cargo test coin_selection::tests::randomized_selection_conserves_coin_and_assets` | Killed; Proptest minimized the failure to two 1.5 ADA inputs and the seed is retained in `rust/proptest-regressions/coin_selection.txt` |
| Return no hardware witnesses from extraction | `cargo test hardware` | Killed by deterministic identity and randomized fixed-width roundtrip tests |
| Accept any CIP-30 header credential | `cargo test cip30::tests` | Killed by forged-identity verification |
| Ignore the web BIP-39 passphrase | browser wallet harness | Killed: 3 of 19 checks failed, covering payment hash, stake hash, and address |

The temporary mutation of the defensive coin-selection dust-fixing asset
accumulator survived the generated property. This is recorded rather than
hidden: the selector's current break condition already requires
`accumulated_coin >= target + final_fee + min_change`, so a selected result
cannot enter that branch with dust under the present algorithm. The property
therefore claims greedy-path coverage only; the branch remains a defensive
future-change seam, not evidence of a green mutation score.

All mutations were restored before verification. These results show that the
listed tests detect the selected faults; they do not prove exhaustive mutation
coverage, cryptographic correctness, device behavior, provider behavior, or
production safety. A full `cargo-mutants` run remains an optional toolchain
enhancement, not a reason to weaken the current test gates.

The audit follows the current
[`cargo-mutants` mutant model](https://mutants.rs/mutants.html), while keeping
Flutter unit/browser, physical-device, provider, store, and production evidence
as separate claims.
