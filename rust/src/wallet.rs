use crate::error::CardanoError;
use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

#[derive(Clone, Debug)]
pub struct KeyDerivationResult {
    pub account_key: String,
    /// Payment public key bech32 (xpub). For display only — NOT for signing.
    pub payment_key: String,
    /// Stake public key bech32 (xpub). For display only — NOT for signing.
    pub stake_key: String,
    /// Blake2b-224 hash of the payment public key (28 bytes = 56 hex chars).
    /// Use as `key_hash_hex` argument for `make_pubkey_script`.
    pub payment_key_hash: String,
    /// Payment private key bech32 (xprv) at m/1852'/1815'/0'/0/0.
    /// Pass to `sign_tx` / `sign_tx_with_metadata`.
    pub payment_signing_key: String,
    /// Stake private key bech32 (xprv) at m/1852'/1815'/0'/2/0.
    /// Pass to signing functions for staking certificates / withdrawals.
    pub stake_signing_key: String,
    /// Blake2b-224 hash of the stake public key (28 bytes = 56 hex chars).
    pub stake_key_hash: String,
}

#[frb(sync)]
pub fn derive_keys_from_mnemonic(
    mnemonic: String,
    passphrase: String,
    account_index: u32,
    _is_testnet: bool,
) -> Result<KeyDerivationResult, String> {
    derive_keys_from_mnemonic_internal(&mnemonic, &passphrase, account_index, false)
        .map_err(|e| e.to_string())
}

pub fn derive_keys_from_mnemonic_internal(
    mnemonic: &str,
    passphrase: &str,
    account_index: u32,
    _is_testnet: bool,
) -> Result<KeyDerivationResult, CardanoError> {
    let mnemonic_obj = bip39::Mnemonic::parse(mnemonic)
        .map_err(|_| CardanoError::InvalidMnemonic("Invalid mnemonic words".to_string()))?;

    let entropy = mnemonic_obj.to_entropy();
    let root_key = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, passphrase.as_bytes());

    // CIP-1852: m/1852'/1815'/account'
    let account_key = root_key
        .derive(1852 | 0x80000000)
        .derive(1815 | 0x80000000)
        .derive(account_index | 0x80000000);

    // Payment key: m/1852'/1815'/account'/0/0
    let payment_key = account_key.derive(0).derive(0);

    // Stake key: m/1852'/1815'/account'/2/0
    let stake_key = account_key.derive(2).derive(0);

    let payment_pub = payment_key.to_public();
    let payment_key_hash = hex::encode(payment_pub.to_raw_key().hash().to_bytes());
    let stake_key_hash = hex::encode(stake_key.to_public().to_raw_key().hash().to_bytes());

    Ok(KeyDerivationResult {
        account_key: account_key.to_bech32(),
        payment_key: payment_pub.to_bech32(), // public (for display)
        payment_signing_key: payment_key.to_bech32(), // private xprv (for signing)
        stake_key: stake_key.to_public().to_bech32(), // public (for display)
        stake_signing_key: stake_key.to_bech32(), // private xprv (for signing)
        payment_key_hash,
        stake_key_hash,
    })
}

#[frb(sync)]
pub fn derive_account_key(account_key: String, role: u32, index: u32) -> Result<String, String> {
    derive_account_key_internal(&account_key, role, index).map_err(|e| e.to_string())
}

pub fn derive_account_key_internal(
    account_key: &str,
    role: u32,
    index: u32,
) -> Result<String, CardanoError> {
    let key = csl::Bip32PrivateKey::from_bech32(account_key)
        .map_err(|_| CardanoError::InvalidKey("Invalid account key format".to_string()))?;

    let derived_key = key.derive(role).derive(index);

    Ok(derived_key.to_public().to_bech32())
}

/// A base address derived at a specific (role, index) within an account, plus the
/// payment key hash for that slot. Used for HD multi-account discovery and
/// BIP-44 gap-limit address scanning (Phase 5a).
#[derive(Clone, Debug)]
pub struct DerivedAddress {
    /// bech32 base address (`addr…` mainnet / `addr_test…` testnet).
    pub address: String,
    /// Blake2b-224 hash (56 hex chars) of the payment public key at this slot.
    pub payment_key_hash: String,
}

/// Derive a base address from an account-level xprv (the `account_key` field of
/// [KeyDerivationResult]), combining the payment key at `(role, index)` with the
/// account's stake key (`m/.../account'/2/0`).
///
/// - `role`: 0 = external/receive chain, 1 = internal/change chain.
/// - `index`: address index on that chain.
/// - `network_id`: 0 = testnet, 1 = mainnet.
///
/// Deriving the stake credential internally means every address in an account
/// shares one stake key (one reward address per account), matching CIP-1852.
#[frb(sync)]
pub fn derive_address(
    account_key: String,
    role: u32,
    index: u32,
    network_id: u8,
) -> Result<DerivedAddress, String> {
    derive_address_internal(&account_key, role, index, network_id).map_err(|e| e.to_string())
}

pub fn derive_address_internal(
    account_key: &str,
    role: u32,
    index: u32,
    network_id: u8,
) -> Result<DerivedAddress, CardanoError> {
    let key = csl::Bip32PrivateKey::from_bech32(account_key)
        .map_err(|_| CardanoError::InvalidKey("Invalid account key format".to_string()))?;

    let payment_pub = key.derive(role).derive(index).to_public();
    let stake_pub = key.derive(2).derive(0).to_public();

    let pay_hash = payment_pub.to_raw_key().hash();
    let stake_hash = stake_pub.to_raw_key().hash();

    let pay_cred = csl::Credential::from_keyhash(&pay_hash);
    let stake_cred = csl::Credential::from_keyhash(&stake_hash);

    let base = csl::BaseAddress::new(network_id, &pay_cred, &stake_cred);
    let address = base
        .to_address()
        .to_bech32(None)
        .map_err(|e| CardanoError::SerializationError(e.to_string()))?;

    Ok(DerivedAddress {
        address,
        payment_key_hash: hex::encode(pay_hash.to_bytes()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_MNEMONIC: &str =
        "test walk nut penalty hip pave soap entry language right filter choice";

    #[test]
    fn print_payment_key_hash() {
        // Helper test — run with `cargo test -- --nocapture` to see the hash
        let mnemonic_obj = bip39::Mnemonic::parse(TEST_MNEMONIC).unwrap();
        let entropy = mnemonic_obj.to_entropy();
        let root = csl::Bip32PrivateKey::from_bip39_entropy(&entropy, b"");
        let pay_prv = root
            .derive(1852 | 0x8000_0000)
            .derive(1815 | 0x8000_0000)
            .derive(0x8000_0000)
            .derive(0)
            .derive(0);
        let hash = pay_prv.to_public().to_raw_key().hash();
        println!("payment_key_hash: {}", hex::encode(hash.to_bytes()));
        assert_eq!(hash.to_bytes().len(), 28);
    }

    #[test]
    fn test_derive_keys_from_mnemonic() {
        let result = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false);
        assert!(result.is_ok());
        let keys = result.unwrap();
        assert!(!keys.account_key.is_empty());
        // Public keys are xpub
        assert!(!keys.payment_key.is_empty());
        assert!(!keys.stake_key.is_empty());
        // Private signing keys are xprv
        assert!(
            keys.payment_signing_key.starts_with("xprv"),
            "payment_signing_key should start with 'xprv'"
        );
        assert!(
            keys.stake_signing_key.starts_with("xprv"),
            "stake_signing_key should start with 'xprv'"
        );
        assert_eq!(keys.payment_key_hash.len(), 56); // 28 bytes hex
        assert_eq!(
            keys.payment_key_hash,
            "9493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e"
        );
        assert_eq!(keys.stake_key_hash.len(), 56); // 28 bytes hex
    }

    #[test]
    fn test_invalid_mnemonic() {
        let result = derive_keys_from_mnemonic_internal("invalid mnemonic", "", 0, false);
        assert!(result.is_err());
    }

    #[test]
    fn test_derive_account_key() {
        let mnemonic_result = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false);
        assert!(mnemonic_result.is_ok());
        let account_key = mnemonic_result.unwrap().account_key;

        let result = derive_account_key_internal(&account_key, 0, 0);
        assert!(result.is_ok());
        assert!(!result.unwrap().is_empty());
    }

    #[test]
    fn test_derive_address_external_index0_matches_known_hash() {
        // Account 0, external role 0, index 0 must reproduce the canonical payment
        // key hash and a valid testnet base address.
        let keys = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false).unwrap();
        let d = derive_address_internal(&keys.account_key, 0, 0, 0).unwrap();
        assert_eq!(
            d.payment_key_hash,
            "9493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e"
        );
        assert!(d.address.starts_with("addr_test1"));
        // Same payment credential + stake credential as the CIP-30 base address.
        let expected =
            crate::cip30::compute_base_address(keys.payment_key_hash, keys.stake_key_hash, 0)
                .unwrap();
        assert_eq!(d.address, expected);
    }

    #[test]
    fn test_derive_address_distinct_per_index_and_role() {
        let keys = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false).unwrap();
        let ext0 = derive_address_internal(&keys.account_key, 0, 0, 0).unwrap();
        let ext1 = derive_address_internal(&keys.account_key, 0, 1, 0).unwrap();
        let chg0 = derive_address_internal(&keys.account_key, 1, 0, 0).unwrap();
        // Different indices and different roles yield different addresses/hashes.
        assert_ne!(ext0.payment_key_hash, ext1.payment_key_hash);
        assert_ne!(ext0.payment_key_hash, chg0.payment_key_hash);
        assert_ne!(ext0.address, ext1.address);
        assert_ne!(ext0.address, chg0.address);
    }

    #[test]
    fn test_derive_address_mainnet_prefix() {
        let keys = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false).unwrap();
        let d = derive_address_internal(&keys.account_key, 0, 0, 1).unwrap();
        assert!(d.address.starts_with("addr1"));
    }

    #[test]
    fn test_derive_address_accounts_differ() {
        // Different accounts must produce different external index-0 addresses.
        let k0 = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false).unwrap();
        let k1 = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 1, false).unwrap();
        let a0 = derive_address_internal(&k0.account_key, 0, 0, 0).unwrap();
        let a1 = derive_address_internal(&k1.account_key, 0, 0, 0).unwrap();
        assert_ne!(a0.address, a1.address);
    }

    #[test]
    fn test_derive_address_bad_key() {
        assert!(derive_address_internal("not-a-key", 0, 0, 0).is_err());
    }
}
