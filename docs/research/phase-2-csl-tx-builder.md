# Phase 2 Reference: CSL v15 TX Builder, CIP-2, and Blockfrost

> Source of truth for the Phase 2 implementation agents (Rust TX Builder,
> Coin Selection, Signing, Blockfrost Provider). Cite this doc rather than
> re-deriving APIs.
>
> Target stack: `cardano-serialization-lib = "15.0"` (current: 15.0.3),
> Blockfrost public API, Cardano **preview** testnet only.

## 1. CSL `TransactionBuilder` v15 walkthrough

### 1.1 Builder config

The config is constructed via `TransactionBuilderConfigBuilder` (fluent),
then frozen via `.build()`. All fee/deposit/size limits come from the
network's protocol parameters and must be pulled from Blockfrost
(`/epochs/latest/parameters`) per session — see §4.

Source: `rust/src/builders/tx_builder.rs` lines ~234-330
([github](https://github.com/Emurgo/cardano-serialization-lib/blob/master/rust/src/builders/tx_builder.rs)).

```rust
use cardano_serialization_lib as csl;
use csl::{
    BigNum, Coin, LinearFee, TransactionBuilder, TransactionBuilderConfig,
    TransactionBuilderConfigBuilder,
};

fn build_config(pp: &ProtocolParams) -> Result<TransactionBuilderConfig, csl::JsError> {
    let linear_fee = LinearFee::new(
        &Coin::from(pp.min_fee_a),          // coefficient (per-byte)
        &Coin::from(pp.min_fee_b),          // constant
    );
    TransactionBuilderConfigBuilder::new()
        .fee_algo(&linear_fee)
        .pool_deposit(&BigNum::from(pp.pool_deposit))     // u64 from string
        .key_deposit(&BigNum::from(pp.key_deposit))
        .max_value_size(pp.max_val_size as u32)           // typically 5000
        .max_tx_size(pp.max_tx_size as u32)               // typically 16384
        .coins_per_utxo_byte(&Coin::from(pp.coins_per_utxo_size))
        .build()
}
```

Notes:
- `LinearFee::new(coefficient, constant)` — **coefficient first**.
  Source: `rust/src/fees.rs`. Both args are `&Coin`.
- v15 uses `coins_per_utxo_byte` (Babbage+). The legacy `coins_per_utxo_word`
  builder method still exists for older eras but **must not be used** for
  preview/preprod/mainnet today.
- `ex_unit_prices` and `ref_script_coins_per_byte` are only required when
  building Plutus transactions — skip for Phase 2 (vkey-only).
- The builder methods return `Self` by value, **not `&mut self`** — chain
  them, don't try to mutate in place.

### 1.2 Adding inputs

Two paths, choose one per TX:

**A. Manual input set** (we pick UTxOs in our coin-selection code):

```rust
use csl::{Address, BigNum, TransactionHash, TransactionInput, TxInputsBuilder, Value};

let mut inputs = TxInputsBuilder::new();
inputs.add_regular_input(
    &from_addr,                                      // &Address
    &TransactionInput::new(&TransactionHash::from_bytes(tx_hash_bytes)?, output_index),
    &Value::new(&BigNum::from(lovelace_amount)),
)?;
tx_builder.set_inputs(&inputs);
```

`add_regular_input` returns an error for script/reward addresses. Use it
for ordinary payment addresses only (Phase 2 scope).

Source: `rust/src/builders/tx_inputs_builder.rs`.

**B. Let CSL pick from a UTxO set** (alternative, but we prefer A so coin
selection is testable in Dart-visible code):

```rust
use csl::{CoinSelectionStrategyCIP2, TransactionUnspentOutputs};

tx_builder.add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirst)?;
```

CSL's `CoinSelectionStrategyCIP2` variants: `LargestFirst`, `RandomImprove`,
`LargestFirstMultiAsset`, `RandomImproveMultiAsset`. The non-MultiAsset
variants ignore native tokens in inputs — only use them if you're certain
selected UTxOs are pure ADA.

### 1.3 Adding outputs

```rust
use csl::{TransactionOutput, TransactionOutputBuilder, Value};

let output = TransactionOutputBuilder::new()
    .with_address(&to_addr)
    .next()?
    .with_value(&Value::new(&BigNum::from(send_lovelace)))
    .build()?;
tx_builder.add_output(&output)?;
```

For multi-asset outputs, wrap a `MultiAsset` into `Value::new_with_assets`
(see §2). `add_output` validates `min_ada` and **errors** if the output
under-funds — surface that as a `CardanoError::SerializationError`.

### 1.4 TTL, validity, metadata

```rust
use csl::SlotBigNum;

tx_builder.set_ttl_bignum(&SlotBigNum::from(current_slot + 7200));   // ~2h
tx_builder.set_validity_start_interval_bignum(&SlotBigNum::from(current_slot));
// tx_builder.set_auxiliary_data(&aux) — only if attaching metadata (Phase 2 optional)
```

The plain `set_ttl(u32)` is deprecated; use `set_ttl_bignum` (slots fit
in u64 post-Babbage).

### 1.5 Fee, change, finalize

```rust
use csl::{Transaction, hash_transaction, make_vkey_witness,
          TransactionWitnessSet, Vkeywitnesses};

// Tells the builder to compute fee and emit a change output to this addr.
// Returns false if balance is exact and no change output is needed.
let _had_change: bool = tx_builder.add_change_if_needed(&change_addr)?;

// Final, signed transaction (no witnesses yet — but body is locked in).
let tx: Transaction = tx_builder.build_tx()?;
let body = tx.body();

// Witness step (vkey-only for Phase 2):
let tx_hash = hash_transaction(&body);
let mut vkeys = Vkeywitnesses::new();
vkeys.add(&make_vkey_witness(&tx_hash, &payment_private_key));

let mut wset = TransactionWitnessSet::new();
wset.set_vkeys(&vkeys);

let signed = Transaction::new(&body, &wset, tx.auxiliary_data());
let cbor_bytes: Vec<u8> = signed.to_bytes();   // → POST to /tx/submit
```

`build_tx()` returns a `Transaction` whose witness set is empty — we
replace it with our signed one via `Transaction::new`. `build()` (no
`_tx`) returns just the `TransactionBody` and is older API; prefer
`build_tx()`.

### 1.6 Gotchas

1. **Witness order** — CSL handles vkey sorting inside `Vkeywitnesses::add`;
   never build the witness set by raw CBOR.
2. **Deterministic CBOR** — never re-encode signed bytes through another
   CBOR lib; body hash will change and the node rejects.
3. **`add_output` enforces `min_ada`** — bubble its error verbatim.
4. **`add_change_if_needed` fails** if remaining balance < min_ada for
   change. Treat as "selection too tight, retry with more inputs."
5. **Don't call `min_fee` manually** — `add_change_if_needed` does it.
6. **`set_fee` overrides everything** — test-only.
7. **`build_tx` errors** on inputs < outputs + fee. Coin selection
   should catch this earlier.

## 2. Min-ada for multi-asset outputs

CSL v15 helper:

```rust
pub fn min_ada_for_output(
    output: &TransactionOutput,
    data_cost: &DataCost,
) -> Result<BigNum, JsError>
```

Source: `rust/src/utils.rs`. Internally wraps `MinOutputAdaCalculator`
which iterates because growing the coin field may push the CBOR over
another byte boundary.

```rust
use csl::{DataCost, Coin, min_ada_for_output};

let data_cost = DataCost::new_coins_per_byte(&Coin::from(pp.coins_per_utxo_size));
let needed = min_ada_for_output(&output, &data_cost)?;
```

**Coefficient on preview today (May 2026):** `coins_per_utxo_size = 4310`
lovelace per byte (Babbage formula; unchanged since Vasil HF). Always
read from `/epochs/latest/parameters` — do not hardcode.
(See [Cardano Docs - parameter guide](https://docs.cardano.org/about-cardano/explore-more/parameter-guide).)

### Worked example

Output: send 1 ADA + 100 units of `PolicyId(28 bytes) . AssetName("MYTKN")`
to a Shelley address (57 bytes bech32 → 57-byte CBOR addr).

- Serialized output CBOR length ≈ **~115 bytes** (address + coin + asset
  map with one policy & one name).
- Min ADA ≈ `coins_per_utxo_size * (output_size + 160)`
  ≈ `4310 * (115 + 160) ≈ 1,185,250 lovelace ≈ ~1.19 ADA`.
- Concretely: a single-token output typically needs **~1.2-1.4 ADA**.
  Pure-ADA outputs need ~0.97 ADA (the well-known ~1 ADA floor).

The constant `160` is the per-output overhead Babbage adds (utxo entry
size). Our code should never assume a value — always call
`min_ada_for_output` and surface the result.

## 3. CIP-2 Largest-First coin selection

Spec: <https://cips.cardano.org/cip/CIP-2>.

### 3.1 Algorithm (ADA-only path)

```text
fn largest_first(utxos: Vec<Utxo>, target: Coin, max_inputs: usize) -> Result<Selection> {
    let mut pool = utxos;
    pool.sort_by_key(|u| Reverse(u.lovelace));        // descending
    let mut selected = Vec::new();
    let mut acc: Coin = 0;
    for u in pool {
        if acc >= target + estimated_fee(selected.len() + 1) { break; }
        if selected.len() >= max_inputs { return Err(MaxInputsExceeded); }
        acc += u.lovelace;
        selected.push(u);
    }
    if acc < target + estimated_fee(selected.len()) { return Err(InsufficientFunds); }
    Ok(Selection { inputs: selected, change: acc - target - fee })
}
```

### 3.2 Multi-asset extension

CIP-2 does not formally specify multi-asset largest-first. Approach we'll
use, matching CSL's `LargestFirstMultiAsset`:

1. **Per asset, then ADA**. For each asset class in the target
   (including lovelace), run largest-first over UTxOs that contain it,
   accumulating until quantity is satisfied.
2. **Union the selections**. The final input set is the union; an input
   selected for asset A may already provide ADA for the lovelace pass.
3. **Recompute change as a `MultiAsset`** containing all leftover units.

### 3.3 Edge cases

| Case | Behavior |
|---|---|
| `target == 0` | Reject up-front (`InvalidArgument`). |
| `utxos.is_empty()` | `InsufficientFunds`. |
| Sum(utxos) < target + min_fee_floor | `InsufficientFunds` before loop. |
| Selection succeeds but change < min_ada | Add one more input from pool; if pool empty, fail. |
| Selection > `max_tx_size / per_input_size` | `MaxInputsExceeded` (use ~80 as a safe Phase 2 cap; real cap depends on size). |
| All UTxOs are dust (each < 1 ADA min_ada) and target is small | May still succeed; the change calculation handles it via `add_change_if_needed`. |
| Multi-asset target asks for asset that no UTxO contains | `InsufficientFunds` on that asset; report which one. |

### 3.4 Fee feedback loop

Fee depends on TX size, which depends on input count:

1. Estimate fee = `pp.min_fee_b + pp.min_fee_a * 250 * n_inputs`.
2. Select with that target.
3. Build TX; let `add_change_if_needed` compute the real fee.
4. If change falls below min_ada, retry with one more UTxO (max 3
   retries, then fail).

CIP-2 recommends Random-Improve over Largest-First for dust hygiene.
Phase 2 ships Largest-First only; Random-Improve is Phase 3+.

## 4. Blockfrost endpoints for Phase 2

Base URL (preview): `https://cardano-preview.blockfrost.io/api/v0`
Base URL (preprod): `https://cardano-preprod.blockfrost.io/api/v0`
Base URL (mainnet): `https://cardano-mainnet.blockfrost.io/api/v0`

Auth: every request **must** include header `project_id: <PROJECT_ID>`.
A project ID's prefix encodes the network (`preview…`, `preprod…`,
`mainnet…`). Source the project ID from a Dart-level env/config; never
hardcode. The Rust layer should accept it as a parameter — no global
state.

### 4.1 `GET /addresses/{address}/utxos`

Query params: `count` (1-100, default 100), `page` (1-N), `order`
(`asc`|`desc`).

Response: `200 OK` → JSON array. Each element:

```json
{
  "address": "addr_test1q...",
  "tx_hash":  "1f4f1...",
  "tx_index": 0,
  "output_index": 0,
  "amount": [
    { "unit": "lovelace", "quantity": "42000000" },
    { "unit": "<policy_id_hex><asset_name_hex>", "quantity": "12" }
  ],
  "block": "8788...",
  "data_hash": null,
  "inline_datum": null,
  "reference_script_hash": null
}
```

Pagination: page through with `page=1,2,…` until response array length
< `count`. Address with no UTxOs returns `404` (treat as empty, not
error). Source:
[blockfrost-openapi `AddressUtxoContentInner`](https://docs.rs/blockfrost-openapi/).

### 4.2 `GET /epochs/latest/parameters`

Response: `EpochParamContent` (56 fields). We map this subset into
`TransactionBuilderConfig`:

| Blockfrost field | Type | Use |
|---|---|---|
| `min_fee_a` | i32 | `LinearFee.coefficient` |
| `min_fee_b` | i32 | `LinearFee.constant` |
| `max_tx_size` | i32 | `max_tx_size` |
| `max_val_size` | String (u32) | `max_value_size` |
| `key_deposit` | String (u64) | `key_deposit` |
| `pool_deposit` | String (u64) | `pool_deposit` |
| `coins_per_utxo_size` | Option<String> | `coins_per_utxo_byte` + min_ada calc |
| `price_mem` / `price_step` | Option<f64> | `ex_unit_prices` (Phase 3) |
| `collateral_percent` | Option<i32> | Plutus only (Phase 3) |
| `min_fee_ref_script_cost_per_byte` | Option<f64> | Reference scripts (Phase 3) |

Note string types — Blockfrost serializes large integers as strings to
avoid JS precision loss. Parse via `u64::from_str` in Rust; surface
`SerializationError` if parsing fails.

Source: [docs.rs/blockfrost-openapi `EpochParamContent`](https://docs.rs/blockfrost-openapi/).

### 4.3 `POST /tx/submit`

- Method: `POST`
- Path: `/tx/submit`
- Header: `Content-Type: application/cbor` (raw CBOR bytes, **not** hex)
- Body: the bytes from `Transaction::to_bytes()`
- Success: `200 OK`, body = JSON string of tx hash (64 hex chars)

Error responses:

| Code | Meaning | Recovery |
|---|---|---|
| 400 | Invalid TX (bad witnesses, fee too low, UTxO consumed, etc.) | Surface ledger error to user; do not retry blindly |
| 403 | Bad `project_id` | Fix config |
| 425 | Mempool full | Backoff + retry (1-5s) |
| 429 | Rate limited | Respect headers; backoff |
| 500 | Blockfrost outage | Backoff + retry |

The 400 body contains a human-readable ledger reason — log verbatim.

### 4.4 Rate limits

- 10 req/sec sustained, burst of 500 (refills at 10/sec).
- Limits are per-IP, not per-project.
- Phase 2 traffic is well below this. The TX submit + UTxO fetch + PP
  fetch is ≤ 3 requests per send.

Source: [blockfrost.dev / docs.blockfrost.io](https://blockfrost.dev/start-building).

## 5. Recommendations

### 5.1 Fee buffer

**No additive buffer.** `add_change_if_needed` already computes the
exact min fee from the final body size and emits change as `total - out
- fee`. Adding a buffer just wastes user funds and creates change-output
classification headaches.

Instead, handle the one realistic failure mode: change-below-min-ada.
If it happens, retry coin selection with one more UTxO (§3.4). Loop max
3 times, then fail loudly.

### 5.2 Protocol parameter caching

- **Cache per session** with a 1-epoch TTL (preview epoch = 1 day).
- Refresh on any explicit "build TX" call older than 1 hour to catch
  mid-epoch hard forks (rare, but cheap insurance).
- Cache invalidation on tx-submit failure with code 400 mentioning
  fee/value mismatch — likely PP changed.
- Cache lives in the **Dart layer** (Provider), not Rust. Rust accepts
  a `ProtocolParams` struct per call and stays stateless. This matches
  the existing `#[frb(sync)]` no-state convention in `wallet.rs`.

### 5.3 CSL v15 API stability flags

- `coins_per_utxo_word` deprecated post-Babbage → `coins_per_utxo_byte`.
  Old CSL v11 examples mislead.
- `add_key_input` / `add_regular_input` deprecated in v15 → prefer
  `add_regular_utxo` (takes `TransactionUnspentOutput`).
- `set_ttl(u32)` deprecated → `set_ttl_bignum(&SlotBigNum)`.
- `build()` (body only) older; `build_tx()` (full tx) preferred.
- v15 adds Conway-era governance fields (voting_procedures,
  voting_proposals, treasury, donation). Phase 2 leaves them `None`.
- Don't leak `JsError` past the FFI boundary. Map it:

  ```rust
  fn map_csl<T>(r: Result<T, csl::JsError>) -> Result<T, CardanoError> {
      r.map_err(|e| CardanoError::CslError(format!("{:?}", e)))
  }
  ```

  Matches the existing `.to_string()` pattern in `wallet.rs`.

## 6. Open questions

1. **Exact `max_inputs` cap for Phase 2.** CSL doesn't enforce a hard
   limit; the practical cap is `max_tx_size` divided by per-input CBOR
   (~80 bytes). Recommend hardcoding 80 inputs for Phase 2 and
   surfacing as a config. *Coordinator: confirm whether we need this
   exposed to Dart or buried in coin_selection.rs.*

2. **Blockfrost project_id source.** Dart-side env var, asset file, or
   passed in per-call? Affects API surface of `BlockfrostProvider`.
   *Coordinator: pick one for the example app — recommend per-call
   parameter so we don't ship secrets in the package.*

3. **Multi-asset coin selection complexity.** CIP-2 doesn't specify it;
   `LargestFirstMultiAsset` in CSL is one interpretation. *Coordinator:
   decide whether Phase 2 ships our own Rust impl (testable, slower) or
   delegates to `tx_builder.add_inputs_from(..., LargestFirstMultiAsset)`
   (simpler, opaque). Recommend the latter for v0.2 and revisit if we
   see selection bugs in the wild.*

4. **Witness-set CBOR ordering on the Dart→Rust boundary.** If signing
   ever moves to Dart (hardware wallet flow), the signed witness set
   must be ordered identically to what `hash_transaction` saw. Out of
   scope for Phase 2 (we sign in Rust) but flag for Phase 3.

5. **Preview vs preprod default.** Project plan says preview; double-check
   nothing in Phase 1 hardcoded preprod. *Quick grep before merge.*

6. **`hash_transaction` and `make_vkey_witness` exact module path in
   CSL v15.** Confirmed exported at crate root (`csl::hash_transaction`,
   `csl::make_vkey_witness`) via [docs.rs index](https://docs.rs/cardano-serialization-lib/),
   but the source files weren't directly readable from the GitHub raw
   URLs we tried. *Verify with `cargo doc --open` once the dependency
   is added — should be a 30-second sanity check.*
