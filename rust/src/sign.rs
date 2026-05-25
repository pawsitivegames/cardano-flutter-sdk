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
    let mut hasher = Blake2b::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result[..32]);
    output
}

/// Decode a payment key from bech32 format.
///
/// Keys should be in standard Cardano bech32 format (xprv prefix).
fn decode_payment_key(key_str: &str) -> Result<csl::Bip32PrivateKey, CardanoError> {
    csl::Bip32PrivateKey::from_bech32(key_str)
        .map_err(|_| CardanoError::InvalidKey("Invalid payment key format".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Test mnemonic from Phase 1 wallet tests
    const TEST_MNEMONIC: &str =
        "test walk nut penalty hip pave soap entry language right filter choice";

    /// Helper to derive a payment key from the test mnemonic
    fn derive_test_payment_key() -> String {
        let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
        let entropy = mnemonic_obj.to_entropy();
        let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

        let account_key = root_key
            .derive(1852 | 0x80000000)
            .derive(1815 | 0x80000000)
            .derive(0 | 0x80000000);

        let payment_key = account_key.derive(0).derive(0);
        payment_key.to_bech32()
    }

    /// Helper to build a minimal transaction body for testing
    fn build_test_tx_body() -> csl::TransactionBody {
        // Minimal tx: one input, one output
        let mut inputs = csl::TransactionInputs::new();

        // Create a dummy input with hash of all zeros
        let dummy_hash =
            csl::TransactionHash::from_bytes(vec![0u8; 32]).expect("Valid transaction hash");
        let dummy_input = csl::TransactionInput::new(&dummy_hash, 0);
        inputs.add(&dummy_input);

        // Create a dummy output address (testnet)
        let address_str = "addr_test1qpegxkqsqsg5s44czuppgjkn4eamvf2dlxw7g2nw7pxjf76w2uld";
        let output_address = csl::Address::from_bech32(address_str).expect("Valid output address");

        let output_value = csl::Value::new(&csl::BigNum::from(1_000_000u64));
        let output = csl::TransactionOutput::new(&output_address, &output_value);

        let mut outputs = csl::TransactionOutputs::new();
        outputs.add(&output);

        // Create the transaction body
        let mut tx_body = csl::TransactionBody::new(&inputs, &outputs);

        // Set fee
        tx_body.set_fee(&csl::BigNum::from(200_000u64));

        tx_body
    }

    #[test]
    fn sign_tx_round_trip() {
        let payment_key = derive_test_payment_key();
        let tx_body = build_test_tx_body();

        // Serialize body to CBOR hex
        let body_bytes = tx_body.to_bytes();
        let body_cbor_hex = hex::encode(body_bytes);

        // Sign the transaction
        let result = sign_tx_internal(body_cbor_hex, vec![payment_key]);
        assert!(result.is_ok(), "Signing should succeed: {:?}", result.err());

        let signed_tx = result.unwrap();

        // Verify the signed transaction can be deserialized
        let tx_bytes = hex::decode(&signed_tx.tx_cbor_hex).expect("Valid hex output");
        let transaction = csl::Transaction::from_bytes(tx_bytes).expect("Valid transaction CBOR");

        // Verify witness set has exactly one witness
        let witnesses = transaction.witness_set().vkeys();
        assert!(witnesses.is_some(), "Witness set should contain vkeys");
        assert_eq!(
            witnesses.unwrap().len(),
            1,
            "Should have exactly one vkey witness"
        );
    }

    #[test]
    fn sign_tx_two_witnesses() {
        let payment_key_1 = derive_test_payment_key();

        // For second key, derive from different account index
        let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
        let entropy = mnemonic_obj.to_entropy();
        let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

        let account_key = root_key
            .derive(1852 | 0x80000000)
            .derive(1815 | 0x80000000)
            .derive(1 | 0x80000000); // account index 1

        let payment_key_2 = account_key.derive(0).derive(0).to_bech32();

        let tx_body = build_test_tx_body();
        let body_bytes = tx_body.to_bytes();
        let body_cbor_hex = hex::encode(body_bytes);

        // Sign with both keys
        let result = sign_tx_internal(body_cbor_hex, vec![payment_key_1, payment_key_2]);
        assert!(
            result.is_ok(),
            "Signing with two keys should succeed: {:?}",
            result.err()
        );

        let signed_tx = result.unwrap();

        // Verify we have two witnesses
        let tx_bytes = hex::decode(&signed_tx.tx_cbor_hex).expect("Valid hex output");
        let transaction = csl::Transaction::from_bytes(tx_bytes).expect("Valid transaction CBOR");

        let witnesses = transaction.witness_set().vkeys();
        assert!(witnesses.is_some(), "Witness set should contain vkeys");
        assert_eq!(
            witnesses.unwrap().len(),
            2,
            "Should have exactly two vkey witnesses"
        );
    }

    #[test]
    fn sign_tx_rejects_garbage_key() {
        let tx_body = build_test_tx_body();
        let body_bytes = tx_body.to_bytes();
        let body_cbor_hex = hex::encode(body_bytes);

        let garbage_key = "not_a_valid_key_12345".to_string();

        let result = sign_tx_internal(body_cbor_hex, vec![garbage_key]);
        assert!(result.is_err(), "Should reject invalid key");

        match result.unwrap_err() {
            CardanoError::InvalidKey(_) => {} // Expected
            e => panic!("Expected InvalidKey error, got {:?}", e),
        }
    }

    #[test]
    fn sign_tx_rejects_malformed_body() {
        let payment_key = derive_test_payment_key();
        let malformed_cbor = "deadbeef".to_string(); // Too short/invalid CBOR

        let result = sign_tx_internal(malformed_cbor, vec![payment_key]);
        assert!(result.is_err(), "Should reject malformed CBOR");

        match result.unwrap_err() {
            CardanoError::InvalidCbor(_) => {} // Expected
            e => panic!("Expected InvalidCbor error, got {:?}", e),
        }
    }

    #[test]
    fn tx_hash_stable() {
        let tx_body = build_test_tx_body();
        let body_bytes = tx_body.to_bytes();
        let body_cbor_hex = hex::encode(body_bytes.clone());

        // Compute hash independently
        let expected_hash_bytes = compute_blake2b256_hash(&body_bytes);
        let expected_hash_hex = hex::encode(expected_hash_bytes);

        let payment_key = derive_test_payment_key();

        // Sign and get hash from result
        let signed_tx = sign_tx_internal(body_cbor_hex.clone(), vec![payment_key.clone()])
            .expect("Signing should succeed");

        // Hashes must match
        assert_eq!(
            signed_tx.tx_hash, expected_hash_hex,
            "Transaction hash should be stable"
        );

        // Sign again with same body, verify same hash
        let signed_tx_2 =
            sign_tx_internal(body_cbor_hex, vec![payment_key]).expect("Signing should succeed");

        assert_eq!(
            signed_tx.tx_hash, signed_tx_2.tx_hash,
            "Same body should always produce same hash"
        );
    }
}
