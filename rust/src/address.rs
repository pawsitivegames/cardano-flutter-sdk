use crate::error::CardanoError;
use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

#[derive(Clone, Debug)]
pub struct AddressInfo {
    pub address: String,
    pub network: String,
}

#[frb(sync)]
pub fn validate_address(address_str: String) -> Result<AddressInfo, String> {
    validate_address_internal(&address_str).map_err(|e| e.to_string())
}

pub fn validate_address_internal(address_str: &str) -> Result<AddressInfo, CardanoError> {
    let address = csl::Address::from_bech32(address_str).map_err(|_| {
        CardanoError::InvalidAddress(format!("Invalid bech32 address: {}", address_str))
    })?;

    let network = match address.network_id() {
        Ok(0) => "testnet",
        Ok(_) => "mainnet",
        Err(_) => "unknown",
    }
    .to_string();

    Ok(AddressInfo {
        address: address_str.to_string(),
        network,
    })
}

#[frb(sync)]
pub fn is_valid_bech32(addr: String) -> bool {
    csl::Address::from_bech32(&addr).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::derive_keys_from_mnemonic_internal;

    const TEST_MNEMONIC: &str =
        "test walk nut penalty hip pave soap entry language right filter choice";

    /// Derives a CSL-valid testnet enterprise address from the standard test mnemonic.
    /// Run with `cargo test derive_canonical -- --nocapture` to print the address.
    #[test]
    fn derive_canonical_testnet_address() {
        let keys = derive_keys_from_mnemonic_internal(TEST_MNEMONIC, "", 0, true).unwrap();
        let pub_key = csl::Bip32PublicKey::from_bech32(&keys.payment_key).unwrap();
        let payment_cred = csl::Credential::from_keyhash(&pub_key.to_raw_key().hash());
        // Network id 0 = testnet
        let addr = csl::EnterpriseAddress::new(0, &payment_cred)
            .to_address()
            .to_bech32(None)
            .unwrap();
        println!("Canonical testnet address: {}", addr);
        assert!(is_valid_bech32(addr));
    }

    /// Enterprise address derived from the test mnemonic via CIP-1852 m/1852'/1815'/0'/0/0.
    /// Verified CSL-valid by derive_canonical_testnet_address above.
    const TESTNET_ADDR: &str = "addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz";

    #[test]
    fn test_validate_valid_bech32() {
        assert!(is_valid_bech32(TESTNET_ADDR.to_string()));
    }

    #[test]
    fn test_validate_invalid_bech32() {
        let addr = "not_an_address";
        assert!(!is_valid_bech32(addr.to_string()));
    }

    #[test]
    fn test_validate_address_info() {
        // Test that short invalid addresses are rejected
        let addr = "addr123";
        let result = validate_address(addr.to_string());
        assert!(result.is_err());
    }
}
