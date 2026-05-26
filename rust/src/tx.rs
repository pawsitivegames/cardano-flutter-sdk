use crate::error::CardanoError;
use blake2::Blake2b512;
use cardano_serialization_lib as csl;
use digest::Digest;
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
pub(crate) fn input_to_csl(input: &TxInput) -> Result<(csl::TransactionInput, csl::Value), CardanoError> {
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

            multi_asset.insert(&policy_id, &{
                let mut assets = csl::Assets::new();
                assets.insert(&asset_name, &amount);
                assets
            });
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

    // Compute the transaction hash using Blake2b-256
    let mut hasher = Blake2b512::new();
    hasher.update(body.to_bytes());
    let hash_result = hasher.finalize();
    // Blake2b-512 produces 64 bytes, we take first 32 for Blake2b-256
    let tx_hash_bytes: Vec<u8> = hash_result[..32].to_vec();
    let tx_hash_hex = hex::encode(&tx_hash_bytes);

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
}
