# Task: Phase 2 Rust TX Builder Agent

**Assigned to:** Rust TX Builder Agent
**Deliverable:** `rust/src/tx.rs` + tests; FFI-exposed builder API
**Blocked by:** Research Agent
**Unblocks:** Signing Agent, Test & Verification Agent

## Objective

Wrap CSL v15's `TransactionBuilder` behind a stable, panic-free Rust
API that the Dart side can drive through flutter_rust_bridge. The
builder is sync — no `tokio` here. Network I/O lives in the Dart
Blockfrost provider.

## API Shape (target)

```rust
pub struct TxInput {
    pub tx_hash: String,       // hex
    pub output_index: u32,
    pub address: String,       // bech32
    pub value: Value,
}

pub struct TxOutput {
    pub address: String,       // bech32
    pub value: Value,
}

pub struct Value {
    pub coin: u64,
    pub assets: Vec<NativeAsset>, // empty for ADA-only
}

pub struct NativeAsset {
    pub policy_id: String,     // hex
    pub asset_name: String,    // hex
    pub quantity: u64,
}

pub struct ProtocolParams {
    pub min_fee_a: u64,
    pub min_fee_b: u64,
    pub coins_per_utxo_byte: u64,
    pub max_tx_size: u32,
    // ...whatever Blockfrost surfaces that the builder needs
}

pub struct BuiltTx {
    pub tx_body_cbor_hex: String,
    pub tx_hash: String,
    pub fee: u64,
}

#[frb(sync)]
pub fn build_tx(
    inputs: Vec<TxInput>,
    outputs: Vec<TxOutput>,
    change_address: String,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltTx, CardanoError>;

#[frb(sync)]
pub fn min_ada_for_output(output: TxOutput, coins_per_utxo_byte: u64)
    -> Result<u64, CardanoError>;

#[frb(sync)]
pub fn estimate_fee(
    tx_body_cbor_hex: String,
    witness_count: u32,
    params: ProtocolParams,
) -> Result<u64, CardanoError>;
```

The exact shape can shift slightly to match what Research Agent finds
in CSL, but the *spirit* — sync, FFI-friendly types, no CSL types
leaked across the boundary — must hold.

## Implementation Notes

- Add `pub mod tx;` to `rust/src/lib.rs`
- Extend `CardanoError` with `TxBuild { reason: String }` and
  `InvalidParameter { field: String, reason: String }` if not present
- Convert hex/bech32 inputs into CSL types at the boundary; never
  expose `csl::TransactionBuilder` or other CSL types outward
- Use `cardano_serialization_lib::tx_builder::TransactionBuilder`
  via `TransactionBuilderConfigBuilder`
- Do not panic. Map every `csl::Error` and every `String::from_utf8` /
  hex decode to a typed `CardanoError`
- Keep the public `build_tx` deterministic for fixed inputs (no
  timestamps, no RNG)

## Tests (in `rust/src/tx.rs`)

- `build_tx_ada_only_balances` — 1 input, 1 output, change goes to
  change_address, fee ≥ `min_fee_a * size + min_fee_b`
- `build_tx_rejects_insufficient_inputs` — sum(inputs) < sum(outputs)
  + min fee → `CardanoError::TxBuild`
- `min_ada_for_pure_ada_output` — matches CSL's helper output
- `min_ada_for_multi_asset_output` — output with one native asset has
  min-ada > pure-ADA case
- `build_tx_roundtrip_cbor` — built body deserializes back to the same
  inputs/outputs via CSL
- `build_tx_with_one_native_asset` — multi-asset output serializes
  and balances correctly

## Acceptance

- [ ] `cargo build` and `cargo test` pass
- [ ] `cargo clippy --all-targets -- -D warnings` passes
- [ ] `cargo fmt` applied
- [ ] No panics — confirmed by reading; tests for known failure modes
- [ ] All types crossing FFI are primitives, `String`, `Vec<u8>`, or
      `#[derive(Debug, Clone)]` plain structs
- [ ] flutter_rust_bridge codegen runs clean against the new module
