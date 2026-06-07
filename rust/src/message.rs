//! CIP-8 message signing and verification.
//!
//! Provides functions to sign arbitrary messages with payment or stake keys
//! and verify signatures.
//!
//! # ⚠️ Legacy — prefer [`crate::cip30`] for new code
//!
//! These functions emit a **custom, non-COSE** CBOR map
//! (`{public_key, signature, message}`), **not** a spec `COSE_Sign1` array, so
//! they are *not interoperable* with browser wallets (Lace/Eternl/Nami). For
//! CIP-30 `signData`/CIP-8 interop use [`crate::cip30::cip30_sign_data`] /
//! [`crate::cip30::cip30_verify_data`], which are built on Emurgo's reference
//! `cardano-message-signing` library.
//!
//! # Identity binding (security)
//!
//! A bare "this is a valid Ed25519 signature by *some* key" check is a forgery
//! oracle: an attacker can keep a victim's `address` while supplying their own
//! `public_key` + a signature they made with their own key. To prevent this,
//! [`verify_message`] **cryptographically binds** the signing public key to the
//! claimed address — the Blake2b-224 hash of `public_key_hex` must equal a
//! credential inside the address before the signature is trusted. See
//! [`verify_message_internal`].

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

/// ⚠️ DEPRECATED / legacy — prefer `cip30_sign_data`.
///
/// Custom, non-COSE structure that predates the CIP-30 path. NOT interoperable
/// with browser wallets, and its `address` field is **not** cryptographically
/// bound to the signature (see [`verify_message`]). Use `cip30_sign_data` /
/// `cip30_verify_data` for any authentication or wallet interop. Retained only
/// for backward compatibility.
///
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

/// ⚠️ DEPRECATED / legacy — prefer `cip30_verify_data`.
///
/// Verify a legacy (non-COSE) signed message.
///
/// Verifies that the signature is a valid Ed25519 signature over the message, and
/// checks that the supplied public key hashes into the supplied `address`.
///
/// SECURITY: unlike `cip30_verify_data`, the `address` and `public_key` here are
/// caller-supplied fields that sit **outside** the signature, so this only proves
/// "the holder of `public_key` signed `message`" — it does NOT cryptographically
/// bind the *address* to the signing act (the COSE path binds the address inside
/// the signed protected header). Do not use this for address-authenticated login;
/// use `cip30_verify_data`.
///
/// # Arguments
/// * `signed_message` - The [SignedMessage] to verify
/// * `expected_address` - Optional: if provided, must equal `signed_message.address`,
///   and the signing key must hash to a credential in that address.
///
/// # Returns
/// `true` if the signature is valid (and identity-bound, when an address is
/// present); `false` otherwise.
///
/// # Errors
/// * `InvalidCbor` - If the COSE Sign1 structure is malformed
/// * `InvalidAddress` - If a claimed/expected address cannot be parsed
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
    // Check address match if required (the caller's expected address must equal
    // the one the signer claimed).
    if let Some(expected) = expected_address.as_ref() {
        if signed_message.address.as_ref() != Some(expected) {
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

    // ── Identity binding ──────────────────────────────────────────────────────
    // If the signer claimed an address (or the caller pinned one), the signing
    // public key MUST hash to a credential inside that address. Without this a
    // valid signature by *any* key would satisfy a claim about *someone else's*
    // address — the forgery oracle this fix closes.
    //
    // The address to bind against is the one the signer embedded. (`expected`
    // has already been required to equal it above, so checking either is
    // equivalent.) A bech32-prefixed value is treated as a real Cardano address
    // and parsed; anything else is rejected as an invalid address rather than
    // silently skipping the binding.
    if let Some(address) = signed_message.address.as_ref() {
        if !public_key_owns_address(&public_key, address)? {
            return Ok(false);
        }
    }

    // Verify the signature
    let is_valid = public_key.verify(&hash, &signature);

    Ok(is_valid)
}

/// Return `true` if the Blake2b-224 hash of `public_key` matches a credential
/// (payment or stake) inside the bech32 `address`.
///
/// Used to bind a signing key to a claimed address so that a valid signature
/// cannot be replayed as if it came from an address the key does not control.
///
/// # Errors
/// * `InvalidAddress` - If `address` is not a parseable bech32 Cardano address.
fn public_key_owns_address(
    public_key: &csl::PublicKey,
    address: &str,
) -> Result<bool, CardanoError> {
    let addr = csl::Address::from_bech32(address)
        .map_err(|_| CardanoError::InvalidAddress(format!("Invalid bech32 address: {address}")))?;
    let pk_hash = public_key.hash().to_bytes();
    Ok(crate::cip30::address_credential_hashes(&addr)
        .iter()
        .any(|cred| cred == &pk_hash))
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

    /// A real testnet base address controlled by the given account's payment key.
    fn account_base_address(account_index: u32) -> String {
        let k = crate::wallet::derive_keys_from_mnemonic_internal(
            TEST_MNEMONIC,
            "",
            account_index,
            true,
        )
        .unwrap();
        crate::cip30::compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap()
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
            sign_message_internal(message_hex, payment_key, Some(account_base_address(0))).unwrap();

        // Verify pinned to a different address should fail (string mismatch).
        let is_valid = verify_message_internal(signed, Some(account_base_address(1))).unwrap();
        assert!(!is_valid, "Signature should not verify for wrong address");
    }

    #[test]
    fn test_verify_passes_with_matching_address() {
        let payment_key = derive_payment_key();
        let message = "Test message".as_bytes();
        let message_hex = hex::encode(message);
        let expected_addr = account_base_address(0);

        let signed =
            sign_message_internal(message_hex, payment_key, Some(expected_addr.clone())).unwrap();

        // Verify with same address (and a key that owns it) should succeed.
        let is_valid = verify_message_internal(signed, Some(expected_addr)).unwrap();
        assert!(is_valid, "Signature should verify for matching address");
    }

    #[test]
    fn test_verify_rejects_forged_identity() {
        // The forgery oracle this hardening closes: the attacker signs with
        // their OWN key but claims the victim's address. The signature is a
        // genuine Ed25519 signature, yet it must NOT verify as the victim.
        let attacker_key = {
            // Account 1 payment key — a key the victim (account 0) does not own.
            let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).expect("Valid mnemonic");
            let entropy = mnemonic_obj.to_entropy();
            let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");
            let account_key = root_key
                .derive(1852 | 0x80000000)
                .derive(1815 | 0x80000000)
                .derive(1 | 0x80000000);
            account_key.derive(0).derive(0).to_bech32()
        };
        let victim_addr = account_base_address(0);
        let message_hex = hex::encode("I authorize this".as_bytes());

        // Attacker signs but stamps the victim's address as context.
        let forged =
            sign_message_internal(message_hex, attacker_key, Some(victim_addr.clone())).unwrap();

        // Pinning to the victim address must reject — the attacker key does not
        // hash to the victim address's credential.
        let pinned = verify_message_internal(forged.clone(), Some(victim_addr)).unwrap();
        assert!(
            !pinned,
            "forged identity must be rejected when address pinned"
        );

        // Even without an explicit expected_address, the embedded claimed
        // address binds: the attacker's key does not own it → reject.
        let unpinned = verify_message_internal(forged, None).unwrap();
        assert!(
            !unpinned,
            "forged identity must be rejected via the embedded address binding"
        );
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
