//! Hardware-wallet support primitives (Phase 4.5).
//!
//! A hardware wallet (Ledger, Trezor) never exposes private keys. Instead it
//! hands back a BIP-32 *account-level extended public key* (xpub) and, on
//! request, signs a transaction and returns raw Ed25519 vkey witnesses. This
//! module provides the two pure, device-agnostic primitives the SDK needs to
//! make those usable:
//!
//! - [`xpub_to_account`] — soft-derive a wallet's base + reward addresses and
//!   payment/stake key hashes from the account xpub (CIP-1852 roles 0 and 2,
//!   index 0). No private keys involved, so it also serves watch-only wallets.
//! - [`assemble_vkey_witness_set`] — fold the raw vkey witnesses a device
//!   returns into a CBOR `transaction_witness_set`, ready for
//!   [`crate::cip30::cip30_assemble_tx`] to combine with the body into a
//!   submittable transaction.
//!
//! The actual device transport (BLE/USB, APDU) lives outside the core SDK — in
//! the example app it is provided by `ledger_cardano_plus` / `ledger_flutter_plus`.

use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

use crate::error::CardanoError;
use crate::tx::{hex_to_bytes, map_csl_error, map_deserialize_error};

/// A wallet account derived from a hardware-wallet (or watch-only) xpub.
///
/// All fields are derived purely from public-key material — no signing key is
/// ever required or produced.
#[derive(Clone, Debug)]
pub struct HardwareAccount {
    /// Bech32 base address (`addr…` / `addr_test…`) at role 0 / index 0.
    pub base_address: String,
    /// Bech32 reward (stake) address (`stake…` / `stake_test…`).
    pub reward_address: String,
    /// Blake2b-224 payment key hash (56 hex chars).
    pub payment_key_hash: String,
    /// Blake2b-224 stake key hash (56 hex chars).
    pub stake_key_hash: String,
}

/// A single Ed25519 vkey witness as returned by a hardware device.
#[derive(Clone, Debug)]
pub struct HardwareVkeyWitness {
    /// 32-byte raw Ed25519 public key, hex-encoded (64 hex chars).
    pub vkey_hex: String,
    /// 64-byte raw Ed25519 signature, hex-encoded (128 hex chars).
    pub signature_hex: String,
}

/// Derive a wallet [`HardwareAccount`] from a BIP-32 account-level xpub.
///
/// The xpub is the 64-byte CIP-1852 account key (`m/1852'/1815'/account'`) a
/// hardware wallet returns from its "get extended public key" call: 32 bytes of
/// raw Ed25519 public key followed by a 32-byte chain code. From it we soft-derive
/// the payment key (`…/0/0`) and stake key (`…/2/0`), hash each (Blake2b-224),
/// and assemble the base + reward addresses.
///
/// # Arguments
/// - `account_xpub_hex`: 128-char hex of the 64-byte account xpub
/// - `network_id`: 0 = testnet, 1 = mainnet
#[frb(sync)]
pub fn xpub_to_account(
    account_xpub_hex: String,
    network_id: u8,
) -> Result<HardwareAccount, CardanoError> {
    let bytes = hex_to_bytes(&account_xpub_hex)?;
    if bytes.len() != 64 {
        return Err(CardanoError::InvalidKey(format!(
            "Account xpub must be 64 bytes (got {})",
            bytes.len()
        )));
    }
    let xpub = csl::Bip32PublicKey::from_bytes(&bytes)
        .map_err(|_| CardanoError::InvalidKey("Invalid BIP-32 account xpub".to_string()))?;

    // Soft derivation (public-key only): payment = role 0, stake = role 2.
    let payment_pub = xpub
        .derive(0)
        .map_err(map_csl_error)?
        .derive(0)
        .map_err(map_csl_error)?;
    let stake_pub = xpub
        .derive(2)
        .map_err(map_csl_error)?
        .derive(0)
        .map_err(map_csl_error)?;

    let pay_hash = payment_pub.to_raw_key().hash();
    let stake_hash = stake_pub.to_raw_key().hash();

    let pay_cred = csl::Credential::from_keyhash(&pay_hash);
    let stake_cred = csl::Credential::from_keyhash(&stake_hash);

    let base = csl::BaseAddress::new(network_id, &pay_cred, &stake_cred);
    let reward = csl::RewardAddress::new(network_id, &stake_cred);

    Ok(HardwareAccount {
        base_address: base.to_address().to_bech32(None).map_err(map_csl_error)?,
        reward_address: reward.to_address().to_bech32(None).map_err(map_csl_error)?,
        payment_key_hash: hex::encode(pay_hash.to_bytes()),
        stake_key_hash: hex::encode(stake_hash.to_bytes()),
    })
}

/// Soft-derive a single raw Ed25519 public key from an account xpub.
///
/// Symmetric with [`xpub_to_account`]: a hardware device returns each signature
/// paired only with a BIP-32 *path* (no public key), so to turn a device
/// `(path, signature)` into a vkey witness we re-derive that path's public key
/// from the same account xpub the addresses were derived from.
///
/// `role`/`index` are the last two (non-hardened) segments of a CIP-1852 path —
/// e.g. payment is `role = 0, index = 0`, stake is `role = 2, index = 0`.
///
/// # Arguments
/// - `account_xpub_hex`: 128-char hex of the 64-byte account xpub
/// - `role`: CIP-1852 role (0 = external/payment, 1 = change, 2 = stake)
/// - `index`: address index within the role
///
/// Returns the 32-byte raw Ed25519 public key as 64 hex chars.
#[frb(sync)]
pub fn xpub_derive_public_key(
    account_xpub_hex: String,
    role: u32,
    index: u32,
) -> Result<String, CardanoError> {
    let bytes = hex_to_bytes(&account_xpub_hex)?;
    if bytes.len() != 64 {
        return Err(CardanoError::InvalidKey(format!(
            "Account xpub must be 64 bytes (got {})",
            bytes.len()
        )));
    }
    let xpub = csl::Bip32PublicKey::from_bytes(&bytes)
        .map_err(|_| CardanoError::InvalidKey("Invalid BIP-32 account xpub".to_string()))?;
    let derived = xpub
        .derive(role)
        .map_err(map_csl_error)?
        .derive(index)
        .map_err(map_csl_error)?;
    Ok(hex::encode(derived.to_raw_key().as_bytes()))
}

/// A transaction input, in the device-friendly form a hardware wallet displays
/// and witnesses (the UTxO it spends, without the resolved value).
#[derive(Clone, Debug)]
pub struct HardwareTxInput {
    /// 32-byte transaction id of the UTxO being spent, hex (64 chars).
    pub tx_hash_hex: String,
    /// Output index within that transaction.
    pub output_index: u32,
}

/// A native-asset entry inside a decomposed transaction output.
#[derive(Clone, Debug)]
pub struct HardwareTxAsset {
    /// 28-byte policy id, hex (56 chars).
    pub policy_id_hex: String,
    /// Asset name bytes, hex (0–64 chars).
    pub asset_name_hex: String,
    /// Quantity as a decimal string (u64).
    pub amount: String,
}

/// A transaction output in the device-friendly form a hardware wallet displays.
#[derive(Clone, Debug)]
pub struct HardwareTxOutput {
    /// Raw address bytes, hex — exactly what a device's "third-party address"
    /// destination expects (not bech32, not CBOR-wrapped).
    pub address_hex: String,
    /// ADA amount (lovelace) as a decimal string (u64).
    pub coin: String,
    /// Native assets carried by the output.
    pub assets: Vec<HardwareTxAsset>,
}

/// A transaction body decomposed into the primitives a hardware device needs to
/// reconstruct, display, and sign it.
///
/// Hardware wallets (Ledger) do not sign raw CBOR — they are handed a structured
/// description of the transaction, re-serialize it on-device, show it to the
/// user, and sign the hash they compute. This is the SDK's authoritative
/// (CSL-parsed) decomposition of a transaction body that a device adapter maps
/// into its own wire types.
#[derive(Clone, Debug)]
pub struct HardwareTxBody {
    /// Inputs (UTxOs) the transaction spends.
    pub inputs: Vec<HardwareTxInput>,
    /// Outputs the transaction creates.
    pub outputs: Vec<HardwareTxOutput>,
    /// Fee in lovelace, as a decimal string (u64).
    pub fee: String,
    /// Time-to-live slot, if set (decimal string).
    pub ttl: Option<String>,
    /// Validity-interval start slot, if set (decimal string).
    pub validity_start: Option<String>,
    /// Network id carried in the body, if present (0 = testnet, 1 = mainnet).
    pub network_id: Option<u8>,
    /// `true` when the body carries features this decomposition does **not** yet
    /// model (certificates, withdrawals, mint, collateral, reference inputs,
    /// governance votes). A device adapter MUST refuse to sign in that case
    /// rather than present the user an incomplete transaction.
    pub has_unsupported_features: bool,
}

/// Decompose a CBOR transaction **body** into device-signable primitives.
///
/// The inverse direction of assembly: the SDK builds a transaction body, this
/// breaks it back into the structured inputs/outputs/fee/ttl a hardware device
/// needs to reconstruct it. Parsing is delegated to CSL so the decomposition is
/// authoritative.
///
/// Only the ordinary-payment shape is modelled today (inputs, outputs with ADA +
/// native tokens, fee, ttl, validity start, network id). Bodies with
/// certificates, withdrawals, mint, collateral, reference inputs, or governance
/// votes set [`HardwareTxBody::has_unsupported_features`] so the caller can
/// refuse rather than mis-sign.
///
/// # Arguments
/// - `tx_body_cbor_hex`: CBOR hex of a `TransactionBody`
#[frb(sync)]
pub fn decompose_tx_body(tx_body_cbor_hex: String) -> Result<HardwareTxBody, CardanoError> {
    let body = csl::TransactionBody::from_bytes(hex_to_bytes(&tx_body_cbor_hex)?)
        .map_err(|_| CardanoError::InvalidCbor("Invalid tx body CBOR".to_string()))?;

    let mut inputs = Vec::new();
    let ins = body.inputs();
    for i in 0..ins.len() {
        let inp = ins.get(i);
        inputs.push(HardwareTxInput {
            tx_hash_hex: hex::encode(inp.transaction_id().to_bytes()),
            output_index: inp.index(),
        });
    }

    let mut outputs = Vec::new();
    let outs = body.outputs();
    for i in 0..outs.len() {
        let out = outs.get(i);
        let val = out.amount();
        let mut assets = Vec::new();
        if let Some(ma) = val.multiasset() {
            let policies = ma.keys();
            for p in 0..policies.len() {
                let policy = policies.get(p);
                if let Some(asset_map) = ma.get(&policy) {
                    let names = asset_map.keys();
                    for n in 0..names.len() {
                        let name = names.get(n);
                        if let Some(qty) = asset_map.get(&name) {
                            assets.push(HardwareTxAsset {
                                policy_id_hex: hex::encode(policy.to_bytes()),
                                asset_name_hex: hex::encode(name.name()),
                                amount: qty.to_str(),
                            });
                        }
                    }
                }
            }
        }
        outputs.push(HardwareTxOutput {
            address_hex: hex::encode(out.address().to_bytes()),
            coin: val.coin().to_str(),
            assets,
        });
    }

    let has_unsupported_features = body.certs().is_some()
        || body.withdrawals().is_some()
        || body.mint().is_some()
        || body.collateral().is_some()
        || body.reference_inputs().is_some()
        || body.voting_procedures().is_some();

    let network_id = body.network_id().map(|n| match n.kind() {
        csl::NetworkIdKind::Testnet => 0u8,
        csl::NetworkIdKind::Mainnet => 1u8,
    });

    Ok(HardwareTxBody {
        inputs,
        outputs,
        fee: body.fee().to_str(),
        ttl: body.ttl_bignum().map(|t| t.to_str()),
        validity_start: body.validity_start_interval_bignum().map(|t| t.to_str()),
        network_id,
        has_unsupported_features,
    })
}

/// Assemble raw device vkey witnesses into a CBOR `transaction_witness_set`.
///
/// Hardware wallets return `(public_key, signature)` pairs rather than a CBOR
/// witness set. This packs them into a `TransactionWitnessSet` whose hex output
/// can be passed straight to [`crate::cip30::cip30_assemble_tx`] (or merged with
/// other witnesses) to build a submittable transaction.
///
/// # Arguments
/// - `witnesses`: device-produced `(vkey_hex, signature_hex)` pairs
#[frb(sync)]
pub fn assemble_vkey_witness_set(
    witnesses: Vec<HardwareVkeyWitness>,
) -> Result<String, CardanoError> {
    let mut vkeys = csl::Vkeywitnesses::new();
    for w in &witnesses {
        let pubkey =
            csl::PublicKey::from_bytes(&hex_to_bytes(&w.vkey_hex)?).map_err(map_csl_error)?;
        let sig = csl::Ed25519Signature::from_bytes(hex_to_bytes(&w.signature_hex)?)
            .map_err(map_deserialize_error)?;
        let vkey = csl::Vkey::new(&pubkey);
        vkeys.add(&csl::Vkeywitness::new(&vkey, &sig));
    }
    let mut ws = csl::TransactionWitnessSet::new();
    ws.set_vkeys(&vkeys);
    Ok(hex::encode(ws.to_bytes()))
}

/// Extract the raw vkey witnesses from a CBOR `transaction_witness_set`.
///
/// The inverse of [`assemble_vkey_witness_set`]. Useful for partial-signing and
/// multi-signature flows: pull the `(public_key, signature)` pairs out of a
/// witness set (e.g. one produced by software signing or another cosigner) to
/// merge them with witnesses from a hardware device.
///
/// Returns an empty list if the witness set carries no vkey witnesses.
///
/// # Arguments
/// - `witness_set_cbor_hex`: hex CBOR of a `TransactionWitnessSet`
#[frb(sync)]
pub fn extract_vkey_witnesses(
    witness_set_cbor_hex: String,
) -> Result<Vec<HardwareVkeyWitness>, CardanoError> {
    let ws = csl::TransactionWitnessSet::from_bytes(hex_to_bytes(&witness_set_cbor_hex)?)
        .map_err(|_| CardanoError::InvalidCbor("Invalid witness set CBOR".to_string()))?;
    let mut out = Vec::new();
    if let Some(vkeys) = ws.vkeys() {
        for i in 0..vkeys.len() {
            let vw = vkeys.get(i);
            out.push(HardwareVkeyWitness {
                vkey_hex: hex::encode(vw.vkey().public_key().as_bytes()),
                signature_hex: hex::encode(vw.signature().to_bytes()),
            });
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Account xpub for the test mnemonic
    // ("test walk nut penalty hip pave soap entry language right filter choice"),
    // i.e. m/1852'/1815'/0'.to_public() — see wallet.rs derivation.
    const TEST_ACCT_XPUB: &str = "cf779aa32f35083707808532471cb64ee41426c9bbd46134dac2ac5b2a0ec0e98fa5fcd46abd9d46d4d8a97a8f3465e2c4e8f3c9dad9ff66823a161ecadca604";

    // The same key hashes wallet.rs derives from the mnemonic private path —
    // proving public soft-derivation lands on the identical credentials.
    const EXPECTED_PAY_HASH: &str = "9493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e";
    const EXPECTED_STAKE_HASH: &str = "32c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dc";

    #[test]
    fn xpub_to_account_matches_mnemonic_path() {
        let acct = xpub_to_account(TEST_ACCT_XPUB.to_string(), 0).unwrap();
        assert_eq!(acct.payment_key_hash, EXPECTED_PAY_HASH);
        assert_eq!(acct.stake_key_hash, EXPECTED_STAKE_HASH);
        assert!(acct.base_address.starts_with("addr_test1"));
        assert!(acct.reward_address.starts_with("stake_test1"));
    }

    #[test]
    fn xpub_to_account_mainnet_prefixes() {
        let acct = xpub_to_account(TEST_ACCT_XPUB.to_string(), 1).unwrap();
        assert!(acct.base_address.starts_with("addr1"));
        assert!(acct.reward_address.starts_with("stake1"));
        // Credentials are network-independent.
        assert_eq!(acct.payment_key_hash, EXPECTED_PAY_HASH);
    }

    #[test]
    fn xpub_to_account_rejects_wrong_length() {
        let err = xpub_to_account("abcd".to_string(), 0);
        assert!(err.is_err());
    }

    #[test]
    fn assemble_vkey_witness_set_roundtrips() {
        // Build a real witness with CSL so the bytes are valid, then assemble.
        let prv = csl::PrivateKey::generate_ed25519().unwrap();
        let pubkey = prv.to_public();
        let msg = [0u8; 32];
        let sig = prv.sign(&msg);
        let w = HardwareVkeyWitness {
            vkey_hex: hex::encode(pubkey.as_bytes()),
            signature_hex: hex::encode(sig.to_bytes()),
        };
        let hex_ws = assemble_vkey_witness_set(vec![w]).unwrap();
        // Parses back as a witness set with exactly one vkey witness.
        let ws = csl::TransactionWitnessSet::from_bytes(hex::decode(&hex_ws).unwrap()).unwrap();
        let vkeys = ws.vkeys().unwrap();
        assert_eq!(vkeys.len(), 1);
        // The witness signature verifies against the public key.
        let vw = vkeys.get(0);
        assert!(pubkey.verify(&msg, &vw.signature()));
    }

    #[test]
    fn extract_then_assemble_is_identity() {
        let prv = csl::PrivateKey::generate_ed25519().unwrap();
        let pubkey = prv.to_public();
        let sig = prv.sign(&[1u8; 32]);
        let original = HardwareVkeyWitness {
            vkey_hex: hex::encode(pubkey.as_bytes()),
            signature_hex: hex::encode(sig.to_bytes()),
        };
        let ws_hex = assemble_vkey_witness_set(vec![original.clone()]).unwrap();
        let extracted = extract_vkey_witnesses(ws_hex).unwrap();
        assert_eq!(extracted.len(), 1);
        assert_eq!(extracted[0].vkey_hex, original.vkey_hex);
        assert_eq!(extracted[0].signature_hex, original.signature_hex);
    }

    #[test]
    fn extract_vkey_witnesses_empty_set() {
        let ws = csl::TransactionWitnessSet::new();
        let hex_ws = hex::encode(ws.to_bytes());
        assert!(extract_vkey_witnesses(hex_ws).unwrap().is_empty());
    }

    #[test]
    fn xpub_derive_public_key_matches_account_hashes() {
        // The payment pubkey (role 0, index 0) must hash to the same payment key
        // hash xpub_to_account produces — proving the device-witness pubkey
        // derivation is consistent with the address derivation.
        let pay_pub_hex = xpub_derive_public_key(TEST_ACCT_XPUB.to_string(), 0, 0).unwrap();
        let pay_pub = csl::PublicKey::from_bytes(&hex::decode(&pay_pub_hex).unwrap()).unwrap();
        assert_eq!(hex::encode(pay_pub.hash().to_bytes()), EXPECTED_PAY_HASH);

        let stake_pub_hex = xpub_derive_public_key(TEST_ACCT_XPUB.to_string(), 2, 0).unwrap();
        let stake_pub = csl::PublicKey::from_bytes(&hex::decode(&stake_pub_hex).unwrap()).unwrap();
        assert_eq!(
            hex::encode(stake_pub.hash().to_bytes()),
            EXPECTED_STAKE_HASH
        );
    }

    #[test]
    fn xpub_derive_public_key_rejects_wrong_length() {
        assert!(xpub_derive_public_key("abcd".to_string(), 0, 0).is_err());
    }

    #[test]
    fn decompose_tx_body_roundtrips_payment() {
        // Build a minimal body with CSL: one input, one output (ADA), fee, ttl.
        let mut body_inputs = csl::TransactionInputs::new();
        let tx_hash = csl::TransactionHash::from_bytes(vec![7u8; 32]).unwrap();
        body_inputs.add(&csl::TransactionInput::new(&tx_hash, 1));

        let addr = csl::Address::from_bech32(
            "addr_test1vpu5vlrf4xkxv2qpwngf6cjhtw542ayty80v8dyr49rf5eg57c2qv",
        )
        .unwrap();
        let mut body_outputs = csl::TransactionOutputs::new();
        body_outputs.add(&csl::TransactionOutput::new(
            &addr,
            &csl::Value::new(&csl::BigNum::from(1_500_000u64)),
        ));

        let mut body = csl::TransactionBody::new_tx_body(
            &body_inputs,
            &body_outputs,
            &csl::BigNum::from(170_000u64),
        );
        body.set_ttl(&csl::BigNum::from(99_000_000u64));

        let parts = decompose_tx_body(hex::encode(body.to_bytes())).unwrap();
        assert_eq!(parts.inputs.len(), 1);
        assert_eq!(parts.inputs[0].tx_hash_hex, hex::encode([7u8; 32]));
        assert_eq!(parts.inputs[0].output_index, 1);
        assert_eq!(parts.outputs.len(), 1);
        assert_eq!(parts.outputs[0].coin, "1500000");
        assert!(parts.outputs[0].assets.is_empty());
        // address_hex is the raw address bytes (matches the bech32 we built from).
        assert_eq!(parts.outputs[0].address_hex, hex::encode(addr.to_bytes()));
        assert_eq!(parts.fee, "170000");
        assert_eq!(parts.ttl.as_deref(), Some("99000000"));
        assert!(!parts.has_unsupported_features);
    }

    #[test]
    fn decompose_tx_body_flags_certificates() {
        // A body carrying a stake registration certificate must be flagged so a
        // device adapter refuses rather than mis-signing.
        let mut body_inputs = csl::TransactionInputs::new();
        let tx_hash = csl::TransactionHash::from_bytes(vec![3u8; 32]).unwrap();
        body_inputs.add(&csl::TransactionInput::new(&tx_hash, 0));
        let addr = csl::Address::from_bech32(
            "addr_test1vpu5vlrf4xkxv2qpwngf6cjhtw542ayty80v8dyr49rf5eg57c2qv",
        )
        .unwrap();
        let mut body_outputs = csl::TransactionOutputs::new();
        body_outputs.add(&csl::TransactionOutput::new(
            &addr,
            &csl::Value::new(&csl::BigNum::from(1_000_000u64)),
        ));
        let mut body = csl::TransactionBody::new_tx_body(
            &body_inputs,
            &body_outputs,
            &csl::BigNum::from(170_000u64),
        );

        let stake_pub_hex = xpub_derive_public_key(TEST_ACCT_XPUB.to_string(), 2, 0).unwrap();
        let stake_hash = csl::PublicKey::from_bytes(&hex::decode(&stake_pub_hex).unwrap())
            .unwrap()
            .hash();
        let cred = csl::Credential::from_keyhash(&stake_hash);
        let mut certs = csl::Certificates::new();
        certs.add(&csl::Certificate::new_stake_registration(
            &csl::StakeRegistration::new(&cred),
        ));
        body.set_certs(&certs);

        let parts = decompose_tx_body(hex::encode(body.to_bytes())).unwrap();
        assert!(parts.has_unsupported_features);
    }

    #[test]
    fn decompose_tx_body_rejects_bad_cbor() {
        assert!(decompose_tx_body("00".to_string()).is_err());
    }

    #[test]
    fn assemble_vkey_witness_set_rejects_bad_hex() {
        let w = HardwareVkeyWitness {
            vkey_hex: "zz".to_string(),
            signature_hex: "zz".to_string(),
        };
        assert!(assemble_vkey_witness_set(vec![w]).is_err());
    }
}
