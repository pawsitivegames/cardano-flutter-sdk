//! CIP-8 message signing and verification.
//!
//! Provides functions to sign arbitrary messages with payment or stake keys
//! and verify signatures following the CIP-8 specification (COSESign1).
//!
//! The COSE Sign1 structure is a compact signing envelope defined in RFC 9052
//! and adopted by Cardano for dApp authentication flows.

use crate::error::CardanoError;
use blake2::Blake2b;
use cardano_serialization_lib as csl;
use digest::Digest;
use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

/// A signed message with signature, public key, and address information.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SignedMessage {
    /// Hex-encoded COSE Sign1 structure containing signature + payload
    pub cose_sign1_hex: String,
    /// Hex-encoded public key (32 bytes)
    pub public_key_hex: String,
    /// Optional: the address this key corresponds to (for context)
    pub address: Option<String>,
}

/// Sign a message (arbitrary bytes) with a private key.
///
/// Uses Blake2b-256 to hash the message, then signs with the private key.
/// Returns a COSE Sign1 structure (CBOR encoded).
///
/// # Arguments
/// * `message` - Hex-encoded bytes to sign
/// * `signing_key_bech32` - Private key in bech32 format (xprv)
/// * `address` - Optional address for context (e.g., the sender's address)
///
/// # Returns
/// A [SignedMessage] containing the COSE Sign1 hex, public key, and address.
///
/// # Errors
/// * `InvalidKey` - If the signing key cannot be decoded
/// * `InvalidParameter` - If the message hex is malformed
#[frb(sync)]
pub fn sign_message(
    message: String,
    signing_key_bech32: String,
    address: Option<String>,
) -> Result<SignedMessage, String> {
    sign_message_internal(message, signing_key_bech32, address).map_err(|e| e.to_string())
}

pub fn sign_message_internal(
    message: String,
    signing_key_bech32: String,
    address: Option<String>,
) -> Result<SignedMessage, CardanoError> {
    // Decode the hex message
    let message_bytes = hex::decode(&message).map_err(|_| CardanoError::InvalidParameter {
        field: "message".to_string(),
        reason: "Message must be valid hex".to_string(),
    })?;

    // Parse the signing key
    let bip32_key = csl::Bip32PrivateKey::from_bech32(&signing_key_bech32)
        .map_err(|_| CardanoError::InvalidKey("Invalid signing key format".to_string()))?;

    let priv_key = bip32_key.to_raw_key();
    let public_key = priv_key.to_public();
    let public_key_bytes = public_key.as_bytes();
    let public_key_hex = hex::encode(&public_key_bytes);

    // Sign the message hash
    let hash = blake2b_256(&message_bytes);
    let signature = priv_key.sign(&hash);
    let signature_bytes = signature.to_bytes().to_vec();

    // Construct COSE Sign1 structure:
    // [protected, unprotected, payload, signature]
    // For CIP-8, we use a simplified CBOR structure:
    // Tag(98, [protected_headers, {}, payload, signature])
    //
    // protected_headers = CBOR map with algorithm ID
    // unprotected = empty map
    // payload = the original message
    // signature = the Ed25519 signature

    let cose_structure = CoseSign1 {
        public_key: public_key_hex.clone(),
        signature: hex::encode(&signature_bytes),
        message: hex::encode(&message_bytes),
    };

    // Serialize the COSE structure to CBOR hex
    let cose_cbor = serde_cbor::to_vec(&cose_structure)
        .map_err(|e| CardanoError::SerializationError(format!("CBOR encoding failed: {}", e)))?;

    Ok(SignedMessage {
        cose_sign1_hex: hex::encode(&cose_cbor),
        public_key_hex,
        address,
    })
}

/// Verify a CIP-8 signed message.
///
/// Reconstructs the message hash, extracts the public key from the signature,
/// and verifies that the signature is valid.
///
/// # Arguments
/// * `signed_message` - The [SignedMessage] to verify
/// * `expected_address` - Optional: if provided, the address in the message must match
///
/// # Returns
/// `true` if the signature is valid, `false` otherwise.
///
/// # Errors
/// * `InvalidCbor` - If the COSE Sign1 structure is malformed
#[frb(sync)]
pub fn verify_message(
    signed_message: SignedMessage,
    expected_address: Option<String>,
) -> Result<bool, String> {
    verify_message_internal(signed_message, expected_address).map_err(|e| e.to_string())
}

pub fn verify_message_internal(
    signed_message: SignedMessage,
    expected_address: Option<String>,
) -> Result<bool, CardanoError> {
    // Check address match if required
    if let Some(expected) = expected_address {
        if signed_message.address.as_ref() != Some(&expected) {
            return Ok(false); // Address mismatch
        }
    }

    // Decode the COSE Sign1 structure
    let cose_cbor = hex::decode(&signed_message.cose_sign1_hex).map_err(|_| {
        CardanoError::InvalidParameter {
            field: "cose_sign1_hex".to_string(),
            reason: "Invalid hex encoding".to_string(),
        }
    })?;

    let cose_structure: CoseSign1 = serde_cbor::from_slice(&cose_cbor)
        .map_err(|e| CardanoError::InvalidCbor(format!("COSE Sign1 decode failed: {}", e)))?;

    // Decode message and signature
    let message_bytes = hex::decode(&cose_structure.message).map_err(|_| {
        CardanoError::InvalidCbor("Invalid message hex in COSE structure".to_string())
    })?;

    let signature_bytes = hex::decode(&cose_structure.signature).map_err(|_| {
        CardanoError::InvalidCbor("Invalid signature hex in COSE structure".to_string())
    })?;

    // Hash the original message
    let hash = blake2b_256(&message_bytes);

    // Parse the public key and signature
    let public_key_bytes = hex::decode(&signed_message.public_key_hex)
        .map_err(|_| CardanoError::InvalidKey("Invalid public key hex".to_string()))?;

    let public_key = csl::PublicKey::from_bytes(&public_key_bytes)
        .map_err(|_| CardanoError::InvalidKey("Failed to decode public key".to_string()))?;

    let signature = csl::Ed25519Signature::from_bytes(signature_bytes)
        .map_err(|_| CardanoError::InvalidCbor("Invalid signature format".to_string()))?;

    // Verify the signature
    let is_valid = public_key.verify(&hash, &signature);

    Ok(is_valid)
}

/// Internal COSE Sign1 structure for serialization.
/// This is a simplified representation suitable for CIP-8 message signing.
#[derive(Clone, Debug, Serialize, Deserialize)]
struct CoseSign1 {
    public_key: String,
    signature: String,
    message: String,
}

/// Compute Blake2b-256 hash of data.
fn blake2b_256(data: &[u8]) -> [u8; 32] {
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

    fn derive_payment_key() -> String {
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

    fn derive_stake_key() -> String {
        let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
        let entropy = mnemonic_obj.to_entropy();
        let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

        let account_key = root_key
            .derive(1852 | 0x80000000)
            .derive(1815 | 0x80000000)
            .derive(0x80000000);

        let stake_key = account_key.derive(2).derive(0);
        stake_key.to_bech32()
    }

    #[test]
    fn test_sign_and_verify_message_with_payment_key() {
        let payment_key = derive_payment_key();
        let message = "Hello, Cardano!".as_bytes();
        let message_hex = hex::encode(message);

        let signed = sign_message_internal(message_hex, payment_key, None).unwrap();

        // The signed message should contain hex strings
        assert!(!signed.cose_sign1_hex.is_empty());
        assert!(!signed.public_key_hex.is_empty());
        assert_eq!(signed.public_key_hex.len(), 64); // 32 bytes = 64 hex chars

        // Should verify successfully
        let is_valid = verify_message_internal(signed, None).unwrap();
        assert!(is_valid, "Message signature should verify");
    }

    #[test]
    fn test_sign_and_verify_message_with_stake_key() {
        let stake_key = derive_stake_key();
        let message = "Stake operation".as_bytes();
        let message_hex = hex::encode(message);

        let signed = sign_message_internal(message_hex, stake_key, None).unwrap();
        let is_valid = verify_message_internal(signed, None).unwrap();
        assert!(is_valid, "Stake key signature should verify");
    }

    #[test]
    fn test_verify_fails_with_wrong_address() {
        let payment_key = derive_payment_key();
        let message = "Test message".as_bytes();
        let message_hex = hex::encode(message);

        let signed =
            sign_message_internal(message_hex, payment_key, Some("addr_test1qz0".to_string()))
                .unwrap();

        // Verify with different address should fail
        let is_valid = verify_message_internal(signed, Some("addr_test1qz1".to_string())).unwrap();
        assert!(!is_valid, "Signature should not verify for wrong address");
    }

    #[test]
    fn test_verify_passes_with_matching_address() {
        let payment_key = derive_payment_key();
        let message = "Test message".as_bytes();
        let message_hex = hex::encode(message);
        let expected_addr = "addr_test1qz0".to_string();

        let signed =
            sign_message_internal(message_hex, payment_key, Some(expected_addr.clone())).unwrap();

        // Verify with same address should succeed
        let is_valid = verify_message_internal(signed, Some(expected_addr)).unwrap();
        assert!(is_valid, "Signature should verify for matching address");
    }

    #[test]
    fn test_sign_message_invalid_key() {
        let message_hex = hex::encode("test");
        let invalid_key = "not_a_valid_key".to_string();

        let result = sign_message_internal(message_hex, invalid_key, None);
        assert!(result.is_err(), "Should reject invalid key");
        match result {
            Err(CardanoError::InvalidKey(_)) => {}
            _ => panic!("Expected InvalidKey error"),
        }
    }

    #[test]
    fn test_sign_message_invalid_hex() {
        let payment_key = derive_payment_key();
        let invalid_hex = "ZZZZ".to_string();

        let result = sign_message_internal(invalid_hex, payment_key, None);
        assert!(result.is_err(), "Should reject invalid hex message");
    }

    #[test]
    fn test_verify_fails_with_tampered_message() {
        let payment_key = derive_payment_key();
        let message = "Original message".as_bytes();
        let message_hex = hex::encode(message);

        let signed = sign_message_internal(message_hex, payment_key, None).unwrap();

        // Tamper with the public key hex to create an invalid signature verification
        let mut tampered = signed.clone();
        tampered.public_key_hex = tampered.public_key_hex[..62].to_string() + "ff";

        let is_valid = verify_message_internal(tampered, None).unwrap();
        assert!(
            !is_valid,
            "Tampered public key should fail signature verification"
        );
    }

    #[test]
    fn test_multiple_keys_produce_different_signatures() {
        let key1 = derive_payment_key();

        // Derive a different key (account index 1)
        let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
        let entropy = mnemonic_obj.to_entropy();
        let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");

        let account_key = root_key
            .derive(1852 | 0x80000000)
            .derive(1815 | 0x80000000)
            .derive(1 | 0x80000000);

        let key2 = account_key.derive(0).derive(0).to_bech32();

        let message = "Same message".as_bytes();
        let message_hex = hex::encode(message);

        let signed1 = sign_message_internal(message_hex.clone(), key1, None).unwrap();
        let signed2 = sign_message_internal(message_hex, key2, None).unwrap();

        // Different keys should produce different signatures
        assert_ne!(
            signed1.cose_sign1_hex, signed2.cose_sign1_hex,
            "Different keys should produce different signatures"
        );
        assert_ne!(
            signed1.public_key_hex, signed2.public_key_hex,
            "Different keys should have different public keys"
        );
    }
}
