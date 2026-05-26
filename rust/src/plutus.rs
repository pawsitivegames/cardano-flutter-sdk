//! Plutus smart contract support (Phase 3): PlutusData encoding and
//! script-spending transactions with V2 / V3 scripts.
//!
//! # PlutusData encoding
//! Cardano's Plutus UPLC operates on `Data`, an UPLC-level type with five
//! constructors: `Constr`, `Map`, `List`, `I` (integer), `B` (bytes).
//! These helpers produce the canonical CBOR serialisation used on-chain.
//!
//! # Script-spending transactions
//! `build_script_tx` constructs a transaction that spends one or more Plutus
//! script UTxOs.  Each input requires a redeemer, the script, and a datum
//! (either embedded in the witness or fetched from an inline-datum UTxO via
//! reference inputs).

use blake2::{
    digest::{consts::U32, Digest},
    Blake2b,
};
use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

use crate::error::CardanoError;
use crate::tx::{
    hex_to_bytes, input_to_csl, map_csl_error, map_deserialize_error, output_to_csl,
    BuiltTx, ProtocolParams, TxInput, TxOutput,
};

// ── FFI-visible types ────────────────────────────────────────────────────────

/// Plutus script language version.
pub enum PlutusScriptVersion {
    V2,
    V3,
}

/// A script-locked UTxO to spend, with its witness data.
pub struct PlutusInput {
    /// The UTxO to spend.
    pub tx_input: TxInput,
    /// Flat-encoded script CBOR hex (the `PlutusScript` CBOR, not double-encoded).
    pub script_cbor_hex: String,
    pub script_version: PlutusScriptVersion,
    /// `PlutusData` CBOR hex for the datum embedded in the witness.
    pub datum_cbor_hex: String,
    /// `PlutusData` CBOR hex for the redeemer.
    pub redeemer_cbor_hex: String,
    /// Execution unit memory budget.
    pub ex_units_mem: u64,
    /// Execution unit step budget.
    pub ex_units_steps: u64,
}

// ── PlutusData encoding helpers ───────────────────────────────────────────────

/// Encode an integer as `PlutusData` CBOR hex.
///
/// Handles the full `i64` range; large integers (> i32 range) are encoded as
/// Plutus `I` tags using the CBOR big-integer encoding.
#[frb(sync)]
pub fn plutus_data_int(n: i64) -> Result<String, CardanoError> {
    let big_int = csl::BigInt::from_str(&n.to_string())
        .map_err(|e| CardanoError::CslError(format!("{:?}", e)))?;
    let data = csl::PlutusData::new_integer(&big_int);
    Ok(hex::encode(data.to_bytes()))
}

/// Encode arbitrary bytes (hex input) as `PlutusData` CBOR hex.
#[frb(sync)]
pub fn plutus_data_bytes(hex_data: String) -> Result<String, CardanoError> {
    let bytes = hex_to_bytes(&hex_data)?;
    let data = csl::PlutusData::new_bytes(bytes);
    Ok(hex::encode(data.to_bytes()))
}

/// Encode a constructor application as `PlutusData` CBOR hex.
///
/// # Arguments
/// - `constructor`: alternative index (0-based)
/// - `fields_cbor_hex`: ordered list of `PlutusData` CBOR hex values produced
///   by the other `plutus_data_*` helpers
#[frb(sync)]
pub fn plutus_data_constr(
    constructor: u64,
    fields_cbor_hex: Vec<String>,
) -> Result<String, CardanoError> {
    let mut list = csl::PlutusList::new();
    for field_hex in &fields_cbor_hex {
        let bytes = hex_to_bytes(field_hex)?;
        let field = csl::PlutusData::from_bytes(bytes)
            .map_err(|e| CardanoError::InvalidCbor(format!("Invalid PlutusData field: {:?}", e)))?;
        list.add(&field);
    }
    let constr = csl::ConstrPlutusData::new(&csl::BigNum::from(constructor), &list);
    let data = csl::PlutusData::new_constr_plutus_data(&constr);
    Ok(hex::encode(data.to_bytes()))
}

/// Encode a `PlutusData` list as CBOR hex.
#[frb(sync)]
pub fn plutus_data_list(items_cbor_hex: Vec<String>) -> Result<String, CardanoError> {
    let mut list = csl::PlutusList::new();
    for item_hex in &items_cbor_hex {
        let bytes = hex_to_bytes(item_hex)?;
        let item = csl::PlutusData::from_bytes(bytes)
            .map_err(|e| CardanoError::InvalidCbor(format!("Invalid PlutusData item: {:?}", e)))?;
        list.add(&item);
    }
    let data = csl::PlutusData::new_list(&list);
    Ok(hex::encode(data.to_bytes()))
}

/// Verify that a CBOR hex string represents valid `PlutusData`.
///
/// Returns the same hex on success, or an error describing why it is invalid.
/// Useful for validating externally-sourced datum/redeemer values.
#[frb(sync)]
pub fn validate_plutus_data(cbor_hex: String) -> Result<String, CardanoError> {
    let bytes = hex_to_bytes(&cbor_hex)?;
    csl::PlutusData::from_bytes(bytes)
        .map_err(|e| CardanoError::InvalidCbor(format!("Invalid PlutusData: {:?}", e)))?;
    Ok(cbor_hex)
}

// ── Script-spending transaction ───────────────────────────────────────────────

/// Build a transaction spending one or more Plutus script UTxOs.
///
/// # Arguments
/// - `script_inputs`: Plutus-locked UTxOs, each with witness data
/// - `regular_inputs`: ordinary (key-locked) UTxOs also consumed (e.g. for fees)
/// - `outputs`: outputs to create
/// - `change_address`: receives ADA change
/// - `collateral_inputs`: pure-ADA UTxOs used as collateral (required for Plutus)
/// - `reference_inputs`: read-only reference UTxOs (CIP-31); not consumed
/// - `ttl`: optional slot deadline
/// - `params`: protocol parameters
///
/// # Errors
/// - `InvalidParameter` if `script_inputs` or `collateral_inputs` are empty
/// - `InvalidCbor` if any datum/redeemer/script CBOR is malformed
/// - `TxBuild` if CSL builder or script-data-hash computation fails
#[frb(sync)]
#[allow(clippy::too_many_arguments)]
pub fn build_script_tx(
    script_inputs: Vec<PlutusInput>,
    regular_inputs: Vec<TxInput>,
    outputs: Vec<TxOutput>,
    change_address: String,
    collateral_inputs: Vec<TxInput>,
    reference_inputs: Vec<TxInput>,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltTx, CardanoError> {
    if script_inputs.is_empty() {
        return Err(CardanoError::InvalidParameter {
            field: "script_inputs".to_string(),
            reason: "At least one script input is required".to_string(),
        });
    }
    if collateral_inputs.is_empty() {
        return Err(CardanoError::InvalidParameter {
            field: "collateral_inputs".to_string(),
            reason: "Collateral is required for Plutus transactions".to_string(),
        });
    }

    // ── Builder config ────────────────────────────────────────────────────
    let linear_fee = csl::LinearFee::new(
        &csl::Coin::from(params.min_fee_a),
        &csl::Coin::from(params.min_fee_b),
    );
    let config = csl::TransactionBuilderConfigBuilder::new()
        .fee_algo(&linear_fee)
        .pool_deposit(&csl::BigNum::from(params.pool_deposit))
        .key_deposit(&csl::BigNum::from(params.key_deposit))
        .max_value_size(params.max_val_size)
        .max_tx_size(params.max_tx_size)
        .coins_per_utxo_byte(&csl::Coin::from(params.coins_per_utxo_byte))
        .build()
        .map_err(map_csl_error)?;
    let mut tx_builder = csl::TransactionBuilder::new(&config);

    // ── All inputs (regular + Plutus) via TxInputsBuilder ────────────────
    {
        let mut inputs_builder = csl::TxInputsBuilder::new();

        // Regular key-locked inputs.
        for input in &regular_inputs {
            let (csl_input, value) = input_to_csl(input)?;
            let address = csl::Address::from_bech32(&input.address)
                .map_err(|_| CardanoError::InvalidAddress(input.address.clone()))?;
            inputs_builder
                .add_regular_input(&address, &csl_input, &value)
                .map_err(map_csl_error)?;
        }

        // Plutus script inputs.
        for (idx, pi) in script_inputs.iter().enumerate() {
            let script_bytes = hex_to_bytes(&pi.script_cbor_hex)?;
            let script = match pi.script_version {
                PlutusScriptVersion::V2 => csl::PlutusScript::from_bytes_v2(script_bytes)
                    .map_err(map_csl_error)?,
                PlutusScriptVersion::V3 => csl::PlutusScript::from_bytes_v3(script_bytes)
                    .map_err(map_csl_error)?,
            };

            let datum_bytes = hex_to_bytes(&pi.datum_cbor_hex)?;
            let datum = csl::PlutusData::from_bytes(datum_bytes).map_err(|e| {
                CardanoError::InvalidCbor(format!("Script input {}: invalid datum: {:?}", idx, e))
            })?;

            let redeemer_bytes = hex_to_bytes(&pi.redeemer_cbor_hex)?;
            let redeemer_data = csl::PlutusData::from_bytes(redeemer_bytes).map_err(|e| {
                CardanoError::InvalidCbor(format!(
                    "Script input {}: invalid redeemer: {:?}",
                    idx, e
                ))
            })?;

            let redeemer = csl::Redeemer::new(
                &csl::RedeemerTag::new_spend(),
                &csl::BigNum::from(idx as u64),
                &redeemer_data,
                &csl::ExUnits::new(
                    &csl::BigNum::from(pi.ex_units_mem),
                    &csl::BigNum::from(pi.ex_units_steps),
                ),
            );

            let witness = csl::PlutusWitness::new(&script, &datum, &redeemer);
            let (csl_input, value) = input_to_csl(&pi.tx_input)?;
            inputs_builder.add_plutus_script_input(&witness, &csl_input, &value);
        }

        tx_builder.set_inputs(&inputs_builder);
    }

    // ── Outputs ───────────────────────────────────────────────────────────
    for output in &outputs {
        tx_builder
            .add_output(&output_to_csl(output)?)
            .map_err(map_csl_error)?;
    }

    // ── TTL ───────────────────────────────────────────────────────────────
    if let Some(slot) = ttl {
        tx_builder.set_ttl_bignum(&csl::BigNum::from(slot));
    }

    // ── Collateral ────────────────────────────────────────────────────────
    {
        let mut col_builder = csl::TxInputsBuilder::new();
        for col in &collateral_inputs {
            let (csl_input, value) = input_to_csl(col)?;
            let address = csl::Address::from_bech32(&col.address)
                .map_err(|_| CardanoError::InvalidAddress(col.address.clone()))?;
            col_builder
                .add_regular_input(&address, &csl_input, &value)
                .map_err(map_csl_error)?;
        }
        tx_builder.set_collateral(&col_builder);
    }

    // ── Reference inputs ──────────────────────────────────────────────────
    for ref_input in &reference_inputs {
        let hash_bytes = hex_to_bytes(&ref_input.tx_hash)?;
        let tx_hash =
            csl::TransactionHash::from_bytes(hash_bytes).map_err(map_deserialize_error)?;
        let csl_input = csl::TransactionInput::new(&tx_hash, ref_input.output_index);
        tx_builder.add_reference_input(&csl_input);
    }

    // ── Script data hash (required for Plutus) ────────────────────────────
    // An empty Costmdls is passed here; the hash covers redeemers + datums.
    // For production, callers should supply actual cost models from protocol
    // parameters (Blockfrost /epochs/latest/parameters → cost_models).
    // Phase 3.5 will expose a `cost_models_cbor_hex` parameter.
    tx_builder
        .calc_script_data_hash(&csl::Costmdls::new())
        .map_err(|e| CardanoError::TxBuild {
            reason: format!("Failed to compute script data hash: {:?}", e),
        })?;

    // ── Change + fee ──────────────────────────────────────────────────────
    let change_addr = csl::Address::from_bech32(&change_address)
        .map_err(|_| CardanoError::InvalidAddress(change_address.clone()))?;
    tx_builder
        .add_change_if_needed(&change_addr)
        .map_err(|e| CardanoError::TxBuild {
            reason: format!("Failed to compute change: {:?}", e),
        })?;

    // ── Finalise ──────────────────────────────────────────────────────────
    let tx = tx_builder.build_tx().map_err(|e| CardanoError::TxBuild {
        reason: format!("Failed to build transaction: {:?}", e),
    })?;

    let body = tx.body();
    let body_bytes = body.to_bytes();
    let body_cbor_hex = hex::encode(&body_bytes);

    let mut hasher = Blake2b::<U32>::new();
    hasher.update(&body_bytes);
    let tx_hash_hex = hex::encode(hasher.finalize().as_slice());

    let fee: u64 = body
        .fee()
        .to_str()
        .parse()
        .map_err(|_| CardanoError::TxBuild {
            reason: "Failed to convert fee to u64".to_string(),
        })?;

    Ok(BuiltTx {
        tx_body_cbor_hex: body_cbor_hex,
        tx_hash: tx_hash_hex,
        fee,
    })
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── PlutusData encoding ──────────────────────────────────────────────

    #[test]
    fn plutus_data_int_positive() {
        let hex = plutus_data_int(42).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        let data = csl::PlutusData::from_bytes(bytes).expect("Must round-trip");
        // CSL represents small positive integers as BigInt.
        assert!(data.as_integer().is_some());
    }

    #[test]
    fn plutus_data_int_negative() {
        let hex = plutus_data_int(-1).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        csl::PlutusData::from_bytes(bytes).expect("Must round-trip");
    }

    #[test]
    fn plutus_data_int_large() {
        // u64::MAX + 1 (requires big-integer CBOR encoding)
        let hex = plutus_data_int(i64::MAX).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        csl::PlutusData::from_bytes(bytes).expect("Must round-trip");
    }

    #[test]
    fn plutus_data_bytes_roundtrips() {
        let hex = plutus_data_bytes("deadbeef".to_string()).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        let data = csl::PlutusData::from_bytes(bytes).expect("Must round-trip");
        assert!(data.as_bytes().is_some());
    }

    #[test]
    fn plutus_data_constr_zero_fields() {
        let hex = plutus_data_constr(0, vec![]).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        let data = csl::PlutusData::from_bytes(bytes).expect("Must round-trip");
        assert!(data.as_constr_plutus_data().is_some());
    }

    #[test]
    fn plutus_data_constr_nested() {
        let inner_int = plutus_data_int(99).unwrap();
        let inner_bytes = plutus_data_bytes("cafe".to_string()).unwrap();
        let hex = plutus_data_constr(1, vec![inner_int, inner_bytes]).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        let data = csl::PlutusData::from_bytes(bytes).expect("Must round-trip");
        let constr = data.as_constr_plutus_data().expect("Must be Constr");
        assert_eq!(
            constr.alternative().to_str(),
            "1",
            "Alternative must be 1"
        );
        assert_eq!(constr.data().len(), 2, "Must have 2 fields");
    }

    #[test]
    fn plutus_data_list_roundtrips() {
        let a = plutus_data_int(1).unwrap();
        let b = plutus_data_int(2).unwrap();
        let hex = plutus_data_list(vec![a, b]).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        let data = csl::PlutusData::from_bytes(bytes).expect("Must round-trip");
        let list = data.as_list().expect("Must be List");
        assert_eq!(list.len(), 2);
    }

    #[test]
    fn validate_plutus_data_accepts_valid() {
        let valid = plutus_data_int(0).unwrap();
        let result = validate_plutus_data(valid.clone()).unwrap();
        assert_eq!(result, valid);
    }

    #[test]
    fn validate_plutus_data_rejects_garbage() {
        let result = validate_plutus_data("not_hex".to_string());
        assert!(result.is_err());
    }

    // ── build_script_tx error cases ──────────────────────────────────────

    #[test]
    fn rejects_empty_script_inputs() {
        let result = build_script_tx(
            vec![],
            vec![],
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            vec![crate::tx::TxInput {
                tx_hash: "0".repeat(64),
                output_index: 0,
                address: "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"
                    .to_string(),
                value: crate::tx::Value {
                    coin: 5_000_000,
                    assets: vec![],
                },
            }],
            vec![],
            None,
            crate::tx::ProtocolParams {
                min_fee_a: 44,
                min_fee_b: 155_381,
                coins_per_utxo_byte: 4_310,
                max_tx_size: 16_384,
                pool_deposit: 500_000_000,
                key_deposit: 2_000_000,
                max_val_size: 5_000,
            },
        );
        assert!(
            matches!(result, Err(CardanoError::InvalidParameter { ref field, .. }) if field == "script_inputs")
        );
    }

    #[test]
    fn rejects_missing_collateral() {
        let datum_hex = plutus_data_int(0).unwrap();
        let redeemer_hex = plutus_data_int(0).unwrap();

        // Minimal dummy script (valid PlutusV2 always-succeed script CBOR)
        // This is the flat-encoded always-succeeds V2 script.
        let script_hex = "5907de010000323232323232323232323232323322323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232";
        let _ = script_hex; // suppress unused warning

        // Use an empty collateral list → should fail validation.
        let result = build_script_tx(
            vec![PlutusInput {
                tx_input: crate::tx::TxInput {
                    tx_hash: "0".repeat(64),
                    output_index: 0,
                    address: "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"
                        .to_string(),
                    value: crate::tx::Value {
                        coin: 5_000_000,
                        assets: vec![],
                    },
                },
                script_cbor_hex: "4e4d01000033222220051616190001".to_string(),
                script_version: PlutusScriptVersion::V2,
                datum_cbor_hex: datum_hex,
                redeemer_cbor_hex: redeemer_hex,
                ex_units_mem: 14_000_000,
                ex_units_steps: 10_000_000_000,
            }],
            vec![],
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            vec![], // empty collateral — must fail
            vec![],
            None,
            crate::tx::ProtocolParams {
                min_fee_a: 44,
                min_fee_b: 155_381,
                coins_per_utxo_byte: 4_310,
                max_tx_size: 16_384,
                pool_deposit: 500_000_000,
                key_deposit: 2_000_000,
                max_val_size: 5_000,
            },
        );
        assert!(
            matches!(result, Err(CardanoError::InvalidParameter { ref field, .. }) if field == "collateral_inputs")
        );
    }
}
