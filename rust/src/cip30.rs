//! CIP-30 dApp connector primitives (Phase 4.3).
//!
//! CIP-30 is the Cardano dApp–wallet bridge. On mobile, the SDK *is* the wallet,
//! so this module provides the serialization and signing primitives a CIP-30
//! wallet API needs, all spec-compliant:
//!
//! - [`compute_base_address`] — derive a `addr…`/`addr_test…` base address from
//!   payment + stake key hashes (used by `getChangeAddress` / `getUsedAddresses`).
//! - [`address_to_hex`] — CIP-30 returns addresses as hex of their raw bytes.
//! - [`value_to_cbor_hex`] — CIP-30 `getBalance` returns a CBOR-encoded `Value`.
//! - [`utxo_to_cbor_hex`] — CIP-30 `getUtxos` returns CBOR `TransactionUnspentOutput`s.
//! - [`sum_values`] — fold a UTxO set into a single `Value` (for `getBalance`).
//! - [`cip30_sign_tx`] — sign a full transaction, returning just the witness set
//!   (CIP-30 `signTx` returns `cbor<transaction_witness_set>`).
//! - [`cip30_sign_data`] / [`cip30_verify_data`] — CIP-8 `COSE_Sign1` + `COSE_Key`
//!   data signatures (CIP-30 `signData`).
//!
//! The COSE structures follow RFC 9052 / CIP-8: the signature is a pure Ed25519
//! signature over the canonical `Sig_structure` CBOR, not a pre-hash.

use std::collections::BTreeMap;

use blake2::{
    digest::{consts::U32, Digest},
    Blake2b,
};
use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;
use serde_cbor::Value as CborValue;

use crate::error::CardanoError;
use crate::tx::{
    hex_to_bytes, input_to_csl, map_csl_error, map_deserialize_error, value_to_csl, NativeAsset,
    TxInput, Value,
};

/// A CIP-30 `DataSignature`: a COSE_Sign1 signature plus its COSE_Key.
///
/// Both fields are hex-encoded CBOR, matching the shape a CIP-30 `signData`
/// call returns to a dApp (`{ signature, key }`).
#[derive(Clone, Debug)]
pub struct DataSignature {
    /// Hex-encoded `COSE_Sign1` structure (`[protected, unprotected, payload, sig]`).
    pub signature: String,
    /// Hex-encoded `COSE_Key` containing the Ed25519 public key.
    pub key: String,
}

// ── Address helpers ───────────────────────────────────────────────────────────

/// Compute a bech32 base address from payment and stake key hashes.
///
/// A base address binds a payment credential and a staking credential, e.g.
/// `addr_test1q…` (testnet) or `addr1q…` (mainnet). This is the address a
/// CIP-30 wallet returns from `getChangeAddress` / `getUsedAddresses`.
///
/// # Arguments
/// - `payment_key_hash_hex`: 56-char hex Blake2b-224 payment key hash
/// - `stake_key_hash_hex`: 56-char hex Blake2b-224 stake key hash
/// - `network_id`: 0 = testnet, 1 = mainnet
#[frb(sync)]
pub fn compute_base_address(
    payment_key_hash_hex: String,
    stake_key_hash_hex: String,
    network_id: u8,
) -> Result<String, CardanoError> {
    let pay_hash = csl::Ed25519KeyHash::from_bytes(hex_to_bytes(&payment_key_hash_hex)?)
        .map_err(map_deserialize_error)?;
    let stake_hash = csl::Ed25519KeyHash::from_bytes(hex_to_bytes(&stake_key_hash_hex)?)
        .map_err(map_deserialize_error)?;

    let pay_cred = csl::Credential::from_keyhash(&pay_hash);
    let stake_cred = csl::Credential::from_keyhash(&stake_hash);

    let base = csl::BaseAddress::new(network_id, &pay_cred, &stake_cred);
    base.to_address().to_bech32(None).map_err(map_csl_error)
}

/// Convert a bech32 address to hex of its raw bytes (CIP-30 address encoding).
#[frb(sync)]
pub fn address_to_hex(address_bech32: String) -> Result<String, CardanoError> {
    let addr = csl::Address::from_bech32(&address_bech32)
        .map_err(|_| CardanoError::InvalidAddress("Invalid bech32 address".to_string()))?;
    Ok(hex::encode(addr.to_bytes()))
}

// ── Value / UTxO serialization ────────────────────────────────────────────────

/// Serialize a [`Value`] to CBOR hex (CIP-30 `getBalance` encoding).
#[frb(sync)]
pub fn value_to_cbor_hex(value: Value) -> Result<String, CardanoError> {
    let csl_value = value_to_csl(&value)?;
    Ok(hex::encode(csl_value.to_bytes()))
}

/// Serialize a [`TxInput`] to a CBOR `TransactionUnspentOutput` hex string
/// (CIP-30 `getUtxos` encoding: `[input, output]`).
#[frb(sync)]
pub fn utxo_to_cbor_hex(input: TxInput) -> Result<String, CardanoError> {
    let (tx_input, value) = input_to_csl(&input)?;
    let address = csl::Address::from_bech32(&input.address)
        .map_err(|_| CardanoError::InvalidAddress("Invalid UTxO address bech32".to_string()))?;
    let tx_output = csl::TransactionOutput::new(&address, &value);
    let utxo = csl::TransactionUnspentOutput::new(&tx_input, &tx_output);
    Ok(hex::encode(utxo.to_bytes()))
}

/// Convert a CSL `Value` back into this crate's [`Value`].
fn csl_value_to_value(v: &csl::Value) -> Value {
    let coin: u64 = v.coin().to_str().parse().unwrap_or(0);
    let mut assets = Vec::new();

    if let Some(ma) = v.multiasset() {
        let policies = ma.keys();
        for i in 0..policies.len() {
            let policy = policies.get(i);
            if let Some(asset_map) = ma.get(&policy) {
                let names = asset_map.keys();
                for j in 0..names.len() {
                    let name = names.get(j);
                    if let Some(qty) = asset_map.get(&name) {
                        assets.push(NativeAsset {
                            policy_id: hex::encode(policy.to_bytes()),
                            asset_name: hex::encode(name.name()),
                            quantity: qty.to_str().parse().unwrap_or(0),
                        });
                    }
                }
            }
        }
    }

    Value { coin, assets }
}

/// Sum a list of [`Value`]s into a single [`Value`] (coin + native assets).
///
/// Used to compute a wallet's total balance from its UTxO set. Multi-asset
/// addition is delegated to CSL for correctness.
#[frb(sync)]
pub fn sum_values(values: Vec<Value>) -> Result<Value, CardanoError> {
    let mut acc = csl::Value::new(&csl::BigNum::from(0u64));
    for v in &values {
        let cv = value_to_csl(v)?;
        acc = acc.checked_add(&cv).map_err(map_csl_error)?;
    }
    Ok(csl_value_to_value(&acc))
}

// ── Transaction signing (witness set only) ────────────────────────────────────

/// Compute Blake2b-256 hash of data.
fn blake2b_256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Blake2b::<U32>::new();
    hasher.update(data);
    let mut out = [0u8; 32];
    out.copy_from_slice(hasher.finalize().as_slice());
    out
}

/// Sign a full transaction and return only the vkey witness set (CBOR hex).
///
/// CIP-30 `signTx` hands the wallet a complete transaction and expects back a
/// `cbor<transaction_witness_set>` containing the wallet's witnesses, which the
/// dApp then merges with the body before submission.
///
/// Only the witnesses for the supplied keys are produced; any witnesses already
/// present in the transaction are not echoed back.
///
/// # Arguments
/// - `tx_cbor_hex`: full transaction (body + witnesses + aux) as CBOR hex
/// - `signing_keys_bech32`: bech32 xprv keys to sign with (payment, stake, …)
#[frb(sync)]
pub fn cip30_sign_tx(
    tx_cbor_hex: String,
    signing_keys_bech32: Vec<String>,
) -> Result<String, CardanoError> {
    // Validate keys up front.
    for key in &signing_keys_bech32 {
        csl::Bip32PrivateKey::from_bech32(key)
            .map_err(|_| CardanoError::InvalidKey("Invalid signing key format".to_string()))?;
    }

    let tx_bytes = hex_to_bytes(&tx_cbor_hex)?;
    let tx = csl::Transaction::from_bytes(tx_bytes)
        .map_err(|_| CardanoError::InvalidCbor("Invalid transaction CBOR".to_string()))?;

    let body = tx.body();
    let hash = blake2b_256(&body.to_bytes());

    let mut witnesses = csl::Vkeywitnesses::new();
    for key in signing_keys_bech32 {
        let bip32 = csl::Bip32PrivateKey::from_bech32(&key)
            .map_err(|_| CardanoError::InvalidKey("Invalid signing key format".to_string()))?;
        let priv_key = bip32.to_raw_key();
        let public_key = priv_key.to_public();
        let signature = priv_key.sign(&hash);
        witnesses.add(&csl::Vkeywitness::new(
            &csl::Vkey::new(&public_key),
            &signature,
        ));
    }

    let mut witness_set = csl::TransactionWitnessSet::new();
    witness_set.set_vkeys(&witnesses);
    Ok(hex::encode(witness_set.to_bytes()))
}

// ── CIP-8 / COSE data signing ─────────────────────────────────────────────────

/// Build the COSE protected-header bstr: `{ 1: -8 (EdDSA), "address": <bytes> }`.
fn protected_header(address_bytes: &[u8]) -> Vec<u8> {
    let mut map = BTreeMap::new();
    map.insert(CborValue::Integer(1), CborValue::Integer(-8)); // alg: EdDSA
    map.insert(
        CborValue::Text("address".to_string()),
        CborValue::Bytes(address_bytes.to_vec()),
    );
    serde_cbor::to_vec(&CborValue::Map(map)).expect("CBOR map encodes")
}

/// Build the canonical `Sig_structure` bytes that are actually signed/verified.
fn sig_structure(protected: &[u8], payload: &[u8]) -> Vec<u8> {
    let arr = CborValue::Array(vec![
        CborValue::Text("Signature1".to_string()),
        CborValue::Bytes(protected.to_vec()),
        CborValue::Bytes(Vec::new()), // external_aad
        CborValue::Bytes(payload.to_vec()),
    ]);
    serde_cbor::to_vec(&arr).expect("CBOR array encodes")
}

/// Build a `COSE_Key` for an Ed25519 public key.
fn cose_key(public_key_bytes: &[u8]) -> Vec<u8> {
    let mut map = BTreeMap::new();
    map.insert(CborValue::Integer(1), CborValue::Integer(1)); // kty: OKP
    map.insert(CborValue::Integer(3), CborValue::Integer(-8)); // alg: EdDSA
    map.insert(CborValue::Integer(-1), CborValue::Integer(6)); // crv: Ed25519
    map.insert(
        CborValue::Integer(-2),
        CborValue::Bytes(public_key_bytes.to_vec()),
    ); // x
    serde_cbor::to_vec(&CborValue::Map(map)).expect("CBOR map encodes")
}

/// Sign arbitrary data per CIP-30 `signData` (CIP-8 `COSE_Sign1`).
///
/// # Arguments
/// - `address_hex`: hex of the raw signer address bytes (see [`address_to_hex`])
/// - `payload_hex`: hex of the message bytes to sign
/// - `signing_key_bech32`: bech32 xprv signing key
///
/// # Returns
/// A [`DataSignature`] with the `COSE_Sign1` and `COSE_Key` as hex CBOR.
#[frb(sync)]
pub fn cip30_sign_data(
    address_hex: String,
    payload_hex: String,
    signing_key_bech32: String,
) -> Result<DataSignature, CardanoError> {
    let address_bytes = hex_to_bytes(&address_hex)?;
    let payload = hex_to_bytes(&payload_hex)?;

    let bip32 = csl::Bip32PrivateKey::from_bech32(&signing_key_bech32)
        .map_err(|_| CardanoError::InvalidKey("Invalid signing key format".to_string()))?;
    let priv_key = bip32.to_raw_key();
    let public_key = priv_key.to_public();

    let protected = protected_header(&address_bytes);
    let to_sign = sig_structure(&protected, &payload);
    let signature = priv_key.sign(&to_sign);

    // COSE_Sign1 = [ protected: bstr, unprotected: map, payload: bstr, sig: bstr ]
    let mut unprotected = BTreeMap::new();
    unprotected.insert(
        CborValue::Text("hashed".to_string()),
        CborValue::Bool(false),
    );
    let cose_sign1 = CborValue::Array(vec![
        CborValue::Bytes(protected),
        CborValue::Map(unprotected),
        CborValue::Bytes(payload),
        CborValue::Bytes(signature.to_bytes()),
    ]);
    let cose_sign1_bytes = serde_cbor::to_vec(&cose_sign1)
        .map_err(|e| CardanoError::SerializationError(format!("COSE_Sign1 encode: {}", e)))?;

    Ok(DataSignature {
        signature: hex::encode(cose_sign1_bytes),
        key: hex::encode(cose_key(&public_key.as_bytes())),
    })
}

/// Verify a CIP-30 `DataSignature`.
///
/// Reconstructs the `Sig_structure` from the embedded protected header and
/// payload and checks the Ed25519 signature against the `COSE_Key`'s public key.
///
/// # Arguments
/// - `data_signature`: the [`DataSignature`] to verify
/// - `expected_payload_hex`: if provided, the embedded payload must match it
///
/// # Returns
/// `true` if the signature is valid (and the payload matches, if given).
#[frb(sync)]
pub fn cip30_verify_data(
    data_signature: DataSignature,
    expected_payload_hex: Option<String>,
) -> Result<bool, CardanoError> {
    let cose_sign1_bytes = hex_to_bytes(&data_signature.signature)?;
    let cose: CborValue = serde_cbor::from_slice(&cose_sign1_bytes)
        .map_err(|e| CardanoError::InvalidCbor(format!("COSE_Sign1 decode: {}", e)))?;

    let arr = match cose {
        CborValue::Array(a) if a.len() == 4 => a,
        _ => {
            return Err(CardanoError::InvalidCbor(
                "COSE_Sign1 must be a 4-element array".to_string(),
            ))
        }
    };

    let protected = match &arr[0] {
        CborValue::Bytes(b) => b.clone(),
        _ => return Err(CardanoError::InvalidCbor("protected must be bstr".to_string())),
    };
    let payload = match &arr[2] {
        CborValue::Bytes(b) => b.clone(),
        CborValue::Null => Vec::new(),
        _ => return Err(CardanoError::InvalidCbor("payload must be bstr".to_string())),
    };
    let signature_bytes = match &arr[3] {
        CborValue::Bytes(b) => b.clone(),
        _ => return Err(CardanoError::InvalidCbor("signature must be bstr".to_string())),
    };

    if let Some(expected) = expected_payload_hex {
        if hex_to_bytes(&expected)? != payload {
            return Ok(false);
        }
    }

    // Extract the public key (label -2) from the COSE_Key.
    let key_bytes = hex_to_bytes(&data_signature.key)?;
    let key_cbor: CborValue = serde_cbor::from_slice(&key_bytes)
        .map_err(|e| CardanoError::InvalidCbor(format!("COSE_Key decode: {}", e)))?;
    let public_key_bytes = match key_cbor {
        CborValue::Map(m) => match m.get(&CborValue::Integer(-2)) {
            Some(CborValue::Bytes(b)) => b.clone(),
            _ => {
                return Err(CardanoError::InvalidKey(
                    "COSE_Key missing Ed25519 public key (-2)".to_string(),
                ))
            }
        },
        _ => return Err(CardanoError::InvalidCbor("COSE_Key must be a map".to_string())),
    };

    let public_key = csl::PublicKey::from_bytes(&public_key_bytes)
        .map_err(|_| CardanoError::InvalidKey("Invalid public key bytes".to_string()))?;
    let signature = csl::Ed25519Signature::from_bytes(signature_bytes)
        .map_err(|_| CardanoError::InvalidCbor("Invalid signature bytes".to_string()))?;

    let to_verify = sig_structure(&protected, &payload);
    Ok(public_key.verify(&to_verify, &signature))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::derive_keys_from_mnemonic_internal;

    const TEST_MNEMONIC: &str =
        "test walk nut penalty hip pave soap entry language right filter choice";

    fn keys() -> crate::wallet::KeyDerivationResult {
        derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, true).unwrap()
    }

    #[test]
    fn test_compute_base_address_testnet() {
        let k = keys();
        let addr = compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap();
        assert!(addr.starts_with("addr_test1"), "got {addr}");
        assert!(csl::Address::from_bech32(&addr).is_ok());
    }

    #[test]
    fn test_compute_base_address_mainnet() {
        let k = keys();
        let addr = compute_base_address(k.payment_key_hash, k.stake_key_hash, 1).unwrap();
        assert!(addr.starts_with("addr1"), "got {addr}");
    }

    #[test]
    fn test_address_to_hex_roundtrips_via_csl() {
        let k = keys();
        let addr = compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap();
        let hexstr = address_to_hex(addr.clone()).unwrap();
        let bytes = hex::decode(&hexstr).unwrap();
        let back = csl::Address::from_bytes(bytes).unwrap();
        assert_eq!(back.to_bech32(None).unwrap(), addr);
    }

    #[test]
    fn test_value_to_cbor_hex_pure_ada() {
        let v = Value {
            coin: 2_000_000,
            assets: vec![],
        };
        let hexstr = value_to_cbor_hex(v).unwrap();
        assert!(!hexstr.is_empty());
        // Round-trip through CSL.
        let bytes = hex::decode(&hexstr).unwrap();
        let cv = csl::Value::from_bytes(bytes).unwrap();
        assert_eq!(cv.coin().to_str(), "2000000");
    }

    #[test]
    fn test_utxo_to_cbor_hex() {
        let input = TxInput {
            tx_hash: "0000000000000000000000000000000000000000000000000000000000000000"
                .to_string(),
            output_index: 0,
            address: "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz"
                .to_string(),
            value: Value {
                coin: 5_000_000,
                assets: vec![],
            },
        };
        let hexstr = utxo_to_cbor_hex(input).unwrap();
        let bytes = hex::decode(&hexstr).unwrap();
        let utxo = csl::TransactionUnspentOutput::from_bytes(bytes).unwrap();
        assert_eq!(utxo.output().amount().coin().to_str(), "5000000");
    }

    #[test]
    fn test_sum_values_pure_ada() {
        let vals = vec![
            Value {
                coin: 1_000_000,
                assets: vec![],
            },
            Value {
                coin: 2_500_000,
                assets: vec![],
            },
        ];
        let total = sum_values(vals).unwrap();
        assert_eq!(total.coin, 3_500_000);
        assert!(total.assets.is_empty());
    }

    #[test]
    fn test_sum_values_with_assets() {
        let policy = "a0028f350aaabe0545fdcb56b039bfb08e4bb4d8c4d7c3c7d481c235";
        let name = hex::encode("TOKEN");
        let vals = vec![
            Value {
                coin: 1_000_000,
                assets: vec![NativeAsset {
                    policy_id: policy.to_string(),
                    asset_name: name.clone(),
                    quantity: 10,
                }],
            },
            Value {
                coin: 2_000_000,
                assets: vec![NativeAsset {
                    policy_id: policy.to_string(),
                    asset_name: name.clone(),
                    quantity: 5,
                }],
            },
        ];
        let total = sum_values(vals).unwrap();
        assert_eq!(total.coin, 3_000_000);
        assert_eq!(total.assets.len(), 1);
        assert_eq!(total.assets[0].quantity, 15);
        assert_eq!(total.assets[0].policy_id, policy);
    }

    #[test]
    fn test_sign_and_verify_data_roundtrip() {
        let k = keys();
        let addr = compute_base_address(
            k.payment_key_hash.clone(),
            k.stake_key_hash.clone(),
            0,
        )
        .unwrap();
        let address_hex = address_to_hex(addr).unwrap();
        let payload = hex::encode("Login to dApp at 2026-06-02");

        let sig = cip30_sign_data(
            address_hex,
            payload.clone(),
            k.payment_signing_key.clone(),
        )
        .unwrap();
        assert!(!sig.signature.is_empty());
        assert!(!sig.key.is_empty());

        let ok = cip30_verify_data(sig.clone(), Some(payload)).unwrap();
        assert!(ok, "data signature should verify");

        // No expected payload also verifies.
        let ok2 = cip30_verify_data(sig, None).unwrap();
        assert!(ok2);
    }

    #[test]
    fn test_verify_data_fails_on_wrong_payload() {
        let k = keys();
        let address_hex = address_to_hex(
            compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap(),
        )
        .unwrap();
        let payload = hex::encode("original");
        let sig = cip30_sign_data(address_hex, payload, k.payment_signing_key).unwrap();

        let ok = cip30_verify_data(sig, Some(hex::encode("tampered"))).unwrap();
        assert!(!ok, "verification must fail for a different payload");
    }

    #[test]
    fn test_verify_data_fails_on_tampered_signature() {
        let k = keys();
        let address_hex = address_to_hex(
            compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap(),
        )
        .unwrap();
        let payload = hex::encode("msg");
        let mut sig = cip30_sign_data(address_hex, payload.clone(), k.payment_signing_key).unwrap();

        // Flip the last byte of the COSE_Sign1.
        let mut bytes = hex::decode(&sig.signature).unwrap();
        let last = bytes.len() - 1;
        bytes[last] ^= 0xff;
        sig.signature = hex::encode(bytes);

        let ok = cip30_verify_data(sig, Some(payload)).unwrap();
        assert!(!ok, "tampered signature must not verify");
    }

    #[test]
    fn test_sign_data_invalid_key() {
        let address_hex = "00".to_string();
        let payload = hex::encode("x");
        let res = cip30_sign_data(address_hex, payload, "not_a_key".to_string());
        assert!(matches!(res, Err(CardanoError::InvalidKey(_))));
    }

    #[test]
    fn test_cip30_sign_tx_invalid_key() {
        let res = cip30_sign_tx("00".to_string(), vec!["bad".to_string()]);
        assert!(matches!(res, Err(CardanoError::InvalidKey(_))));
    }

    #[test]
    fn test_cip30_sign_tx_invalid_cbor() {
        let k = keys();
        let res = cip30_sign_tx("deadbeef".to_string(), vec![k.payment_signing_key]);
        assert!(matches!(res, Err(CardanoError::InvalidCbor(_))));
    }
}
