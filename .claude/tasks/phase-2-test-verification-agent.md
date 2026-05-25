# Task: Phase 2 Test & Verification Agent

**Assigned to:** Test & Verification Agent
**Deliverable:** CI workflow + `docs/PHASE_2_VERIFICATION.md`
**Blocked by:** Rust TX Builder, Signing, Blockfrost Provider all complete
**Unblocks:** Example & Docs Agent

## Objective

Prove the Phase 2 pipeline works end to end on testnet preview. Wire
CI to run unit + property tests on every push, and to run one live
testnet submission per CI run when the secret is present.

## Deliverables

1. **GitHub Actions workflow update** (extend the existing Phase 1
   workflow rather than creating a new one):
   - Run `cargo test`, `cargo clippy --all-targets -- -D warnings`,
     `cargo fmt --check`
   - Run `flutter test` (both unit and integration)
   - If `BLOCKFROST_PROJECT_ID` is present in repo secrets, run the
     live testnet integration test and post the tx hash as a PR
     comment (or workflow summary)
   - Cache Cargo and pub deps to keep runs under ~10 minutes

2. **End-to-end test** (`example/integration_test/send_flow_test.dart`
   or equivalent):
   - Derive a known testnet wallet from a fixture mnemonic
   - Fetch UTXOs via Blockfrost
   - Build a small (1 ADA) self-send transaction
   - Sign it
   - Submit via Blockfrost
   - Poll `/tx/{hash}` until confirmed or 90s elapse
   - Assert the hash appears on-chain

   This test runs in CI only when the secret is present; locally it
   skips with a clear message.

3. **`docs/PHASE_2_VERIFICATION.md`** — parallel to Phase 1's
   verification doc. Sections:
   - What was tested (unit, property, live)
   - What was *not* tested (mainnet, hardware wallets, Plutus —
     deferred to later phases)
   - At least one confirmed testnet preview tx hash, with link to
     a block explorer
   - Known gaps and risks carried into Phase 2.5 / Phase 3
   - Sign-off date

## Acceptance

- [ ] CI green on a fresh PR
- [ ] Live testnet submission recorded with on-chain hash
- [ ] Verification doc honest about what was and wasn't covered
- [ ] No regressions in Phase 1 tests
- [ ] CLAUDE.md updated if any project-level fact changed during
      Phase 2 (e.g. a new env var that future sessions need to know
      about)
