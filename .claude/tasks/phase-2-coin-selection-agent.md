# Task: Phase 2 Coin Selection Agent — Largest-First (CIP-2)

**Assigned to:** Coin Selection Agent
**Deliverable:** `rust/src/coin_selection.rs` + unit + property tests
**Blocked by:** Research Agent (fee estimator signature)
**Unblocks:** Test & Verification Agent, Example & Docs Agent

## Objective

Implement the largest-first coin selection algorithm per CIP-2 as a
pure Rust function: no I/O, no globals, no randomness. Deterministic
in input ordering.

Scope is **largest-first only** for v0.2.0. Random-improve and manual
selection are out of scope; do not implement them.

## API

```rust
pub struct CoinSelectionResult {
    pub selected_inputs: Vec<TxInput>,
    pub change_outputs: Vec<TxOutput>,
    pub fee: u64,
}

pub fn largest_first(
    available_utxos: Vec<TxInput>,
    target_outputs: Vec<TxOutput>,
    change_address: String,
    params: ProtocolParams,
) -> Result<CoinSelectionResult, CardanoError>;
```

(Re-use the types defined by the Rust TX Builder Agent in `tx.rs`.
Do not duplicate.)

## Algorithm

1. Sort `available_utxos` by ADA-value descending (deterministic
   tiebreak on tx_hash + output_index).
2. Greedily add inputs until `sum(inputs) >= sum(target_outputs) + estimated_fee + min_change_ada`.
3. Estimate fee using a placeholder body size + the running witness
   count. Re-estimate after each input added (fee grows with size).
4. Produce a change output(s) for the residual. If residual ADA is
   below min-ada, add another input.
5. For multi-asset targets: ensure selected inputs cover both the ADA
   sum *and* each target asset quantity. If not, keep pulling inputs
   that carry the missing asset.
6. If the available pool is exhausted before requirements are met:
   `Err(CardanoError::InsufficientFunds { needed, available })`.

## Errors to surface

- `CardanoError::InsufficientFunds { needed_lovelace, available_lovelace }`
- `CardanoError::InsufficientAsset { policy_id, asset_name, needed, available }`
- `CardanoError::DustChange { residual_lovelace, min_required }`

## Tests

Unit:
- `largest_first_single_input_covers` — one big UTXO covers everything
- `largest_first_picks_multiple_inputs` — needs three UTXOs, picks
  the three largest
- `largest_first_insufficient_funds` — returns `InsufficientFunds`
- `largest_first_multi_asset_needs_asset_carrier` — pure-ADA largest
  UTXO doesn't carry the target asset, algorithm pulls a smaller UTXO
  that does
- `largest_first_change_below_min_ada_pulls_more` — first attempt
  leaves dust change, algorithm adds another input
- `largest_first_deterministic_ordering` — same inputs, same output
  (snapshot test)

Property (use `proptest` if Cargo dep already present, otherwise
roll a simple seeded loop):
- `invariant_inputs_cover_outputs_plus_fee` — for any randomly
  generated UTXO set + target, if Ok, then
  `sum_inputs.ada == sum_outputs.ada + change.ada + fee`
- `invariant_no_asset_lost` — for every (policy, asset), sum across
  inputs == sum across outputs + change

## Acceptance

- [ ] Module added to `rust/src/lib.rs`
- [ ] All listed tests pass
- [ ] No I/O, no randomness, no statics
- [ ] `cargo clippy --all-targets -- -D warnings` passes
- [ ] Property invariants documented in module-level doc comment
