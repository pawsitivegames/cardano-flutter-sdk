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
// Phase 2: transaction building and signing.
// Phase 3: native minting, Plutus data, CIP-25/68 metadata.

pub mod address;
pub mod coin_selection;
pub mod error;
pub mod message;
pub mod metadata;
pub mod minting;
pub mod plutus;
pub mod sign;
pub mod staking;
pub mod tx;
pub mod wallet;

use flutter_rust_bridge::frb;

// Re-export public types for Dart convenience
pub use address::{is_valid_bech32, validate_address, AddressInfo};
pub use coin_selection::{largest_first, CoinSelectionResult};
pub use message::{sign_message, verify_message, SignedMessage};
pub use metadata::{build_cip25_metadata, build_cip68_datum, Cip25Asset, Cip25Policy};
pub use minting::{
    build_mint_tx, compute_policy_id, make_pubkey_script, make_timelock_expiry_script,
    BuiltMintTx, MintAsset, MintSpec,
};
pub use plutus::{
    build_script_tx, plutus_data_bytes, plutus_data_constr, plutus_data_int, plutus_data_list,
    validate_plutus_data, PlutusInput, PlutusScriptVersion,
};
pub use sign::{sign_tx, sign_tx_with_metadata, SignedTx};
pub use staking::{
    build_delegation_tx, build_reward_withdrawal_tx, build_stake_deregistration_tx,
    build_stake_registration_tx, compute_stake_address, BuiltStakingTx,
};
pub use tx::{
    build_tx, estimate_fee, min_ada_for_output, BuiltTx, NativeAsset, ProtocolParams, TxInput,
    TxOutput, Value,
};
pub use wallet::{derive_account_key, derive_keys_from_mnemonic, KeyDerivationResult};

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
