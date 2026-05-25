---
title: Phase 2 — Transaction Building & Signing
status: planning
created: 2026-05-24
depends_on: Phase 1 (address validation, BIP32 key derivation, FFI bridge)
target_version: v0.2.0
network: testnet preview only (no mainnet submissions in Phase 2)
---

# Goal: Phase 2 — Transaction Building & Signing

Build on Phase 1's read-only wallet primitives to deliver an end-to-end
"send ADA + native asset" flow on Cardano testnet preview. By the end
of Phase 2 a user of the example app must be able to enter a recipient
address + amount, review the fee, sign locally, and see the transaction
confirmed on-chain.

Backend: continue with `cardano-serialization-lib` v15 (the Phase 1
choice). A backend swap to CML is deferred — do not introduce it mid-phase.

## Success Criteria

**The following must ship together for v0.2.0:**

1. **Rust transaction builder**
   - Wrap CSL's `TransactionBuilder` behind a stable Rust API
   - Inputs / outputs / change / metadata / TTL / fee
   - Returns a serialized CBOR transaction body + tx hash
   - No panics; all failure modes mapped to `CardanoError`
   - Sync API (no `tokio` for tx construction)

2. **Coin selection (largest-first)**
   - Pure Rust, deterministic, side-effect free
   - Input: list of UTXOs + target outputs + fee estimator
   - Output: selected UTXOs + change output(s)
   - Handles: insufficient funds, dust outputs, multi-asset balancing
   - Property tests for the input ≥ output + fee invariant
   - Other algorithms (random-improve, manual) are explicitly out of scope for v0.2.0

3. **Witness construction & signing**
   - Sign a built transaction body with a derived payment key
   - Produce a complete witness set (vkey witnesses for v0.2.0; no native scripts / Plutus)
   - Sync API; private key material never crosses FFI as a `String`
     long-term — for v0.2.0 we accept hex-encoded bech32 keys but
     document the boundary

4. **Multi-asset outputs**
   - Outputs can carry `Value { coin: u64, multiasset: BTreeMap<PolicyId, BTreeMap<AssetName, u64>> }`
   - Min-ada calculation per output (CSL helper) wired in
   - Round-trip CBOR serialize/deserialize verified

5. **Blockfrost provider (Dart-side)**
   - Pure-Dart HTTP client; no FFI calls for network I/O
   - Endpoints: fetch UTXOs for address, fetch protocol parameters, submit transaction
   - API key read from `BLOCKFROST_PROJECT_ID` env (never hardcoded)
   - Retries with exponential backoff for 5xx; surface 4xx as typed errors
   - Testnet preview default; mainnet routing exists but is unused in Phase 2

6. **End-to-end example flow**
   - Example app gains a "Send" screen
   - Fetch UTXOs → user enters recipient + amount → builder computes fee
     and change → user reviews → signs → submits → polls for confirmation
   - At least one successful real submission on testnet preview, with the
     tx hash recorded in `docs/PHASE_2_VERIFICATION.md`

7. **Tests**
   - Unit (Rust): fee math against 10 hand-crafted fixtures, coin selection
     against synthetic UTXO sets, witness signature verification
   - Property (Rust): "outputs + fee ≤ inputs" must hold for all coin
     selection outputs
   - Integration (Dart): build → serialize → deserialize → CBOR identical
   - End-to-end: at least one testnet preview submission in CI (gated by
     `BLOCKFROST_PROJECT_ID` secret), confirmed within 90 seconds
   - All existing Phase 1 tests still pass

8. **Documentation**
   - README "Send a transaction" section with a runnable snippet
   - `docs/PHASE_2_VERIFICATION.md` parallel to Phase 1's verification doc
   - Dartdoc on every new public API with at least one example

## Agent Workstreams

Deploy in parallel where dependencies allow. Coordinator gates ship.

### 1. Research Agent
- **Task:** Survey CSL v15 `TransactionBuilder` API surface, current
  testnet preview protocol parameters, Blockfrost endpoints required,
  CIP-2 largest-first specification, and min-ada calculation rules
- **Deliverable:** `docs/research/phase-2-csl-tx-builder.md` with API
  shape, gotchas (epoch-dependent fee math, witness set ordering),
  reference snippets
- **Blocked by:** none

### 2. Rust TX Builder Agent
- **Task:** Implement `rust/src/tx.rs` wrapping `TransactionBuilder`;
  expose `build_tx`, `min_ada_for_output`, `estimate_fee`; map all CSL
  errors into `CardanoError::TxBuild { reason }`
- **Deliverable:** compiling crate, sync APIs, no panics, `cargo test`
  + `cargo clippy --all-targets -- -D warnings` green
- **Blocked by:** Research Agent

### 3. Coin Selection Agent
- **Task:** Implement `rust/src/coin_selection.rs` with `largest_first`
  function; pure (no I/O); property tests; deterministic ordering
- **Deliverable:** function + tests + at least one proptest invariant
- **Blocked by:** Research Agent (for fee estimator signature)

### 4. Signing Agent
- **Task:** Implement `rust/src/sign.rs` — `sign_tx(body, payment_key)`
  producing complete `TransactionWitnessSet`. Key material handling
  documented; no logging of secrets
- **Deliverable:** sign + verify round-trip test using a Phase 1
  derived key
- **Blocked by:** Rust TX Builder Agent

### 5. Blockfrost Provider Agent (Dart)
- **Task:** `dart/lib/src/providers/blockfrost.dart` — HTTP client,
  typed responses, retry policy, env-driven config. Network code stays
  in Dart per CLAUDE.md (no Rust HTTP in this SDK).
- **Deliverable:** `BlockfrostProvider` class with `fetchUtxos`,
  `fetchProtocolParameters`, `submitTransaction`; tests with mocked
  HTTP + one live test gated by env var
- **Blocked by:** none (parallel with Rust work)

### 6. Test & Verification Agent
- **Task:** Wire up CI for testnet preview submission gated by
  `BLOCKFROST_PROJECT_ID`; produce `docs/PHASE_2_VERIFICATION.md`
  with a recorded successful tx hash
- **Deliverable:** green CI run + verification doc with on-chain proof
- **Blocked by:** TX Builder, Signing, Blockfrost Provider all complete

### 7. Example & Docs Agent
- **Task:** Add "Send" screen to example app, README update, dartdoc
  for new public APIs
- **Deliverable:** example app sends a successful testnet tx end-to-end
- **Blocked by:** Test & Verification Agent (proof of working pipeline)

## Scope Guards

- **Do not** submit to mainnet in Phase 2. Testnet preview only.
- **Do not** implement Plutus scripts, datums, or redeemers (Phase 3).
- **Do not** implement random-improve or other coin selection algorithms
  beyond largest-first for v0.2.0.
- **Do not** put Blockfrost HTTP calls through Rust. Dart-side only.
- **Do not** switch the backend to CML mid-phase.
- **Do not** log or persist private key material. Key bytes stay in
  function scope.
- **Do not** hardcode `BLOCKFROST_PROJECT_ID`. Use env or `.env.example`.
- **Do not** hand-edit `frb_generated.dart` / `lib.dart` — re-run
  codegen.

## Coordinator Checklist

- [ ] Research Agent's findings reviewed and reflected in Rust task scope
- [ ] All Rust modules compile with no `-D warnings` failures
- [ ] All unit + property tests pass on `cargo test`
- [ ] Blockfrost provider tests pass with mocked HTTP
- [ ] At least one live testnet preview tx submitted, hash recorded
- [ ] Example app demonstrates the full send flow on iOS device or simulator
- [ ] `docs/PHASE_2_VERIFICATION.md` exists and is honest about what was
      and wasn't verified
- [ ] CLAUDE.md / memories updated if anything material changed
- [ ] Phase 2.5 mainnet gate is reviewed before any mainnet routing is
      enabled

## Open Questions to Resolve Early

1. **Key material at FFI boundary.** v0.2.0 accepts hex-encoded keys
   across FFI. Long-term we want zeroizing byte buffers and platform
   keystore integration — defer to Phase 4 or Phase 6 but document the
   gap in the verification doc.
2. **Fee buffer.** Should the builder add a small fee buffer (e.g. +1%)
   to absorb protocol parameter shifts mid-build? Research Agent to
   recommend.
3. **Min-ada for multi-asset outputs.** CSL exposes a helper; confirm it
   matches the current protocol version on testnet preview.

---

**Last updated:** 2026-05-24
**Next review:** After Research Agent's report lands
