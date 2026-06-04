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

use blake2::{
    digest::{consts::U32, Digest},
    Blake2b,
};
use cardano_message_signing as cms;
use cardano_serialization_lib as csl;
use cms::builders::{AlgorithmId, COSESign1Builder, EdDSA25519Key};
use cms::cbor::CBORValue;
use cms::utils::{FromBytes, Int, ToBytes};
use cms::{COSEKey, COSESign1, HeaderMap, Headers, Label, ProtectedHeaderMap};
use flutter_rust_bridge::frb;

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

/// Assemble a full transaction CBOR from a body, a witness set, and optional
/// auxiliary data.
///
/// This is the dApp-side counterpart to [`cip30_sign_tx`]: the dApp builds the
/// body, the wallet returns a `transaction_witness_set`, and this combines them
/// into a submittable transaction. To build an *unsigned* transaction to hand to
/// `signTx`, pass an empty witness set (`"a0"`).
///
/// # Arguments
/// - `tx_body_cbor_hex`: transaction body CBOR hex
/// - `witness_set_cbor_hex`: `transaction_witness_set` CBOR hex
/// - `aux_data_cbor_hex`: optional auxiliary-data CBOR hex
#[frb(sync)]
pub fn cip30_assemble_tx(
    tx_body_cbor_hex: String,
    witness_set_cbor_hex: String,
    aux_data_cbor_hex: Option<String>,
) -> Result<String, CardanoError> {
    let body = csl::TransactionBody::from_bytes(hex_to_bytes(&tx_body_cbor_hex)?)
        .map_err(|_| CardanoError::InvalidCbor("Invalid tx body CBOR".to_string()))?;
    let witness_set = csl::TransactionWitnessSet::from_bytes(hex_to_bytes(&witness_set_cbor_hex)?)
        .map_err(|_| CardanoError::InvalidCbor("Invalid witness set CBOR".to_string()))?;
    let aux = match aux_data_cbor_hex {
        Some(h) => Some(
            csl::AuxiliaryData::from_bytes(hex_to_bytes(&h)?)
                .map_err(|_| CardanoError::InvalidCbor("Invalid aux data CBOR".to_string()))?,
        ),
        None => None,
    };
    let tx = csl::Transaction::new(&body, &witness_set, aux);
    Ok(hex::encode(tx.to_bytes()))
}

// ── CIP-8 / COSE data signing ─────────────────────────────────────────────────
//
// Built on Emurgo's `cardano-message-signing` (the reference COSE/CIP-8 library
// that Lace/Eternl/Nami use via its WASM build), so the `COSE_Sign1` and
// `COSE_Key` bytes are interop-correct by construction.

/// Map a `cardano-message-signing` deserialization error to [`CardanoError`].
fn map_cms_err<E: std::fmt::Debug>(e: E) -> CardanoError {
    CardanoError::InvalidCbor(format!("COSE decode error: {:?}", e))
}

/// Collect the key-hash credentials (payment and/or stake) embedded in an
/// address. Returns the raw 28-byte Blake2b-224 hashes.
///
/// Used to bind a signing public key to a claimed address: the signer's key
/// hash must appear here for the signature to be attributable to that address.
/// Script credentials are intentionally excluded — a vkey signature can only be
/// owned by a key credential.
pub(crate) fn address_credential_hashes(addr: &csl::Address) -> Vec<Vec<u8>> {
    let mut creds = Vec::new();
    let mut push = |cred: csl::Credential| {
        if let Some(kh) = cred.to_keyhash() {
            creds.push(kh.to_bytes());
        }
    };
    if let Some(base) = csl::BaseAddress::from_address(addr) {
        push(base.payment_cred());
        push(base.stake_cred());
    } else if let Some(reward) = csl::RewardAddress::from_address(addr) {
        push(reward.payment_cred());
    } else if let Some(ent) = csl::EnterpriseAddress::from_address(addr) {
        push(ent.payment_cred());
    } else if let Some(ptr) = csl::PointerAddress::from_address(addr) {
        push(ptr.payment_cred());
    }
    creds
}

/// CBOR label for the COSE `address` protected header (CIP-30 / CIP-8).
fn address_label() -> Label {
    Label::new_text("address".to_string())
}

/// Sign arbitrary data per CIP-30 `signData` (CIP-8 `COSE_Sign1`).
///
/// Produces a `COSE_Sign1` whose protected headers carry `alg = EdDSA` and the
/// signer `address`, with `hashed = false`, plus a matching `COSE_Key` — the
/// exact shape produced by browser wallets, since both are built with Emurgo's
/// `cardano-message-signing` reference library.
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

    // Protected headers: alg = EdDSA, "address" = <raw address bytes>.
    let mut protected = HeaderMap::new();
    protected.set_algorithm_id(&Label::from_algorithm_id(AlgorithmId::EdDSA));
    protected
        .set_header(&address_label(), &CBORValue::new_bytes(address_bytes))
        .map_err(|e| CardanoError::SerializationError(format!("set address header: {:?}", e)))?;
    let protected_serialized = ProtectedHeaderMap::new(&protected);

    // Unprotected: { "hashed": false } is conveyed by signing the raw payload.
    let unprotected = HeaderMap::new();
    let headers = Headers::new(&protected_serialized, &unprotected);

    // Build the Sig_structure, sign its bytes with Ed25519, attach the signature.
    let builder = COSESign1Builder::new(&headers, payload, false);
    let to_sign = builder.make_data_to_sign().to_bytes();
    let signature = priv_key.sign(&to_sign).to_bytes();
    let cose_sign1 = builder.build(signature);

    // COSE_Key for the Ed25519 public key (kty=OKP, alg=EdDSA, crv=Ed25519, x=pk).
    let mut key = EdDSA25519Key::new(public_key.as_bytes());
    key.is_for_verifying();
    let cose_key = key.build();

    Ok(DataSignature {
        signature: hex::encode(cose_sign1.to_bytes()),
        key: hex::encode(cose_key.to_bytes()),
    })
}

/// Verify a CIP-30 `DataSignature`.
///
/// Parses the `COSE_Sign1` with the reference library, reconstructs the
/// `Sig_structure`, and verifies the Ed25519 signature against the public key
/// embedded in the `COSE_Key`.
///
/// # Identity binding (security)
///
/// A bare signature check answers only "is this a valid signature by the key in
/// this `COSE_Key`?" — and the caller supplies that `COSE_Key`, so on its own it
/// does **not** prove the owner of the signer `address` signed anything. To
/// close that gap, this function additionally requires the `COSE_Key` public key
/// to hash to a credential inside the `address` carried in the `COSE_Sign1`
/// protected header (always, when that header is present). Pass
/// `expected_address_hex` to further pin verification to a specific address.
///
/// # Arguments
/// - `data_signature`: the [`DataSignature`] to verify
/// - `expected_payload_hex`: if provided, the embedded payload must match it
/// - `expected_address_hex`: if provided, the protected-header `address` must
///   equal these raw address bytes (hex). The key→address binding is enforced
///   regardless.
///
/// # Returns
/// `true` if the signature is valid, the signing key owns the header address,
/// and the payload/address match any expectations supplied.
#[frb(sync)]
pub fn cip30_verify_data(
    data_signature: DataSignature,
    expected_payload_hex: Option<String>,
    expected_address_hex: Option<String>,
) -> Result<bool, CardanoError> {
    let cose_sign1 =
        COSESign1::from_bytes(hex_to_bytes(&data_signature.signature)?).map_err(map_cms_err)?;

    let payload = cose_sign1.payload().unwrap_or_default();
    if let Some(expected) = expected_payload_hex {
        if hex_to_bytes(&expected)? != payload {
            return Ok(false);
        }
    }

    let to_verify = cose_sign1
        .signed_data(None, None)
        .map_err(|e| CardanoError::InvalidCbor(format!("rebuild Sig_structure: {:?}", e)))?
        .to_bytes();
    let signature_bytes = cose_sign1.signature();

    // Extract the public key (COSE_Key label -2 = OKP x-coordinate).
    let cose_key = COSEKey::from_bytes(hex_to_bytes(&data_signature.key)?).map_err(map_cms_err)?;
    let x_label = Label::new_int(&Int::new_i32(-2));
    let public_key_bytes = cose_key
        .header(&x_label)
        .and_then(|v| v.as_bytes())
        .ok_or_else(|| {
            CardanoError::InvalidKey("COSE_Key missing Ed25519 public key (-2)".to_string())
        })?;

    let public_key = csl::PublicKey::from_bytes(&public_key_bytes)
        .map_err(|_| CardanoError::InvalidKey("Invalid public key bytes".to_string()))?;
    let signature = csl::Ed25519Signature::from_bytes(signature_bytes)
        .map_err(|_| CardanoError::InvalidCbor("Invalid signature bytes".to_string()))?;

    // ── Identity binding ──────────────────────────────────────────────────────
    // Read the signer address from the protected header. CIP-30 `signData`
    // always sets it; if present we require the COSE_Key public key to hash to
    // one of its credentials, so a valid signature cannot be passed off as
    // coming from an address the key does not control.
    let header_address_bytes = cose_sign1
        .headers()
        .protected()
        .deserialized_headers()
        .header(&address_label())
        .and_then(|v| v.as_bytes());

    if let Some(addr_bytes) = header_address_bytes {
        // Optionally pin to a specific expected address.
        if let Some(expected_hex) = expected_address_hex.as_ref() {
            if hex_to_bytes(expected_hex)? != addr_bytes {
                return Ok(false);
            }
        }

        let addr = csl::Address::from_bytes(addr_bytes.clone()).map_err(|_| {
            CardanoError::InvalidAddress("Invalid header address bytes".to_string())
        })?;
        let pk_hash = public_key.hash().to_bytes();
        let owns = address_credential_hashes(&addr)
            .iter()
            .any(|cred| cred == &pk_hash);
        if !owns {
            return Ok(false);
        }
    } else if expected_address_hex.is_some() {
        // Caller demanded a specific address but the signature carries none.
        return Ok(false);
    }

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
            tx_hash: "0000000000000000000000000000000000000000000000000000000000000000".to_string(),
            output_index: 0,
            address: "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz".to_string(),
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
        let addr =
            compute_base_address(k.payment_key_hash.clone(), k.stake_key_hash.clone(), 0).unwrap();
        let address_hex = address_to_hex(addr).unwrap();
        let payload = hex::encode("Login to dApp at 2026-06-02");

        let sig =
            cip30_sign_data(address_hex, payload.clone(), k.payment_signing_key.clone()).unwrap();
        assert!(!sig.signature.is_empty());
        assert!(!sig.key.is_empty());

        let ok = cip30_verify_data(sig.clone(), Some(payload), None).unwrap();
        assert!(ok, "data signature should verify");

        // No expected payload also verifies.
        let ok2 = cip30_verify_data(sig, None, None).unwrap();
        assert!(ok2);
    }

    #[test]
    fn test_cose_sign1_is_cms_interop_shaped() {
        // Independently re-parse our signData output with the reference library
        // and assert the structure a browser wallet (Lace/Eternl) expects:
        //   COSE_Sign1 protected headers: alg = EdDSA, "address" = signer address
        //   payload preserved; COSE_Key: alg = EdDSA, x = the public key.
        let k = keys();
        let addr =
            compute_base_address(k.payment_key_hash.clone(), k.stake_key_hash.clone(), 0).unwrap();
        let address_hex = address_to_hex(addr).unwrap();
        let payload_hex = hex::encode("interop check");

        let sig = cip30_sign_data(
            address_hex.clone(),
            payload_hex.clone(),
            k.payment_signing_key,
        )
        .unwrap();

        // Parse COSE_Sign1 with CMS.
        let cose = COSESign1::from_bytes(hex::decode(&sig.signature).unwrap()).unwrap();
        let protected = cose.headers().protected().deserialized_headers();

        // alg = EdDSA
        assert_eq!(
            protected.algorithm_id(),
            Some(Label::from_algorithm_id(AlgorithmId::EdDSA))
        );
        // "address" header equals the signer address bytes
        let addr_in_header = protected
            .header(&address_label())
            .and_then(|v| v.as_bytes())
            .expect("address header present");
        assert_eq!(hex::encode(addr_in_header), address_hex);
        // payload preserved
        assert_eq!(hex::encode(cose.payload().unwrap()), payload_hex);

        // COSE_Key: alg = EdDSA, x present and 32 bytes
        let cose_key = COSEKey::from_bytes(hex::decode(&sig.key).unwrap()).unwrap();
        assert_eq!(
            cose_key.algorithm_id(),
            Some(Label::from_algorithm_id(AlgorithmId::EdDSA))
        );
        let x = cose_key
            .header(&Label::new_int(&Int::new_i32(-2)))
            .and_then(|v| v.as_bytes())
            .expect("x coordinate present");
        assert_eq!(x.len(), 32);
    }

    #[test]
    fn test_verify_data_fails_on_wrong_payload() {
        let k = keys();
        let address_hex =
            address_to_hex(compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap())
                .unwrap();
        let payload = hex::encode("original");
        let sig = cip30_sign_data(address_hex, payload, k.payment_signing_key).unwrap();

        let ok = cip30_verify_data(sig, Some(hex::encode("tampered")), None).unwrap();
        assert!(!ok, "verification must fail for a different payload");
    }

    #[test]
    fn test_verify_data_fails_on_tampered_signature() {
        let k = keys();
        let address_hex =
            address_to_hex(compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap())
                .unwrap();
        let payload = hex::encode("msg");
        let mut sig = cip30_sign_data(address_hex, payload.clone(), k.payment_signing_key).unwrap();

        // Flip the last byte of the COSE_Sign1.
        let mut bytes = hex::decode(&sig.signature).unwrap();
        let last = bytes.len() - 1;
        bytes[last] ^= 0xff;
        sig.signature = hex::encode(bytes);

        let ok = cip30_verify_data(sig, Some(payload), None).unwrap();
        assert!(!ok, "tampered signature must not verify");
    }

    fn attacker_keys() -> crate::wallet::KeyDerivationResult {
        // A different account → a different key the victim does not control.
        derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 1, true).unwrap()
    }

    #[test]
    fn test_verify_data_rejects_forged_identity() {
        // Forgery: the attacker signs with THEIR OWN key but stamps the VICTIM's
        // address into the protected header, then hands over their own COSE_Key.
        // The Ed25519 signature is genuine, so a naive "valid sig by some key"
        // check would return true. Identity binding must reject it.
        let victim = keys();
        let attacker = attacker_keys();

        let victim_addr_hex = address_to_hex(
            compute_base_address(victim.payment_key_hash, victim.stake_key_hash, 0).unwrap(),
        )
        .unwrap();
        let payload = hex::encode("Withdraw all funds");

        // Attacker produces a perfectly valid signature claiming the victim addr.
        let forged = cip30_sign_data(
            victim_addr_hex.clone(),
            payload.clone(),
            attacker.payment_signing_key,
        )
        .unwrap();

        let ok = cip30_verify_data(forged, Some(payload), None).unwrap();
        assert!(
            !ok,
            "signature by attacker key must NOT verify against victim address"
        );
    }

    #[test]
    fn test_verify_data_expected_address_pins_signer() {
        // Attacker honestly signs with their own key AND their own address (this
        // is internally consistent and binds correctly). But a verifier that
        // pins the victim's address must still reject it.
        let victim = keys();
        let attacker = attacker_keys();

        let victim_addr_hex = address_to_hex(
            compute_base_address(victim.payment_key_hash, victim.stake_key_hash, 0).unwrap(),
        )
        .unwrap();
        let attacker_addr_hex = address_to_hex(
            compute_base_address(attacker.payment_key_hash, attacker.stake_key_hash, 0).unwrap(),
        )
        .unwrap();
        let payload = hex::encode("login");

        let sig = cip30_sign_data(
            attacker_addr_hex.clone(),
            payload.clone(),
            attacker.payment_signing_key,
        )
        .unwrap();

        // Self-consistent: verifies against the attacker's own address.
        assert!(
            cip30_verify_data(sig.clone(), Some(payload.clone()), Some(attacker_addr_hex)).unwrap()
        );
        // But not when the verifier requires the victim's address.
        assert!(
            !cip30_verify_data(sig, Some(payload), Some(victim_addr_hex)).unwrap(),
            "must reject when pinned address differs from header address"
        );
    }

    #[test]
    fn test_verify_data_expected_address_matches() {
        let k = keys();
        let addr_hex =
            address_to_hex(compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap())
                .unwrap();
        let payload = hex::encode("ok");
        let sig =
            cip30_sign_data(addr_hex.clone(), payload.clone(), k.payment_signing_key).unwrap();

        assert!(
            cip30_verify_data(sig, Some(payload), Some(addr_hex)).unwrap(),
            "honest signature must verify when the pinned address matches"
        );
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

    // ── Cross-implementation interop vectors ────────────────────────────────
    //
    // These `COSE_Sign1` + `COSE_Key` blobs were produced OUTSIDE this crate by
    // Emurgo's `@emurgo/cardano-message-signing-nodejs` (the reference COSE/CIP-8
    // WASM library that Lace / Eternl / Nami / MeshJS use) signing with keys
    // derived by `@emurgo/cardano-serialization-lib-nodejs` from the shared test
    // mnemonic. They are frozen here as a regression gate: our hardened
    // `cip30_verify_data` (CSL-based identity binding) must ACCEPT a genuine
    // wallet-shaped signature for both address forms a wallet emits —
    //   • a base address signed by the payment key (dApp login), and
    //   • a reward (stake) address signed by the stake key.
    // Generation is reproducible via tools/cose-interop/gen.js (see docs).

    // base address signed by the payment key.
    const EXT_BASE_ADDRESS_HEX: &str = "009493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e32c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dc";
    const EXT_BASE_PAYLOAD_HEX: &str =
        "4c6f67696e20746f204578616d706c654441707020617420323032362d30362d3034";
    const EXT_BASE_SIG_HEX: &str = "845846a2012767616464726573735839009493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e32c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dca166686173686564f458224c6f67696e20746f204578616d706c654441707020617420323032362d30362d30345840c98ec88a85c603c66ba729e92b0fdef7c6c0c484b1474c64584eec2456f228b459ed5685a7f5d7063ddcf78ffe71f9de121cf408e4ecf98eeedd33f5e7677b04";
    const EXT_BASE_KEY_HEX: &str = "a501010327048102200621582073fea80d424276ad0978d4fe5310e8bc2d485f5f6bb3bf87612989f112ad5a7d";

    // reward (stake) address signed by the stake key.
    const EXT_REWARD_ADDRESS_HEX: &str =
        "e032c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dc";
    const EXT_REWARD_PAYLOAD_HEX: &str = "50726f7665207374616b65206b6579206f776e657273686970";
    const EXT_REWARD_SIG_HEX: &str = "84582aa201276761646472657373581de032c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dca166686173686564f4581950726f7665207374616b65206b6579206f776e65727368697058408a52ad61150efd36d7e830cb8641faba7757a36686f2cb6f503ca3a8f0dad7209d89f2f92dd4fe2f95bf580424d4b6436130b00ccfe4c2e50287ac977256c707";
    const EXT_REWARD_KEY_HEX: &str = "a50101032704810220062158202c041c9c6a676ac54d25e2fdce44c56581e316ae43adc4c7bf17f23214d8d892";

    #[test]
    fn test_interop_external_base_address_vector_verifies() {
        // The external lib derived the same base address we do — ties the foreign
        // vector to our own derivation.
        let k = keys();
        let ours =
            address_to_hex(compute_base_address(k.payment_key_hash, k.stake_key_hash, 0).unwrap())
                .unwrap();
        assert_eq!(
            ours, EXT_BASE_ADDRESS_HEX,
            "external base address must match ours"
        );

        let sig = DataSignature {
            signature: EXT_BASE_SIG_HEX.to_string(),
            key: EXT_BASE_KEY_HEX.to_string(),
        };
        assert!(
            cip30_verify_data(
                sig,
                Some(EXT_BASE_PAYLOAD_HEX.to_string()),
                Some(EXT_BASE_ADDRESS_HEX.to_string()),
            )
            .unwrap(),
            "wallet-shaped base-address signature must verify with identity binding"
        );
    }

    #[test]
    fn test_interop_external_reward_address_vector_verifies() {
        // Exercises the RewardAddress branch of the credential binding: the stake
        // key signs and the stake (reward) address sits in the header.
        let sig = DataSignature {
            signature: EXT_REWARD_SIG_HEX.to_string(),
            key: EXT_REWARD_KEY_HEX.to_string(),
        };
        assert!(
            cip30_verify_data(
                sig,
                Some(EXT_REWARD_PAYLOAD_HEX.to_string()),
                Some(EXT_REWARD_ADDRESS_HEX.to_string()),
            )
            .unwrap(),
            "wallet-shaped reward-address signature must verify with identity binding"
        );
    }

    #[test]
    fn test_interop_external_vector_rejects_swapped_key() {
        // Take the genuine base-address signature but present the OTHER vector's
        // COSE_Key. The key no longer hashes to the header address → reject,
        // proving the binding guards the externally-produced signature too.
        let forged = DataSignature {
            signature: EXT_BASE_SIG_HEX.to_string(),
            key: EXT_REWARD_KEY_HEX.to_string(),
        };
        assert!(
            !cip30_verify_data(forged, Some(EXT_BASE_PAYLOAD_HEX.to_string()), None).unwrap(),
            "a mismatched COSE_Key must not verify against the header address"
        );
    }

    // ── Live wallet vector ──────────────────────────────────────────────────
    //
    // Captured from the real **Eternl** browser extension (mainnet) signing
    // "cardano-flutter-sdk COSE interop check" over its own base address via the
    // CIP-30 `signData` API (tools/cose-interop/wallet-capture.html). Note the
    // COSE_Key here is `a4…` (no `key_ops` entry) — a different encoding from the
    // `a5…` our signer emits — so this also guards against over-strict COSE_Key
    // parsing. The hardened verifier must accept it with the address bound.
    const ETERNL_ADDRESS_HEX: &str = "0110997ab1d79815c41244f70195ec41ebbcb9698d023465a397353fa083d566cb6d70811839d998f40393fb43132688164423842135f8b20b";
    const ETERNL_PAYLOAD_HEX: &str =
        "63617264616e6f2d666c75747465722d73646b20434f534520696e7465726f7020636865636b";
    const ETERNL_SIG_HEX: &str = "845846a20127676164647265737358390110997ab1d79815c41244f70195ec41ebbcb9698d023465a397353fa083d566cb6d70811839d998f40393fb43132688164423842135f8b20ba166686173686564f4582663617264616e6f2d666c75747465722d73646b20434f534520696e7465726f7020636865636b58402304c4d20e247c1ebb958359e418eb6b90d5571977990528c947f6d363d65f8b0d1da8daaed3597eae30c045e0c4c3427b68bb8d4c2706db2e48529b83108b0a";
    const ETERNL_KEY_HEX: &str =
        "a40101032720062158205af41bc80e360f15d611eb610fd3f12903a920dc0a49901e29de261c881e50fa";

    #[test]
    fn test_interop_live_eternl_mainnet_vector_verifies() {
        let sig = DataSignature {
            signature: ETERNL_SIG_HEX.to_string(),
            key: ETERNL_KEY_HEX.to_string(),
        };
        assert!(
            cip30_verify_data(
                sig,
                Some(ETERNL_PAYLOAD_HEX.to_string()),
                Some(ETERNL_ADDRESS_HEX.to_string()),
            )
            .unwrap(),
            "a real Eternl signData signature must verify with identity binding"
        );
    }

    #[test]
    fn test_interop_live_eternl_vector_rejects_wrong_payload() {
        let sig = DataSignature {
            signature: ETERNL_SIG_HEX.to_string(),
            key: ETERNL_KEY_HEX.to_string(),
        };
        assert!(
            !cip30_verify_data(sig, Some(hex::encode("not what was signed")), None).unwrap(),
            "the real signature must not verify for a different payload"
        );
    }
}
