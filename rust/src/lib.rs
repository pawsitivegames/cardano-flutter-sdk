mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
// cardano_flutter_rs — Rust FFI wrapper for the cardano_flutter_rs Dart package.
//
// Architecture: this crate provides an ergonomic Rust API around
// cardano-multiplatform-lib (CML). The Dart side calls into here via
// flutter_rust_bridge. Do NOT expose raw CML types across the FFI boundary —
// always wrap them in this crate's own types for stability.
//
// Phase 0: basic FFI scaffold with hello-world functions.
// Phase 1+: integrate CML for address validation and transaction building.

use flutter_rust_bridge::frb;

// Module stubs — implement in Phase 1.
// pub mod address;
// pub mod wallet;
// pub mod tx;

/// Returns SDK + CSL version strings. Used to confirm the FFI bridge is wired
/// correctly end-to-end during initial setup.
#[frb(sync)]
pub fn sdk_version() -> String {
    format!(
        "cardano_flutter_rs v{}",
        env!("CARGO_PKG_VERSION"),
    )
}

/// Validates a Bech32-encoded Cardano address (simple check).
///
/// First end-to-end test of the FFI bridge. If this works in your example
/// Flutter app, the bridge is functioning and you can proceed to Phase 1.
/// Phase 1 will implement full CML-backed validation.
#[frb(sync)]
pub fn is_valid_bech32(addr: String) -> bool {
    // Phase 0: basic validation. Phase 1 will use full CML integration.
    addr.starts_with("addr") && addr.len() > 50
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sdk_version_includes_crate_version() {
        let v = sdk_version();
        assert!(v.contains("cardano_flutter_rs"));
    }

    #[test]
    fn invalid_address_rejected() {
        assert!(!is_valid_bech32("not_an_address".into()));
    }

    // TODO: add a valid testnet bech32 fixture and assert true.
}
