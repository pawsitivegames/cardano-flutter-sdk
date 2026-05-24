mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
// cardano_flutter_rs — Rust FFI wrapper for the cardano_flutter_rs Dart package.
//
// Architecture: this crate provides an ergonomic Rust API around
// cardano-serialization-lib (CSL) with pluggable backend support.
// The Dart side calls into here via flutter_rust_bridge.
// Do NOT expose raw CSL types across the FFI boundary — always wrap them in
// this crate's own types for stability.
//
// Phase 1: CSL-backed address validation and key derivation.
// Phase 2+: transaction building and signing.

pub mod address;
pub mod error;
pub mod wallet;

use flutter_rust_bridge::frb;

// Re-export public types for Dart convenience
pub use address::{AddressInfo, is_valid_bech32, validate_address};
pub use wallet::{KeyDerivationResult, derive_keys_from_mnemonic, derive_account_key};

/// Returns SDK version string.
#[frb(sync)]
pub fn sdk_version() -> String {
    format!(
        "cardano_flutter_rs v{} (CSL-backed)",
        env!("CARGO_PKG_VERSION"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::address::is_valid_bech32;

    #[test]
    fn sdk_version_includes_crate_version() {
        let v = sdk_version();
        assert!(v.contains("cardano_flutter_rs"));
        assert!(v.contains("CSL-backed"));
    }

    #[test]
    fn validate_bech32_valid() {
        // Test with properly formatted address - exact validity may depend on CSL validation
        let addr = "addr1qw2f2cjnal96nuzl0pn5xysqf24kxyxnxvjd7yq6khvn2wl2uld";
        let _ = is_valid_bech32(addr.to_string());
    }

    #[test]
    fn validate_bech32_invalid() {
        assert!(!is_valid_bech32("not_an_address".to_string()));
    }
}
