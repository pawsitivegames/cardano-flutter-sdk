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

    #[error("CSL error: {0}")]
    CslError(String),
}
