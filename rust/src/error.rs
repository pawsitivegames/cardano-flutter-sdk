use thiserror::Error;

#[derive(Error, Debug)]
pub enum CardanoError {
    #[error("Invalid address: {0}")]
    InvalidAddress(String),

    #[error("Invalid mnemonic: {0}")]
    InvalidMnemonic(String),

    #[error("Derivation error: {0}")]
    DerivationError(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Network error: {0}")]
    NetworkError(String),

    #[error("Invalid key: {0}")]
    InvalidKey(String),

    #[error("Invalid CBOR: {0}")]
    InvalidCbor(String),

    #[error("CSL error: {0}")]
    CslError(String),

    #[error("Insufficient lovelace: need {needed_lovelace}, have {available_lovelace}")]
    InsufficientFunds {
        needed_lovelace: u64,
        available_lovelace: u64,
    },

    #[error("Insufficient asset: policy {policy_id}, asset {asset_name}, need {needed}, have {available}")]
    InsufficientAsset {
        policy_id: String,
        asset_name: String,
        needed: u64,
        available: u64,
    },

    #[error("Change output below minimum ADA: have {residual_lovelace}, need {min_required}")]
    DustChange {
        residual_lovelace: u64,
        min_required: u64,
    },

    #[error("Coin selection error: {0}")]
    CoinSelectionError(String),

    #[error("Transaction build error: {reason}")]
    TxBuild { reason: String },

    #[error("Invalid parameter {field}: {reason}")]
    InvalidParameter { field: String, reason: String },
}
