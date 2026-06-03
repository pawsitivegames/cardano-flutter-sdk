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
    fn assemble_vkey_witness_set_rejects_bad_hex() {
        let w = HardwareVkeyWitness {
            vkey_hex: "zz".to_string(),
            signature_hex: "zz".to_string(),
        };
        assert!(assemble_vkey_witness_set(vec![w]).is_err());
    }
}
