# Task: Phase 2 Signing Agent — vkey Witnesses

**Assigned to:** Signing Agent
**Deliverable:** `rust/src/sign.rs` + tests
**Blocked by:** Rust TX Builder Agent
**Unblocks:** Test & Verification Agent

## Objective

Sign a built transaction body with a derived payment key and produce
a complete `TransactionWitnessSet` containing vkey witnesses. Plutus
scripts and native scripts are out of scope for Phase 2.

## API

```rust
pub struct SignedTx {
    pub tx_cbor_hex: String,   // full transaction (body + witness set + auxiliary_data)
    pub tx_hash: String,
}

#[frb(sync)]
pub fn sign_tx(
    tx_body_cbor_hex: String,
    payment_keys_hex: Vec<String>, // one or more bech32 / hex-encoded ed25519 extended keys
) -> Result<SignedTx, CardanoError>;
```

## Requirements

- One vkey witness per provided payment key
- Witness set ordering follows CSL's canonical output — do not sort
  by hand; let CSL serialize
- Resulting `tx_hash` must match what the TX Builder reported for the
  same body
- No panics. Bad keys → `CardanoError::InvalidKey { reason }`. Bad
  body → `CardanoError::InvalidCbor { reason }`.
- Never log key material or its hash. Treat the `payment_keys_hex`
  slice as sensitive — drop it as early as possible inside the function.

## Open question to flag, not solve

Long term the key material should not cross FFI as a `String`. Options:
- `Vec<u8>` byte buffer (still copies)
- Platform keystore handle (iOS Keychain / Android Keystore) accessed
  from Dart, with Rust only seeing a signed-by-handle result

For v0.2.0 we accept the `String` boundary and document the gap in
`docs/PHASE_2_VERIFICATION.md`. Flag this to the Coordinator if any
design decision blocks implementation.

## Tests

- `sign_tx_round_trip` — Phase 1 mnemonic → derive payment key →
  build minimal tx → sign → verify witness against the body via CSL
- `sign_tx_two_witnesses` — sign with two keys, both witnesses present
- `sign_tx_rejects_garbage_key` — invalid key → `InvalidKey`
- `sign_tx_rejects_malformed_body` — invalid CBOR → `InvalidCbor`
- `tx_hash_stable` — same body, same hash across sign/no-sign

## Acceptance

- [ ] Module added to `rust/src/lib.rs`
- [ ] Tests pass on `cargo test`
- [ ] No panics; no key material in logs
- [ ] `cargo clippy --all-targets -- -D warnings` passes
- [ ] Boundary tradeoff documented inline + flagged in verification doc
