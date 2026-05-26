//! Native token minting / burning (Phase 3).
//!
//! Implements native-script-based minting policies and the transaction builder
//! for mint/burn operations. Reference: CIP-0035, CIP-0057.
//!
//! # Design
//! Native scripts are serialised as CBOR hex and passed opaquely across the FFI
//! boundary — this keeps the Dart API small and avoids representing a recursive
//! type over FFI.  Two policy constructors (`make_pubkey_script` and
//! `make_timelock_expiry_script`) cover the vast majority of NFT use cases.

use blake2::{
    digest::{consts::U32, Digest},
    Blake2b,
};
use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

use crate::error::CardanoError;
use crate::tx::{
    hex_to_bytes, input_to_csl, map_csl_error, map_deserialize_error, output_to_csl,
    ProtocolParams, TxInput, TxOutput,
};

// ── FFI-visible types ────────────────────────────────────────────────────────

/// A single asset to mint (positive quantity) or burn (negative quantity).
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MintAsset {
    /// Hex-encoded asset name bytes (max 32 bytes → max 64 hex chars).
    pub asset_name_hex: String,
    /// Positive = mint, negative = burn.
    pub quantity: i64,
}

/// Specification for minting/burning assets under one native-script policy.
#[derive(Clone, Debug)]
pub struct MintSpec {
    /// CBOR hex of the serialised `NativeScript` — use one of the constructor
    /// helpers or any externally-built script.
    pub policy_script_cbor_hex: String,
    pub assets: Vec<MintAsset>,
}

/// Result of a successfully built minting transaction.
#[derive(Clone, Debug)]
pub struct BuiltMintTx {
    /// Serialised transaction body (CBOR hex), ready for signing.
    pub tx_body_cbor_hex: String,
    /// Auxiliary data (CBOR hex) if metadata was attached; `None` otherwise.
    /// Pass this to `sign_tx_with_metadata` so it is included in the final tx.
    pub aux_data_cbor_hex: Option<String>,
    /// Blake2b-256 hash of the serialised body.
    pub tx_hash: String,
    /// Computed fee in lovelace.
    pub fee: u64,
}

// ── Policy script helpers ────────────────────────────────────────────────────

/// Build a single-signature native script keyed to `key_hash_hex`.
///
/// Returns the serialised `NativeScript` as CBOR hex.  The policy ID is the
/// Blake2b-224 hash of this bytes (use `compute_policy_id`).
#[frb(sync)]
pub fn make_pubkey_script(key_hash_hex: String) -> Result<String, CardanoError> {
    let key_hash_bytes = hex_to_bytes(&key_hash_hex)?;
    let key_hash =
        csl::Ed25519KeyHash::from_bytes(key_hash_bytes).map_err(map_deserialize_error)?;
    let script = csl::NativeScript::new_script_pubkey(&csl::ScriptPubkey::new(&key_hash));
    Ok(hex::encode(script.to_bytes()))
}

/// Build an NFT minting policy: `ScriptAll [ ScriptPubKey, TimelockExpiry ]`.
///
/// Minting is only valid before `expiry_slot`; signing requires `key_hash_hex`.
/// This pattern produces a one-shot minting policy that provably stops at expiry,
/// giving collectors on-chain assurance of a fixed supply.
#[frb(sync)]
pub fn make_timelock_expiry_script(
    key_hash_hex: String,
    expiry_slot: u64,
) -> Result<String, CardanoError> {
    let key_hash_bytes = hex_to_bytes(&key_hash_hex)?;
    let key_hash =
        csl::Ed25519KeyHash::from_bytes(key_hash_bytes).map_err(map_deserialize_error)?;

    let pubkey_script =
        csl::NativeScript::new_script_pubkey(&csl::ScriptPubkey::new(&key_hash));
    let expiry_script = csl::NativeScript::new_timelock_expiry(
        &csl::TimelockExpiry::new_timelockexpiry(&csl::BigNum::from(expiry_slot)),
    );

    let mut scripts = csl::NativeScripts::new();
    scripts.add(&pubkey_script);
    scripts.add(&expiry_script);

    let all_script = csl::NativeScript::new_script_all(&csl::ScriptAll::new(&scripts));
    Ok(hex::encode(all_script.to_bytes()))
}

/// Compute the 28-byte policy ID (script hash) for a serialised native script.
///
/// # Arguments
/// - `native_script_cbor_hex`: CBOR hex produced by `make_pubkey_script` or
///   `make_timelock_expiry_script`
///
/// # Returns
/// 56-character lowercase hex string (28 bytes = Blake2b-224 of the script).
#[frb(sync)]
pub fn compute_policy_id(native_script_cbor_hex: String) -> Result<String, CardanoError> {
    let bytes = hex_to_bytes(&native_script_cbor_hex)?;
    let script = csl::NativeScript::from_bytes(bytes).map_err(map_deserialize_error)?;
    Ok(hex::encode(script.hash().to_bytes()))
}

// ── Mint transaction builder ─────────────────────────────────────────────────

/// Build a transaction that mints or burns native tokens under native scripts.
///
/// # Arguments
/// - `inputs`: UTxOs to spend (ADA source for fees and min-ADA)
/// - `outputs`: explicit outputs, e.g. recipient of minted tokens; change is
///   computed automatically
/// - `change_address`: receives ADA change (and any un-assigned minted tokens)
/// - `mint_specs`: one entry per minting policy; assets are positive (mint) or
///   negative (burn)
/// - `aux_data_cbor_hex`: pre-built CIP-25/68 auxiliary data; use
///   `build_cip25_metadata` to produce this
/// - `ttl`: slot deadline (`None` = no expiry)
/// - `params`: current protocol parameters
///
/// # Errors
/// - `InvalidParameter` if `inputs` or `mint_specs` are empty
/// - `InvalidAddress` if any address is malformed
/// - `TxBuild` if CSL builder fails (e.g. insufficient funds)
#[frb(sync)]
pub fn build_mint_tx(
    inputs: Vec<TxInput>,
    outputs: Vec<TxOutput>,
    change_address: String,
    mint_specs: Vec<MintSpec>,
    aux_data_cbor_hex: Option<String>,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltMintTx, CardanoError> {
    if inputs.is_empty() {
        return Err(CardanoError::InvalidParameter {
            field: "inputs".to_string(),
            reason: "At least one input is required".to_string(),
        });
    }
    if mint_specs.is_empty() {
        return Err(CardanoError::InvalidParameter {
            field: "mint_specs".to_string(),
            reason: "At least one mint specification is required".to_string(),
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

    // ── Inputs ────────────────────────────────────────────────────────────
    {
        let mut inputs_builder = csl::TxInputsBuilder::new();
        for input in &inputs {
            let (tx_input, value) = input_to_csl(input)?;
            let address = csl::Address::from_bech32(&input.address)
                .map_err(|_| CardanoError::InvalidAddress(input.address.clone()))?;
            inputs_builder
                .add_regular_input(&address, &tx_input, &value)
                .map_err(map_csl_error)?;
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

    // ── Mint ──────────────────────────────────────────────────────────────
    {
        let mut mint_builder = csl::MintBuilder::new();
        for spec in &mint_specs {
            let script_bytes = hex_to_bytes(&spec.policy_script_cbor_hex)?;
            let native_script =
                csl::NativeScript::from_bytes(script_bytes).map_err(map_deserialize_error)?;
            let native_script_source = csl::NativeScriptSource::new(&native_script);
            let mint_witness = csl::MintWitness::new_native_script(&native_script_source);

            for asset in &spec.assets {
                let name_bytes = hex_to_bytes(&asset.asset_name_hex)?;
                let asset_name = csl::AssetName::new(name_bytes).map_err(map_csl_error)?;
                let quantity = if asset.quantity >= 0 {
                    csl::Int::new(&csl::BigNum::from(asset.quantity as u64))
                } else {
                    csl::Int::new_negative(&csl::BigNum::from((-asset.quantity) as u64))
                };
                mint_builder
                    .add_asset(&mint_witness, &asset_name, &quantity)
                    .map_err(map_csl_error)?;
            }
        }
        tx_builder.set_mint_builder(&mint_builder);
    }

    // ── Auxiliary data (metadata) ─────────────────────────────────────────
    if let Some(ref aux_hex) = aux_data_cbor_hex {
        let aux_bytes = hex_to_bytes(aux_hex)?;
        let aux_data =
            csl::AuxiliaryData::from_bytes(aux_bytes).map_err(map_deserialize_error)?;
        tx_builder.set_auxiliary_data(&aux_data);
    }

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
    let tx_hash = hex::encode(hasher.finalize().as_slice());

    let fee: u64 = body
        .fee()
        .to_str()
        .parse()
        .map_err(|_| CardanoError::TxBuild {
            reason: "Failed to convert fee to u64".to_string(),
        })?;

    Ok(BuiltMintTx {
        tx_body_cbor_hex: body_cbor_hex,
        aux_data_cbor_hex,
        tx_hash,
        fee,
    })
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tx::{ProtocolParams, TxInput, TxOutput, Value};

    // A real Ed25519 key hash (28 bytes) used across tests.
    const TEST_KEY_HASH: &str = "e549a5aaf3a7f8ef34667e91a63db3cb0d4aa3d99f02ad7cac4ae5b0";

    fn params() -> ProtocolParams {
        ProtocolParams {
            min_fee_a: 44,
            min_fee_b: 155_381,
            coins_per_utxo_byte: 4_310,
            max_tx_size: 16_384,
            pool_deposit: 500_000_000,
            key_deposit: 2_000_000,
            max_val_size: 5_000,
        }
    }

    fn dummy_input(lovelace: u64) -> TxInput {
        TxInput {
            tx_hash: "0".repeat(64),
            output_index: 0,
            address: "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"
                .to_string(),
            value: Value {
                coin: lovelace,
                assets: vec![],
            },
        }
    }

    // ── Policy script helpers ────────────────────────────────────────────

    #[test]
    fn make_pubkey_script_roundtrips() {
        let cbor = make_pubkey_script(TEST_KEY_HASH.to_string()).unwrap();
        let bytes = hex::decode(&cbor).unwrap();
        // Must deserialise without error.
        csl::NativeScript::from_bytes(bytes).expect("round-trip failed");
    }

    #[test]
    fn make_timelock_expiry_script_roundtrips() {
        let cbor =
            make_timelock_expiry_script(TEST_KEY_HASH.to_string(), 99_999_999).unwrap();
        let bytes = hex::decode(&cbor).unwrap();
        csl::NativeScript::from_bytes(bytes).expect("round-trip failed");
    }

    #[test]
    fn compute_policy_id_returns_28_bytes() {
        let script = make_pubkey_script(TEST_KEY_HASH.to_string()).unwrap();
        let policy_id = compute_policy_id(script).unwrap();
        assert_eq!(
            policy_id.len(),
            56,
            "Policy ID must be 28 bytes (56 hex chars)"
        );
    }

    #[test]
    fn compute_policy_id_is_deterministic() {
        let script = make_pubkey_script(TEST_KEY_HASH.to_string()).unwrap();
        assert_eq!(
            compute_policy_id(script.clone()).unwrap(),
            compute_policy_id(script).unwrap()
        );
    }

    #[test]
    fn policy_id_differs_across_scripts() {
        let s1 = make_pubkey_script(TEST_KEY_HASH.to_string()).unwrap();
        let s2 = make_timelock_expiry_script(TEST_KEY_HASH.to_string(), 1_000_000).unwrap();
        assert_ne!(
            compute_policy_id(s1).unwrap(),
            compute_policy_id(s2).unwrap()
        );
    }

    // ── build_mint_tx error cases ────────────────────────────────────────

    #[test]
    fn rejects_empty_inputs() {
        let script = make_pubkey_script(TEST_KEY_HASH.to_string()).unwrap();
        let result = build_mint_tx(
            vec![],
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            vec![MintSpec {
                policy_script_cbor_hex: script,
                assets: vec![MintAsset {
                    asset_name_hex: hex::encode(b"TestNFT"),
                    quantity: 1,
                }],
            }],
            None,
            None,
            params(),
        );
        assert!(
            matches!(result, Err(CardanoError::InvalidParameter { ref field, .. }) if field == "inputs")
        );
    }

    #[test]
    fn rejects_empty_mint_specs() {
        let result = build_mint_tx(
            vec![dummy_input(10_000_000)],
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            vec![],
            None,
            None,
            params(),
        );
        assert!(
            matches!(result, Err(CardanoError::InvalidParameter { ref field, .. }) if field == "mint_specs")
        );
    }

    // ── build_mint_tx happy path ─────────────────────────────────────────

    #[test]
    fn build_mint_tx_produces_valid_cbor() {
        let script = make_pubkey_script(TEST_KEY_HASH.to_string()).unwrap();
        let policy_id = compute_policy_id(script.clone()).unwrap();

        let change_addr =
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string();
        let recipient = change_addr.clone();

        let result = build_mint_tx(
            vec![dummy_input(10_000_000)],
            vec![TxOutput {
                address: recipient,
                value: crate::tx::Value {
                    coin: 2_000_000,
                    assets: vec![crate::tx::NativeAsset {
                        policy_id: policy_id.clone(),
                        asset_name: hex::encode(b"TestNFT"),
                        quantity: 1,
                    }],
                },
            }],
            change_addr,
            vec![MintSpec {
                policy_script_cbor_hex: script,
                assets: vec![MintAsset {
                    asset_name_hex: hex::encode(b"TestNFT"),
                    quantity: 1,
                }],
            }],
            None,
            Some(99_999_999),
            params(),
        );

        assert!(result.is_ok(), "build_mint_tx failed: {:?}", result);
        let built = result.unwrap();

        // Body CBOR must deserialise.
        let body_bytes = hex::decode(&built.tx_body_cbor_hex).unwrap();
        csl::TransactionBody::from_bytes(body_bytes).expect("body CBOR is invalid");

        // tx_hash must be 32 bytes (64 hex chars).
        assert_eq!(built.tx_hash.len(), 64);

        // fee must be > 0.
        assert!(built.fee > 0, "fee should be positive");
    }
}
