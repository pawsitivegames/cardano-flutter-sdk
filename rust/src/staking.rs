//! Staking operations: certificate building and reward withdrawal (Phase 4.1).
//!
//! Provides functions to build stake registration, delegation, withdrawal, and
//! deregistration transactions.  All functions return a serialised transaction body
//! ready to be signed with `sign_tx` using both the payment key and stake key.

use blake2::{
    digest::{consts::U32, Digest},
    Blake2b,
};
use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

use crate::error::CardanoError;
use crate::tx::{hex_to_bytes, input_to_csl, map_csl_error, map_deserialize_error, ProtocolParams, TxInput};

// ── Public types ─────────────────────────────────────────────────────────────

/// Result of a successfully built staking transaction.
#[derive(Clone, Debug)]
pub struct BuiltStakingTx {
    /// Serialised transaction body (CBOR hex), ready for signing.
    pub tx_body_cbor_hex: String,
    /// Blake2b-256 hash of the body.
    pub tx_hash: String,
    /// Computed fee in lovelace.
    pub fee: u64,
    /// Deposit change in lovelace:
    /// - negative = deposit paid (registration)
    /// - positive = deposit returned (deregistration)
    /// - 0 = neutral (delegation, withdrawal)
    pub deposit_change: i64,
}

// ── Internal helpers ─────────────────────────────────────────────────────────

/// Parse a stake key hash hex string into a CSL Credential.
fn stake_credential(stake_key_hash_hex: &str) -> Result<csl::Credential, CardanoError> {
    let bytes = hex_to_bytes(stake_key_hash_hex)?;
    let key_hash = csl::Ed25519KeyHash::from_bytes(bytes).map_err(map_deserialize_error)?;
    Ok(csl::Credential::from_keyhash(&key_hash))
}

/// Build a TransactionBuilder with the standard protocol-params config.
fn make_tx_builder(params: &ProtocolParams) -> Result<csl::TransactionBuilder, CardanoError> {
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
    Ok(csl::TransactionBuilder::new(&config))
}

/// Add inputs to a TransactionBuilder via TxInputsBuilder.
fn add_inputs(
    builder: &mut csl::TransactionBuilder,
    inputs: &[TxInput],
) -> Result<(), CardanoError> {
    if inputs.is_empty() {
        return Err(CardanoError::InvalidParameter {
            field: "inputs".to_string(),
            reason: "At least one input is required".to_string(),
        });
    }
    let mut inputs_builder = csl::TxInputsBuilder::new();
    for input in inputs {
        let (tx_input, value) = input_to_csl(input)?;
        let address = csl::Address::from_bech32(&input.address).map_err(|_| {
            CardanoError::InvalidAddress("Invalid input address bech32".to_string())
        })?;
        inputs_builder
            .add_regular_input(&address, &tx_input, &value)
            .map_err(map_csl_error)?;
    }
    builder.set_inputs(&inputs_builder);
    Ok(())
}

/// Finalise a builder: add change output, build the tx, hash the body, return result.
fn finalise(
    builder: &mut csl::TransactionBuilder,
    change_address: &str,
    ttl: Option<u64>,
    deposit_change: i64,
) -> Result<BuiltStakingTx, CardanoError> {
    if let Some(slot) = ttl {
        builder.set_ttl_bignum(&csl::BigNum::from(slot));
    }

    let change_addr = csl::Address::from_bech32(change_address)
        .map_err(|_| CardanoError::InvalidAddress("Invalid change address".to_string()))?;
    builder
        .add_change_if_needed(&change_addr)
        .map_err(|e| CardanoError::TxBuild {
            reason: format!("Failed to compute change: {:?}", e),
        })?;

    let tx = builder.build_tx().map_err(|e| CardanoError::TxBuild {
        reason: format!("Failed to build transaction: {:?}", e),
    })?;

    let body = tx.body();
    let body_bytes = body.to_bytes();

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

    Ok(BuiltStakingTx {
        tx_body_cbor_hex: hex::encode(body_bytes),
        tx_hash,
        fee,
        deposit_change,
    })
}

// ── Public FFI functions ──────────────────────────────────────────────────────

/// Build a stake key registration transaction.
///
/// Costs `key_deposit` lovelace (typically 2 ADA on mainnet). The deposit is
/// returned upon deregistration.  The stake key must be registered before it
/// can be delegated to a pool.
///
/// # Arguments
/// - `stake_key_hash_hex`: 56-char hex Blake2b-224 hash of the stake public key
/// - `inputs`: UTxOs covering the deposit + fees
/// - `change_address`: bech32 address for ADA change
/// - `network_id`: 0 = testnet, 1 = mainnet
/// - `ttl`: optional slot deadline
/// - `params`: current protocol parameters
///
/// # Errors
/// - `InvalidParameter` if inputs are empty or stake_key_hash_hex is invalid
/// - `InvalidAddress` if any address is malformed
/// - `TxBuild` if the builder fails
#[frb(sync)]
pub fn build_stake_registration_tx(
    stake_key_hash_hex: String,
    inputs: Vec<TxInput>,
    change_address: String,
    network_id: u8,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltStakingTx, CardanoError> {
    let _ = network_id;
    let credential = stake_credential(&stake_key_hash_hex)?;
    let cert =
        csl::Certificate::new_stake_registration(&csl::StakeRegistration::new(&credential));
    let mut certs_builder = csl::CertificatesBuilder::new();
    certs_builder.add(&cert).map_err(map_csl_error)?;

    let mut builder = make_tx_builder(&params)?;
    add_inputs(&mut builder, &inputs)?;
    builder.set_certs_builder(&certs_builder);

    let deposit_change = -(params.key_deposit as i64);
    finalise(&mut builder, &change_address, ttl, deposit_change)
}

/// Build a stake delegation transaction.
///
/// Delegates the stake key to the pool identified by `pool_keyhash_hex`.
/// The stake key must already be registered on-chain.  No deposit is required.
///
/// # Arguments
/// - `stake_key_hash_hex`: 56-char hex of the stake key hash
/// - `pool_keyhash_hex`: 56-char hex of the target pool's operator key hash
/// - `inputs`: UTxOs covering the fee
/// - `change_address`: bech32 address for ADA change
/// - `network_id`: 0 = testnet, 1 = mainnet
/// - `ttl`: optional slot deadline
/// - `params`: current protocol parameters
#[frb(sync)]
pub fn build_delegation_tx(
    stake_key_hash_hex: String,
    pool_keyhash_hex: String,
    inputs: Vec<TxInput>,
    change_address: String,
    network_id: u8,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltStakingTx, CardanoError> {
    let _ = network_id;
    let credential = stake_credential(&stake_key_hash_hex)?;
    let pool_bytes = hex_to_bytes(&pool_keyhash_hex)?;
    let pool_keyhash =
        csl::Ed25519KeyHash::from_bytes(pool_bytes).map_err(map_deserialize_error)?;
    let cert = csl::Certificate::new_stake_delegation(&csl::StakeDelegation::new(
        &credential,
        &pool_keyhash,
    ));
    let mut certs_builder = csl::CertificatesBuilder::new();
    certs_builder.add(&cert).map_err(map_csl_error)?;

    let mut builder = make_tx_builder(&params)?;
    add_inputs(&mut builder, &inputs)?;
    builder.set_certs_builder(&certs_builder);

    finalise(&mut builder, &change_address, ttl, 0)
}

/// Build a reward withdrawal transaction.
///
/// Withdraws accumulated staking rewards from the reward address to `change_address`.
/// `reward_amount` must exactly match the on-chain withdrawable balance (use
/// `fetchAccountInfo` to query this before building).
///
/// # Arguments
/// - `stake_key_hash_hex`: 56-char hex of the stake key hash
/// - `reward_amount`: exact lovelace amount to withdraw (may be 0)
/// - `inputs`: UTxOs covering the fee (rewards reduce the net fee burden)
/// - `change_address`: bech32 address; also receives the withdrawn rewards + ADA change
/// - `network_id`: 0 = testnet, 1 = mainnet
/// - `ttl`: optional slot deadline
/// - `params`: current protocol parameters
#[frb(sync)]
pub fn build_reward_withdrawal_tx(
    stake_key_hash_hex: String,
    reward_amount: u64,
    inputs: Vec<TxInput>,
    change_address: String,
    network_id: u8,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltStakingTx, CardanoError> {
    let credential = stake_credential(&stake_key_hash_hex)?;
    let reward_addr = csl::RewardAddress::new(network_id, &credential);

    let mut withdrawals_builder = csl::WithdrawalsBuilder::new();
    withdrawals_builder
        .add(&reward_addr, &csl::BigNum::from(reward_amount))
        .map_err(map_csl_error)?;

    let mut builder = make_tx_builder(&params)?;
    add_inputs(&mut builder, &inputs)?;
    builder.set_withdrawals_builder(&withdrawals_builder);

    finalise(&mut builder, &change_address, ttl, 0)
}

/// Build a stake key deregistration transaction.
///
/// Returns the `key_deposit` lovelace to `change_address`.  After deregistration
/// the stake key is no longer delegated and must be re-registered to earn rewards.
///
/// # Arguments
/// - `stake_key_hash_hex`: 56-char hex of the stake key hash
/// - `inputs`: UTxOs covering the fee (the returned deposit subsidises it)
/// - `change_address`: bech32 address; receives the returned deposit + ADA change
/// - `network_id`: 0 = testnet, 1 = mainnet
/// - `ttl`: optional slot deadline
/// - `params`: current protocol parameters
#[frb(sync)]
pub fn build_stake_deregistration_tx(
    stake_key_hash_hex: String,
    inputs: Vec<TxInput>,
    change_address: String,
    network_id: u8,
    ttl: Option<u64>,
    params: ProtocolParams,
) -> Result<BuiltStakingTx, CardanoError> {
    let _ = network_id;
    let credential = stake_credential(&stake_key_hash_hex)?;
    let cert = csl::Certificate::new_stake_deregistration(&csl::StakeDeregistration::new(
        &credential,
    ));
    let mut certs_builder = csl::CertificatesBuilder::new();
    certs_builder.add(&cert).map_err(map_csl_error)?;

    let mut builder = make_tx_builder(&params)?;
    add_inputs(&mut builder, &inputs)?;
    builder.set_certs_builder(&certs_builder);

    let deposit_change = params.key_deposit as i64;
    finalise(&mut builder, &change_address, ttl, deposit_change)
}

/// Compute the bech32 stake address (reward address) for a stake key hash.
///
/// # Arguments
/// - `stake_key_hash_hex`: 56-char hex Blake2b-224 hash of the stake public key
/// - `is_testnet`: true for testnet (`stake_test1...`), false for mainnet (`stake1...`)
///
/// # Returns
/// The bech32 reward address string.
#[frb(sync)]
pub fn compute_stake_address(
    stake_key_hash_hex: String,
    is_testnet: bool,
) -> Result<String, CardanoError> {
    let credential = stake_credential(&stake_key_hash_hex)?;
    let network_id: u8 = if is_testnet { 0 } else { 1 };
    let reward_addr = csl::RewardAddress::new(network_id, &credential);
    reward_addr
        .to_address()
        .to_bech32(None)
        .map_err(map_csl_error)
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tx::{ProtocolParams, TxInput, Value};
    use crate::wallet::derive_keys_from_mnemonic_internal;

    const TEST_MNEMONIC: &str =
        "test walk nut penalty hip pave soap entry language right filter choice";

    fn test_input() -> TxInput {
        TxInput {
            tx_hash: "0000000000000000000000000000000000000000000000000000000000000000"
                .to_string(),
            output_index: 0,
            // Enterprise address from test mnemonic (testnet)
            address: "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"
                .to_string(),
            value: Value {
                coin: 10_000_000,
                assets: vec![],
            },
        }
    }

    fn test_params() -> ProtocolParams {
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

    fn test_stake_key_hash() -> String {
        let keys = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false)
            .expect("key derivation failed");
        keys.stake_key_hash
    }

    // ── stake_credential helper ──────────────────────────────────────────────

    #[test]
    fn stake_credential_parses_valid_hash() {
        let hash = test_stake_key_hash();
        assert!(stake_credential(&hash).is_ok());
    }

    #[test]
    fn stake_credential_rejects_bad_hex() {
        assert!(stake_credential("ZZZZ").is_err());
    }

    // ── compute_stake_address ────────────────────────────────────────────────

    #[test]
    fn compute_stake_address_testnet() {
        let hash = test_stake_key_hash();
        let addr = compute_stake_address(hash, true).unwrap();
        assert!(
            addr.starts_with("stake_test1"),
            "testnet stake address should start with 'stake_test1', got: {}",
            addr
        );
    }

    #[test]
    fn compute_stake_address_mainnet() {
        let hash = test_stake_key_hash();
        let addr = compute_stake_address(hash, false).unwrap();
        assert!(
            addr.starts_with("stake1"),
            "mainnet stake address should start with 'stake1', got: {}",
            addr
        );
    }

    // ── build_stake_registration_tx ─────────────────────────────────────────

    #[test]
    fn registration_produces_cbor_and_correct_deposit() {
        let hash = test_stake_key_hash();
        let params = test_params();
        let expected_deposit = -(params.key_deposit as i64);

        let result = build_stake_registration_tx(
            hash,
            vec![test_input()],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            params,
        );
        assert!(result.is_ok(), "registration tx failed: {:?}", result);
        let built = result.unwrap();

        // Body must deserialise cleanly
        let body_bytes = hex::decode(&built.tx_body_cbor_hex).unwrap();
        csl::TransactionBody::from_bytes(body_bytes).expect("body CBOR is invalid");

        assert!(!built.tx_body_cbor_hex.is_empty());
        assert_eq!(built.tx_hash.len(), 64, "tx hash should be 32 bytes (64 hex)");
        assert!(built.fee > 0, "fee should be positive");
        assert_eq!(built.deposit_change, expected_deposit);
    }

    #[test]
    fn registration_empty_inputs_returns_error() {
        let hash = test_stake_key_hash();
        let result = build_stake_registration_tx(
            hash,
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            test_params(),
        );
        assert!(
            matches!(
                result,
                Err(CardanoError::InvalidParameter { ref field, .. }) if field == "inputs"
            ),
            "Expected InvalidParameter for inputs, got: {:?}",
            result
        );
    }

    // ── build_delegation_tx ──────────────────────────────────────────────────

    #[test]
    fn delegation_produces_cbor_and_zero_deposit() {
        let hash = test_stake_key_hash();
        // A valid-format 28-byte pool key hash (fake, but correct length)
        let pool_keyhash = "8e4d2a343f3dcf9330ad9035b3e8d168e6728905262f51f89bc706ce";

        let result = build_delegation_tx(
            hash,
            pool_keyhash.to_string(),
            vec![test_input()],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            test_params(),
        );
        assert!(result.is_ok(), "delegation tx failed: {:?}", result);
        let built = result.unwrap();

        let body_bytes = hex::decode(&built.tx_body_cbor_hex).unwrap();
        csl::TransactionBody::from_bytes(body_bytes).expect("body CBOR is invalid");

        assert!(!built.tx_body_cbor_hex.is_empty());
        assert_eq!(built.tx_hash.len(), 64);
        assert_eq!(built.deposit_change, 0);
    }

    #[test]
    fn delegation_empty_inputs_returns_error() {
        let hash = test_stake_key_hash();
        let pool_keyhash = "8e4d2a343f3dcf9330ad9035b3e8d168e6728905262f51f89bc706ce";
        let result = build_delegation_tx(
            hash,
            pool_keyhash.to_string(),
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            test_params(),
        );
        assert!(
            matches!(
                result,
                Err(CardanoError::InvalidParameter { ref field, .. }) if field == "inputs"
            )
        );
    }

    // ── build_reward_withdrawal_tx ───────────────────────────────────────────

    #[test]
    fn withdrawal_produces_cbor() {
        let hash = test_stake_key_hash();
        let result = build_reward_withdrawal_tx(
            hash,
            1_500_000, // 1.5 ADA of rewards
            vec![test_input()],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            test_params(),
        );
        assert!(result.is_ok(), "withdrawal tx failed: {:?}", result);
        let built = result.unwrap();

        let body_bytes = hex::decode(&built.tx_body_cbor_hex).unwrap();
        csl::TransactionBody::from_bytes(body_bytes).expect("body CBOR is invalid");
        assert_eq!(built.deposit_change, 0);
    }

    #[test]
    fn withdrawal_zero_amount_builds_successfully() {
        let hash = test_stake_key_hash();
        let result = build_reward_withdrawal_tx(
            hash,
            0,
            vec![test_input()],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            test_params(),
        );
        assert!(result.is_ok(), "zero withdrawal should succeed: {:?}", result);
    }

    #[test]
    fn withdrawal_empty_inputs_returns_error() {
        let hash = test_stake_key_hash();
        let result = build_reward_withdrawal_tx(
            hash,
            0,
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            test_params(),
        );
        assert!(
            matches!(
                result,
                Err(CardanoError::InvalidParameter { ref field, .. }) if field == "inputs"
            )
        );
    }

    // ── build_stake_deregistration_tx ────────────────────────────────────────

    #[test]
    fn deregistration_produces_cbor_and_correct_deposit_return() {
        let hash = test_stake_key_hash();
        let params = test_params();
        let expected_deposit = params.key_deposit as i64;

        let result = build_stake_deregistration_tx(
            hash,
            vec![test_input()],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            params,
        );
        assert!(result.is_ok(), "deregistration tx failed: {:?}", result);
        let built = result.unwrap();

        let body_bytes = hex::decode(&built.tx_body_cbor_hex).unwrap();
        csl::TransactionBody::from_bytes(body_bytes).expect("body CBOR is invalid");

        assert!(!built.tx_body_cbor_hex.is_empty());
        assert_eq!(built.deposit_change, expected_deposit);
    }

    #[test]
    fn deregistration_empty_inputs_returns_error() {
        let hash = test_stake_key_hash();
        let result = build_stake_deregistration_tx(
            hash,
            vec![],
            "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
            0,
            None,
            test_params(),
        );
        assert!(
            matches!(
                result,
                Err(CardanoError::InvalidParameter { ref field, .. }) if field == "inputs"
            )
        );
    }
}
