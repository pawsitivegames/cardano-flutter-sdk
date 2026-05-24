use crate::error::CardanoError;
use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

#[derive(Clone, Debug)]
pub struct KeyDerivationResult {
    pub account_key: String,
    pub payment_key: String,
    pub stake_key: String,
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

    Ok(KeyDerivationResult {
        account_key: account_key.to_bech32(),
        payment_key: payment_key.to_public().to_bech32(),
        stake_key: stake_key.to_public().to_bech32(),
    })
}

#[frb(sync)]
pub fn derive_account_key(
    account_key: String,
    role: u32,
    index: u32,
) -> Result<String, String> {
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

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_MNEMONIC: &str = "test walk nut penalty hip pave soap entry language right filter choice";

    #[test]
    fn test_derive_keys_from_mnemonic() {
        let result = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, false);
        assert!(result.is_ok());
        let keys = result.unwrap();
        assert!(!keys.account_key.is_empty());
        assert!(!keys.payment_key.is_empty());
        assert!(!keys.stake_key.is_empty());
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
}
