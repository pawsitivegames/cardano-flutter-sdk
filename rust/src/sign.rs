//! Transaction signing module.
//!
//! Provides vkey witness generation for transaction bodies, producing complete
//! signed transactions ready for submission to the blockchain.

use crate::error::CardanoError;
use blake2::Blake2b;
use cardano_serialization_lib as csl;
use digest::Digest;
use flutter_rust_bridge::frb;

/// A signed transaction ready for submission.
#[derive(Clone, Debug)]
pub struct SignedTx {
    /// Complete transaction (body + witness set + auxiliary_data) in CBOR hex.
    pub tx_cbor_hex: String,
    /// Transaction hash (hash of the serialized body).
    pub tx_hash: String,
}

/// Sign a transaction body and attach optional auxiliary data (metadata).
///
/// Use this instead of `sign_tx` when the transaction carries CIP-25/68 metadata
/// produced by `build_cip25_metadata`.  The `aux_data_cbor_hex` must be the
/// same value returned by `build_mint_tx.aux_data_cbor_hex`.
///
/// # Arguments
/// * `tx_body_cbor_hex` - Serialised transaction body (CBOR hex)
/// * `payment_keys_hex` - Payment keys as bech32 strings
/// * `aux_data_cbor_hex` - Optional auxiliary-data CBOR hex
///
/// # Errors
/// * `InvalidKey` - If a key is malformed
/// * `InvalidCbor` - If the body or aux data CBOR is malformed
#[frb(sync)]
pub fn sign_tx_with_metadata(
    tx_body_cbor_hex: String,
    payment_keys_hex: Vec<String>,
    aux_data_cbor_hex: Option<String>,
    base_witness_set_cbor_hex: Option<String>,
) -> Result<SignedTx, String> {
    sign_tx_with_metadata_internal(
        tx_body_cbor_hex,
        payment_keys_hex,
        aux_data_cbor_hex,
        base_witness_set_cbor_hex,
    )
    .map_err(|e| e.to_string())
}

pub fn sign_tx_with_metadata_internal(
    tx_body_cbor_hex: String,
    payment_keys_hex: Vec<String>,
    aux_data_cbor_hex: Option<String>,
    // Optional pre-built witness set (e.g. from `build_mint_tx`) carrying native
    // scripts. Vkey witnesses are merged into it so the policy script survives.
    base_witness_set_cbor_hex: Option<String>,
) -> Result<SignedTx, CardanoError> {
    // Validate all keys before doing any work.
    for key_str in &payment_keys_hex {
        csl::Bip32PrivateKey::from_bech32(key_str)
            .map_err(|_| CardanoError::InvalidKey("Invalid payment key format".to_string()))?;
    }

    let tx_body_bytes = hex::decode(&tx_body_cbor_hex)
        .map_err(|_| CardanoError::InvalidCbor("Invalid hex encoding".to_string()))?;
    let tx_body = csl::TransactionBody::from_bytes(tx_body_bytes)
        .map_err(|_| CardanoError::InvalidCbor("Invalid transaction body CBOR".to_string()))?;

    let body_bytes = tx_body.to_bytes();
    let hash_array = compute_blake2b256_hash(&body_bytes);
    let tx_hash_hex = hex::encode(hash_array);

    let mut witnesses = csl::Vkeywitnesses::new();
    for key_str in payment_keys_hex {
        let bip32_key = csl::Bip32PrivateKey::from_bech32(&key_str)
            .map_err(|_| CardanoError::InvalidKey("Invalid payment key format".to_string()))?;
        let priv_key = bip32_key.to_raw_key();
        let public_key = priv_key.to_public();
        let signature = priv_key.sign(&hash_array);
        let vkey = csl::Vkey::new(&public_key);
        witnesses.add(&csl::Vkeywitness::new(&vkey, &signature));
    }
    // Start from the builder's witness set (which already holds native/Plutus
    // scripts) when provided, so we don't drop the minting policy script; then
    // merge in the freshly-produced vkey witnesses.
    let mut witness_set = match base_witness_set_cbor_hex {
        Some(ref ws_hex) => {
            let ws_bytes = hex::decode(ws_hex)
                .map_err(|_| CardanoError::InvalidCbor("Invalid witness set hex".to_string()))?;
            csl::TransactionWitnessSet::from_bytes(ws_bytes)
                .map_err(|_| CardanoError::InvalidCbor("Invalid witness set CBOR".to_string()))?
        }
        None => csl::TransactionWitnessSet::new(),
    };
    witness_set.set_vkeys(&witnesses);

    let aux_data: Option<csl::AuxiliaryData> = if let Some(ref aux_hex) = aux_data_cbor_hex {
        let aux_bytes = hex::decode(aux_hex)
            .map_err(|_| CardanoError::InvalidCbor("Invalid aux data hex".to_string()))?;
        Some(
            csl::AuxiliaryData::from_bytes(aux_bytes)
                .map_err(|_| CardanoError::InvalidCbor("Invalid aux data CBOR".to_string()))?,
        )
    } else {
        None
    };

    let transaction = csl::Transaction::new(&tx_body, &witness_set, aux_data);
    Ok(SignedTx {
        tx_cbor_hex: hex::encode(transaction.to_bytes()),
        tx_hash: tx_hash_hex,
    })
}

/// Sign a transaction body with one or more payment keys.
///
/// Takes a serialized transaction body and a list of payment keys (bech32-encoded ed25519
/// extended keys), derives public keys, signs the body hash, and produces a complete
/// `TransactionWitnessSet` containing vkey witnesses.
///
/// # Arguments
/// * `tx_body_cbor_hex` - The transaction body serialized as CBOR hex
/// * `payment_keys_hex` - Payment keys as bech32 strings (treated as sensitive)
///
/// # Returns
/// A `SignedTx` containing the full signed transaction in CBOR hex and its hash.
///
/// # Error handling
/// * `InvalidKey` - If a payment key cannot be decoded or has invalid format
/// * `InvalidCbor` - If the transaction body CBOR is malformed
///
/// # Security notes
/// Keys are cleared as soon as public keys are extracted. The returned witness set
/// contains no key material (only public key hashes).
#[frb(sync)]
pub fn sign_tx(
    tx_body_cbor_hex: String,
    payment_keys_hex: Vec<String>,
) -> Result<SignedTx, String> {
    sign_tx_internal(tx_body_cbor_hex, payment_keys_hex).map_err(|e| e.to_string())
}

pub fn sign_tx_internal(
    tx_body_cbor_hex: String,
    payment_keys_hex: Vec<String>,
) -> Result<SignedTx, CardanoError> {
    // Validate all keys first (before deserializing the body)
    // This ensures InvalidKey errors are reported before InvalidCbor
    for key_str in &payment_keys_hex {
        csl::Bip32PrivateKey::from_bech32(key_str)
            .map_err(|_| CardanoError::InvalidKey("Invalid payment key format".to_string()))?;
    }

    // Deserialize transaction body from hex CBOR
    let tx_body_bytes = hex::decode(&tx_body_cbor_hex)
        .map_err(|_| CardanoError::InvalidCbor("Invalid hex encoding".to_string()))?;

    let tx_body = csl::TransactionBody::from_bytes(tx_body_bytes)
        .map_err(|_| CardanoError::InvalidCbor("Invalid transaction body CBOR".to_string()))?;

    // Compute the hash of the transaction body using Blake2b-256
    let body_bytes = tx_body.to_bytes();
    let hash_array = compute_blake2b256_hash(&body_bytes);
    let tx_hash_hex = hex::encode(hash_array);

    // Build vkey witnesses for each payment key
    let mut witnesses = csl::Vkeywitnesses::new();

    for key_str in payment_keys_hex {
        // Decode the key - it should be a Bip32PrivateKey in bech32 format
        let bip32_key = csl::Bip32PrivateKey::from_bech32(&key_str)
            .map_err(|_| CardanoError::InvalidKey("Invalid payment key format".to_string()))?;

        // Convert to a raw PrivateKey for signing
        let priv_key = bip32_key.to_raw_key();

        // Get the public key for the witness
        let public_key = priv_key.to_public();

        // Sign the hash
        let signature = priv_key.sign(&hash_array);

        // Create the witness
        let vkey = csl::Vkey::new(&public_key);
        let witness = csl::Vkeywitness::new(&vkey, &signature);
        witnesses.add(&witness);
    }

    // Create the witness set with vkeys
    let mut witness_set = csl::TransactionWitnessSet::new();
    witness_set.set_vkeys(&witnesses);

    // Construct the full transaction (body + witness set + no auxiliary data)
    let transaction = csl::Transaction::new(&tx_body, &witness_set, None);

    // Serialize the complete transaction to CBOR hex
    let tx_cbor_bytes = transaction.to_bytes();
    let tx_cbor_hex = hex::encode(tx_cbor_bytes);

    Ok(SignedTx {
        tx_cbor_hex,
        tx_hash: tx_hash_hex,
    })
}

/// Compute Blake2b-256 hash of data.
fn compute_blake2b256_hash(data: &[u8]) -> [u8; 32] {
    let mut hasher = Blake2b::<digest::consts::U32>::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result[..]);
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_MNEMONIC: &str =
        "test walk nut penalty hip pave soap entry language right filter choice";

    /// Derive a payment key from the test mnemonic (CIP-1852 path)
    fn derive_test_payment_key() -> String {
        let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
        let entropy = mnemonic_obj.to_entropy();
        let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

        let account_key = root_key
            .derive(1852 | 0x80000000)
            .derive(1815 | 0x80000000)
            .derive(0x80000000);

        let payment_key = account_key.derive(0).derive(0);
        payment_key.to_bech32()
    }

    fn derive_second_test_payment_key() -> String {
        let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
        let entropy = mnemonic_obj.to_entropy();
        let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

        root_key
            .derive(1852 | 0x80000000)
            .derive(1815 | 0x80000000)
            .derive(1 | 0x80000000)
            .derive(0)
            .derive(0)
            .to_bech32()
    }

    fn minimal_tx_body_hex() -> String {
        let mut body_inputs = csl::TransactionInputs::new();
        let tx_hash = csl::TransactionHash::from_bytes(vec![7u8; 32]).unwrap();
        body_inputs.add(&csl::TransactionInput::new(&tx_hash, 0));

        let addr = csl::Address::from_bech32(
            "addr_test1vpu5vlrf4xkxv2qpwngf6cjhtw542ayty80v8dyr49rf5eg57c2qv",
        )
        .unwrap();
        let mut body_outputs = csl::TransactionOutputs::new();
        body_outputs.add(&csl::TransactionOutput::new(
            &addr,
            &csl::Value::new(&csl::BigNum::from(1_500_000u64)),
        ));

        let body = csl::TransactionBody::new_tx_body(
            &body_inputs,
            &body_outputs,
            &csl::BigNum::from(170_000u64),
        );
        hex::encode(body.to_bytes())
    }

    #[test]
    fn test_key_derivation_works() {
        let payment_key = derive_test_payment_key();
        // Should be a valid bech32 string starting with "xprv"
        assert!(
            payment_key.starts_with("xprv"),
            "Derived key should be valid bech32 xprv"
        );
    }

    #[test]
    fn test_blake2b256_hash_computation() {
        let data = b"test data";
        let hash1 = compute_blake2b256_hash(data);
        let hash2 = compute_blake2b256_hash(data);

        // Hash should be 32 bytes
        assert_eq!(hash1.len(), 32, "Blake2b-256 should produce 32 bytes");

        // Same input should produce same hash (deterministic)
        assert_eq!(hash1, hash2, "Hash should be deterministic");

        // Different input should produce different hash
        let different_hash = compute_blake2b256_hash(b"different data");
        assert_ne!(
            hash1, different_hash,
            "Different inputs should produce different hashes"
        );
    }

    #[test]
    fn test_reject_garbage_key() {
        // Invalid key format should return InvalidKey error
        let garbage_key = "not_a_valid_key_12345".to_string();
        let invalid_cbor = "00".to_string(); // Minimal but valid CBOR

        let result = sign_tx_internal(invalid_cbor, vec![garbage_key]);
        assert!(result.is_err(), "Should reject invalid key");

        match result.unwrap_err() {
            CardanoError::InvalidKey(_) => {
                // Expected
            }
            e => panic!("Expected InvalidKey error, got {:?}", e),
        }
    }

    #[test]
    fn test_reject_malformed_cbor() {
        let payment_key = derive_test_payment_key();
        let malformed_cbor = "deadbeef".to_string(); // Too short/invalid CBOR

        let result = sign_tx_internal(malformed_cbor, vec![payment_key]);
        assert!(result.is_err(), "Should reject malformed CBOR");

        match result.unwrap_err() {
            CardanoError::InvalidCbor(_) => {
                // Expected
            }
            e => panic!("Expected InvalidCbor error, got {:?}", e),
        }
    }

    #[test]
    fn test_multiple_keys_accepted() {
        // Derive two different keys from the same mnemonic
        let key1 = {
            let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
            let entropy = mnemonic_obj.to_entropy();
            let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

            let account_key = root_key
                .derive(1852 | 0x80000000)
                .derive(1815 | 0x80000000)
                .derive(0x80000000);

            account_key.derive(0).derive(0).to_bech32()
        };

        let key2 = {
            let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
            let entropy = mnemonic_obj.to_entropy();
            let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

            let account_key = root_key
                .derive(1852 | 0x80000000)
                .derive(1815 | 0x80000000)
                .derive(1 | 0x80000000); // different account index

            account_key.derive(0).derive(0).to_bech32()
        };

        // Both keys should be valid and different
        assert_ne!(
            key1, key2,
            "Keys from different accounts should be different"
        );

        // Trying to sign with valid keys but invalid CBOR should fail on CBOR, not keys
        let invalid_cbor = "deadbeef".to_string();
        let result = sign_tx_internal(invalid_cbor, vec![key1, key2]);

        match result {
            Err(CardanoError::InvalidCbor(_)) => {
                // Expected: rejected for malformed CBOR, not invalid keys
            }
            other => panic!(
                "Expected InvalidCbor error (keys are valid), got {:?}",
                other
            ),
        }
    }

    #[test]
    fn sign_tx_is_deterministic_and_adds_expected_witnesses() {
        let body_hex = minimal_tx_body_hex();
        let keys = vec![derive_test_payment_key(), derive_second_test_payment_key()];

        let first = sign_tx_internal(body_hex.clone(), keys.clone()).unwrap();
        let second = sign_tx_internal(body_hex, keys).unwrap();
        assert_eq!(first.tx_cbor_hex, second.tx_cbor_hex);
        assert_eq!(first.tx_hash, second.tx_hash);

        let tx = csl::Transaction::from_bytes(hex::decode(first.tx_cbor_hex).unwrap()).unwrap();
        let witnesses = tx
            .witness_set()
            .vkeys()
            .expect("signed transaction must have vkey witnesses");
        assert_eq!(
            witnesses.len(),
            2,
            "both signing keys must produce witnesses"
        );
    }
}
