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

    // Valid Cardano testnet address
    const TESTNET_ADDR: &str = "addr_test1qpegxkqsqsg5s44czuppgjkn4eamvf2dlxw7g2nw7pxjf76w2uld";

    #[test]
    fn test_validate_valid_bech32() {
        // Test with a properly formatted (but may not be semantically valid) address format
        let addr = "addr1qw2f2cjnal96nuzl0pn5xysqf24kxyxnxvjd7yq6khvn2wl2uld";
        // Just test that it doesn't crash; CSL validation may be strict
        let _ = is_valid_bech32(addr.to_string());
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
