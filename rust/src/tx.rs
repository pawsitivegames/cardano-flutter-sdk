use crate::error::CardanoError;
use blake2::Blake2b;
use cardano_serialization_lib as csl;
use digest::{consts::U32, Digest};
use flutter_rust_bridge::frb;

/// Represents a single transaction input (UTxO).
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TxInput {
    pub tx_hash: String, // hex
    pub output_index: u32,
    pub address: String, // bech32
    pub value: Value,
}

/// Represents a single transaction output.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TxOutput {
    pub address: String, // bech32
    pub value: Value,
}

/// Represents a monetary value: ADA (lovelace) + optional native assets.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Value {
    pub coin: u64,
    pub assets: Vec<NativeAsset>, // empty for ADA-only
}

/// Represents a single native token quantity.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeAsset {
    pub policy_id: String,  // hex
    pub asset_name: String, // hex
    pub quantity: u64,
}

/// Protocol parameters required for transaction building.
#[derive(Clone, Copy, Debug)]
pub struct ProtocolParams {
    pub min_fee_a: u64,           // linear fee coefficient (per byte)
    pub min_fee_b: u64,           // linear fee constant
    pub coins_per_utxo_byte: u64, // min-ada per byte
    pub max_tx_size: u32,         // bytes
    pub pool_deposit: u64,        // lovelace
    pub key_deposit: u64,         // lovelace
    pub max_val_size: u32,        // bytes
}

/// Result of a successfully built transaction.
#[derive(Clone, Debug)]
pub struct BuiltTx {
    pub tx_body_cbor_hex: String,
    pub tx_hash: String,
    pub fee: u64,
}

/// Map CSL JsError to CardanoError.
pub(crate) fn map_csl_error(e: csl::JsError) -> CardanoError {
    CardanoError::CslError(format!("{:?}", e))
}

/// Map CSL DeserializeError to CardanoError.
pub(crate) fn map_deserialize_error(e: csl::DeserializeError) -> CardanoError {
    CardanoError::CslError(format!("{:?}", e))
}

/// Parse a hex string into bytes, or return an error.
pub(crate) fn hex_to_bytes(hex: &str) -> Result<Vec<u8>, CardanoError> {
    hex::decode(hex).map_err(|e| CardanoError::InvalidParameter {
        field: "hex_string".to_string(),
        reason: format!("Failed to decode hex: {}", e),
    })
}

/// Convert a TxInput into a CSL TransactionInput and its Value.
pub(crate) fn input_to_csl(
    input: &TxInput,
) -> Result<(csl::TransactionInput, csl::Value), CardanoError> {
    let tx_hash_bytes = hex_to_bytes(&input.tx_hash)?;
    let tx_hash = csl::TransactionHash::from_bytes(tx_hash_bytes).map_err(map_deserialize_error)?;
    let tx_input = csl::TransactionInput::new(&tx_hash, input.output_index);

    let value = value_to_csl(&input.value)?;
    Ok((tx_input, value))
}

/// Convert a Value into a CSL Value.
pub(crate) fn value_to_csl(value: &Value) -> Result<csl::Value, CardanoError> {
    if value.assets.is_empty() {
        // Pure ADA
        Ok(csl::Value::new(&csl::BigNum::from(value.coin)))
    } else {
        // Multi-asset
        let mut multi_asset = csl::MultiAsset::new();

        for asset in &value.assets {
            let policy_bytes = hex_to_bytes(&asset.policy_id)?;
            let policy_id =
                csl::ScriptHash::from_bytes(policy_bytes).map_err(map_deserialize_error)?;

            let asset_name_bytes = hex_to_bytes(&asset.asset_name)?;
            let asset_name = csl::AssetName::new(asset_name_bytes).map_err(map_csl_error)?;

            let amount = csl::BigNum::from(asset.quantity);

            // Merge into any existing Assets under this policy. `MultiAsset::insert`
            // REPLACES the whole policy entry, so building a fresh `Assets` per
            // asset would drop all but the last asset name sharing a policy id
            // (e.g. CIP-68 (100)/(222) pairs) — producing a value-unbalanced tx
            // rejected on-chain with `ValueNotConservedUTxO`.
            let mut assets = multi_asset.get(&policy_id).unwrap_or_default();
            assets.insert(&asset_name, &amount);
            multi_asset.insert(&policy_id, &assets);
        }

        Ok(csl::Value::new_with_assets(
            &csl::BigNum::from(value.coin),
            &multi_asset,
        ))
    }
}

/// Convert a TxOutput into a CSL TransactionOutput.
pub(crate) fn output_to_csl(output: &TxOutput) -> Result<csl::TransactionOutput, CardanoError> {
    let address = csl::Address::from_bech32(&output.address)
        .map_err(|_| CardanoError::InvalidAddress("Invalid output address bech32".to_string()))?;

    let value = value_to_csl(&output.value)?;

    csl::TransactionOutputBuilder::new()
        .with_address(&address)
        .next()
        .map_err(map_csl_error)?
        .with_value(&value)
        .build()
        .map_err(map_csl_error)
}

/// Build a transaction with manual input/output selection.
///
/// # Arguments
/// - `inputs`: UTxOs to spend
/// - `outputs`: outputs to create
/// - `change_address`: where to send change (bech32)
/// - `ttl`: optional slot number after which the tx is invalid
/// - `params`: protocol parameters from the blockchain
///
/// # Errors
/// - `InvalidAddress`: if any address is malformed
/// - `InvalidParameter`: if inputs, outputs, or params are invalid
/// - `TxBuild`: if the builder encounters an error (e.g., insufficient funds, change < min_ada)
#[frb(sync)]
pub fn build_tx(
    inputs: Vec<TxInput>,
    outputs: Vec<TxOutput>,
    change_address: String,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltTx, CardanoError> {
    // Validate that we have inputs and outputs
    if inputs.is_empty() {
        return Err(CardanoError::InvalidParameter {
            field: "inputs".to_string(),
            reason: "At least one input is required".to_string(),
        });
    }

    if outputs.is_empty() {
        return Err(CardanoError::InvalidParameter {
            field: "outputs".to_string(),
            reason: "At least one output is required".to_string(),
        });
    }

    // Build TransactionBuilderConfig
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

    // Add inputs
    {
        let mut inputs_builder = csl::TxInputsBuilder::new();
        for input in &inputs {
            let (tx_input, value) = input_to_csl(input)?;
            let address = csl::Address::from_bech32(&input.address).map_err(|_| {
                CardanoError::InvalidAddress("Invalid input address bech32".to_string())
            })?;

            inputs_builder
                .add_regular_input(&address, &tx_input, &value)
                .map_err(map_csl_error)?;
        }
        tx_builder.set_inputs(&inputs_builder);
    }

    // Add outputs
    for output in &outputs {
        let csl_output = output_to_csl(output)?;
        tx_builder.add_output(&csl_output).map_err(map_csl_error)?;
    }

    // Set TTL if provided (SlotBigNum is just a type alias for BigNum)
    if let Some(slot) = ttl {
        tx_builder.set_ttl_bignum(&csl::BigNum::from(slot));
    }

    // Parse change address
    let change_addr = csl::Address::from_bech32(&change_address)
        .map_err(|_| CardanoError::InvalidAddress("Invalid change address bech32".to_string()))?;

    // Add change if needed (this computes the fee and creates change output)
    tx_builder.add_change_if_needed(&change_addr).map_err(|e| {
        // CSL errors on change < min_ada or other builder issues
        CardanoError::TxBuild {
            reason: format!("Failed to compute change: {:?}", e),
        }
    })?;

    // Build the final transaction
    let tx = tx_builder.build_tx().map_err(|e| CardanoError::TxBuild {
        reason: format!("Failed to build transaction: {:?}", e),
    })?;

    let body = tx.body();

    // Canonical Cardano transaction id: Blake2b-256 over the body CBOR (matches
    // CSL's internal `blake2b256` and `sign.rs`'s signing hash). NOTE: Blake2b-256
    // is NOT the first 32 bytes of Blake2b-512 — the digest length is mixed into
    // Blake2b's parameter block — so truncating Blake2b-512 (the old code) yielded
    // an id that never matched the one the node computes on submission.
    let mut hasher = Blake2b::<U32>::new();
    hasher.update(body.to_bytes());
    let tx_hash_hex = hex::encode(hasher.finalize());

    // Serialize the body
    let body_bytes = body.to_bytes();
    let body_cbor_hex = hex::encode(body_bytes);

    // Extract the fee - BigNum can be converted to u64 using string parsing
    let fee_bignum = body.fee();
    let fee_value: u64 = fee_bignum
        .to_str()
        .parse()
        .map_err(|_| CardanoError::TxBuild {
            reason: "Failed to convert fee BigNum to u64".to_string(),
        })?;

    Ok(BuiltTx {
        tx_body_cbor_hex: body_cbor_hex,
        tx_hash: tx_hash_hex,
        fee: fee_value,
    })
}

/// Compute the minimum ADA required for an output.
///
/// Uses the CSL helper to account for CBOR serialization size and the UTxO
/// entry cost (160 bytes overhead in Babbage).
///
/// # Arguments
/// - `output`: the output to check
/// - `coins_per_utxo_byte`: from protocol parameters
///
/// # Errors
/// - `InvalidAddress`: if the address is malformed
/// - `CslError`: if CSL's min_ada calculator fails
#[frb(sync)]
pub fn min_ada_for_output(output: TxOutput, coins_per_utxo_byte: u64) -> Result<u64, CardanoError> {
    let csl_output = output_to_csl(&output)?;
    let data_cost = csl::DataCost::new_coins_per_byte(&csl::Coin::from(coins_per_utxo_byte));

    let needed = csl::min_ada_for_output(&csl_output, &data_cost).map_err(map_csl_error)?;

    // Convert BigNum to u64 via string parsing
    needed.to_str().parse().map_err(|_| CardanoError::TxBuild {
        reason: "Failed to convert min_ada BigNum to u64".to_string(),
    })
}

/// Estimate the fee for a transaction body.
///
/// Fee = `min_fee_a * tx_size_bytes + min_fee_b + (witness_count * witness_overhead)`.
///
/// # Arguments
/// - `tx_body_cbor_hex`: hex-encoded transaction body CBOR
/// - `witness_count`: expected number of vkey witnesses
/// - `params`: protocol parameters
///
/// # Errors
/// - `InvalidParameter`: if the hex is invalid
/// - `TxBuild`: if fee computation fails
#[frb(sync)]
pub fn estimate_fee(
    tx_body_cbor_hex: String,
    witness_count: u32,
    params: ProtocolParams,
) -> Result<u64, CardanoError> {
    let body_bytes = hex_to_bytes(&tx_body_cbor_hex)?;

    // Estimate witness overhead: ~100 bytes per vkey witness (signature + public key)
    let witness_overhead = witness_count as u64 * 100;

    let total_size = (body_bytes.len() as u64) + witness_overhead;

    let fee = params
        .min_fee_a
        .saturating_mul(total_size)
        .saturating_add(params.min_fee_b);

    Ok(fee)
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use std::collections::BTreeMap;

    fn test_protocol_params() -> ProtocolParams {
        ProtocolParams {
            min_fee_a: 44,
            min_fee_b: 155381,
            coins_per_utxo_byte: 4310,
            max_tx_size: 16384,
            pool_deposit: 500000000,
            key_deposit: 2000000,
            max_val_size: 5000,
        }
    }

    #[test]
    fn test_estimate_fee() {
        let params = test_protocol_params();
        let tx_body_hex = "00".to_string();

        let result = estimate_fee(tx_body_hex, 1, params);
        assert!(result.is_ok(), "estimate_fee should work");
        let fee = result.unwrap();
        assert!(fee > params.min_fee_b, "fee must include min_fee_b");
    }

    #[test]
    fn test_estimate_fee_with_witness_overhead() {
        let params = test_protocol_params();
        let tx_body_hex = "00".to_string();

        let fee_1 = estimate_fee(tx_body_hex.clone(), 1, params).unwrap();
        let fee_2 = estimate_fee(tx_body_hex, 2, params).unwrap();

        // More witnesses should cost more
        assert!(fee_2 > fee_1, "more witnesses should increase fee");
    }

    #[test]
    fn test_hex_to_bytes_valid() {
        // Should decode without error
        let result = hex_to_bytes("deadbeef");
        assert!(result.is_ok());
    }

    #[test]
    fn test_hex_to_bytes_invalid() {
        // Should error on invalid hex
        let result = hex_to_bytes("ZZZZ");
        assert!(result.is_err());
    }

    #[test]
    fn test_value_to_csl_pure_ada() {
        let value = Value {
            coin: 1000000,
            assets: vec![],
        };

        let result = value_to_csl(&value);
        assert!(result.is_ok(), "pure ADA value conversion should work");
    }

    /// Regression: two asset names under the SAME policy in one value must both
    /// survive (CSL `MultiAsset::insert` replaces the policy entry, so a naive
    /// per-asset insert would drop all but the last → `ValueNotConservedUTxO`).
    #[test]
    fn test_value_to_csl_merges_same_policy_assets() {
        let policy = "29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418".to_string();
        let value = Value {
            coin: 2_000_000,
            assets: vec![
                NativeAsset {
                    policy_id: policy.clone(),
                    asset_name: hex::encode(b"AAA"),
                    quantity: 3,
                },
                NativeAsset {
                    policy_id: policy.clone(),
                    asset_name: hex::encode(b"BBB"),
                    quantity: 7,
                },
            ],
        };

        let csl_val = value_to_csl(&value).unwrap();
        let ma = csl_val.multiasset().expect("should have multiasset");
        let policy_hash = csl::ScriptHash::from_bytes(hex::decode(&policy).unwrap()).unwrap();
        let assets = ma.get(&policy_hash).expect("policy present");
        assert_eq!(
            assets.len(),
            2,
            "both asset names under the policy must survive"
        );
        let a = csl::AssetName::new(hex::decode(hex::encode(b"AAA")).unwrap()).unwrap();
        let b = csl::AssetName::new(hex::decode(hex::encode(b"BBB")).unwrap()).unwrap();
        assert_eq!(assets.get(&a).unwrap().to_str(), "3");
        assert_eq!(assets.get(&b).unwrap().to_str(), "7");
    }

    proptest! {
        #[test]
        fn value_to_csl_multiasset_cbor_is_canonical(
            assets in prop::collection::vec(
                (
                    any::<[u8; 28]>(),
                    prop::collection::vec(any::<u8>(), 0..=32),
                    1u64..=u64::MAX,
                ),
                1..24,
            )
        ) {
            let native_assets: Vec<NativeAsset> = assets
                .iter()
                .map(|(policy, asset_name, quantity)| NativeAsset {
                    policy_id: hex::encode(policy),
                    asset_name: hex::encode(asset_name),
                    quantity: *quantity,
                })
                .collect();
            let mut expected = BTreeMap::new();
            for asset in &native_assets {
                expected.insert((asset.policy_id.clone(), asset.asset_name.clone()), asset.quantity);
            }

            let csl_val = value_to_csl(&Value {
                coin: 2_000_000,
                assets: native_assets,
            })
            .expect("generated value should be valid");
            let encoded = csl_val.to_bytes();
            let decoded = csl::Value::from_bytes(encoded.clone()).expect("Value CBOR must decode");
            prop_assert_eq!(decoded.to_bytes(), encoded, "Value CBOR must be canonical");

            let multi_asset = decoded.multiasset().expect("multiasset should be present");
            for ((policy_hex, asset_name_hex), quantity) in expected {
                let policy = csl::ScriptHash::from_bytes(hex::decode(policy_hex).unwrap()).unwrap();
                let asset_name = csl::AssetName::new(hex::decode(asset_name_hex).unwrap()).unwrap();
                let policy_assets = multi_asset.get(&policy).expect("policy survives");
                let actual = policy_assets.get(&asset_name).expect("asset survives");
                prop_assert_eq!(actual.to_str(), quantity.to_string());
            }
        }
    }

    #[test]
    fn value_to_csl_rejects_asset_name_over_32_bytes() {
        let value = Value {
            coin: 2_000_000,
            assets: vec![NativeAsset {
                policy_id: "29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418".to_string(),
                asset_name: hex::encode([0xab; 33]),
                quantity: 1,
            }],
        };

        assert!(
            value_to_csl(&value).is_err(),
            "CSL must reject native asset names longer than 32 bytes"
        );
    }

    #[test]
    fn test_invalid_parameter_error_on_empty_inputs() {
        let params = test_protocol_params();
        let result = build_tx(
            vec![], // empty inputs
            vec![TxOutput {
                address: "addr_test1qpegxkqsqsg5s44czuppgjkn4eamvf2dlxw7g2nw7pxjf76w2uld"
                    .to_string(),
                value: Value {
                    coin: 1000000,
                    assets: vec![],
                },
            }],
            "addr_test1qpegxkqsqsg5s44czuppgjkn4eamvf2dlxw7g2nw7pxjf76w2uld".to_string(),
            None,
            params,
        );

        assert!(result.is_err());
        match result {
            Err(CardanoError::InvalidParameter { field, .. }) if field == "inputs" => {}
            _ => panic!("Expected InvalidParameter for inputs"),
        }
    }

    #[test]
    fn test_invalid_parameter_error_on_empty_outputs() {
        let params = test_protocol_params();
        let result = build_tx(
            vec![TxInput {
                tx_hash: "0000000000000000000000000000000000000000000000000000000000000000"
                    .to_string(),
                output_index: 0,
                address: "addr_test1qpegxkqsqsg5s44czuppgjkn4eamvf2dlxw7g2nw7pxjf76w2uld"
                    .to_string(),
                value: Value {
                    coin: 5000000,
                    assets: vec![],
                },
            }],
            vec![], // empty outputs
            "addr_test1qpegxkqsqsg5s44czuppgjkn4eamvf2dlxw7g2nw7pxjf76w2uld".to_string(),
            None,
            params,
        );

        assert!(result.is_err());
        match result {
            Err(CardanoError::InvalidParameter { field, .. }) if field == "outputs" => {}
            _ => panic!("Expected InvalidParameter for outputs"),
        }
    }

    /// Regression: the returned `tx_hash` must be the canonical Blake2b-256 of
    /// the body CBOR — NOT the first 32 bytes of Blake2b-512 (which is a
    /// different value, since Blake2b mixes the digest length into its state).
    #[test]
    fn test_tx_hash_is_blake2b256_not_truncated_blake2b512() {
        use blake2::Blake2b512;

        let params = test_protocol_params();
        let addr = "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz";
        let built = build_tx(
            vec![TxInput {
                tx_hash: "00".repeat(32),
                output_index: 0,
                address: addr.to_string(),
                value: Value {
                    coin: 5_000_000,
                    assets: vec![],
                },
            }],
            vec![TxOutput {
                address: addr.to_string(),
                value: Value {
                    coin: 1_000_000,
                    assets: vec![],
                },
            }],
            addr.to_string(),
            None,
            params,
        )
        .expect("build_tx should succeed");

        // 32-byte hash → 64 hex chars.
        assert_eq!(built.tx_hash.len(), 64);

        let body_bytes = hex::decode(&built.tx_body_cbor_hex).unwrap();

        // Correct canonical id: Blake2b-256 of the body.
        let mut h256 = Blake2b::<U32>::new();
        h256.update(&body_bytes);
        let expected = hex::encode(h256.finalize());
        assert_eq!(
            built.tx_hash, expected,
            "tx_hash must be Blake2b-256 of the body CBOR"
        );

        // The old buggy value (truncated Blake2b-512) must differ.
        let mut h512 = Blake2b512::new();
        h512.update(&body_bytes);
        let truncated = hex::encode(&h512.finalize()[..32]);
        assert_ne!(
            built.tx_hash, truncated,
            "tx_hash must not be the first 32 bytes of Blake2b-512"
        );
    }
}
