//! Phase 5b — at-rest encryption for wallet recovery secrets.
//!
//! Argon2id (memory-hard KDF) derives a 32-byte key from the user's password +
//! a random salt; XChaCha20-Poly1305 (AEAD) encrypts the secret under that key
//! with a random 192-bit nonce. The result is a self-describing, versioned
//! container (see [`docs/seed-encryption.md`]) returned as a hex string.
//!
//! Design + threat model: `docs/seed-encryption.md`. All cryptography lives here
//! in Rust — the Dart side never implements crypto.

use crate::error::CardanoError;
use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::rand_core::RngCore;
use chacha20poly1305::aead::{Aead, OsRng, Payload};
use chacha20poly1305::{KeyInit, XChaCha20Poly1305, XNonce};
use flutter_rust_bridge::frb;
use zeroize::Zeroizing;

const MAGIC: &[u8; 4] = b"CFS1";
const VERSION: u8 = 0x01;
const KDF_ID_ARGON2ID: u8 = 0x01;
const KEY_LEN: usize = 32;
const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 24;

/// Default Argon2id cost: 64 MiB memory, 3 passes, single lane.
/// Above OWASP's 2024 floor while staying ~sub-second on an iPhone 13.
/// Tune with [`benchmark_kdf`]; override with [`encrypt_seed_with_params`].
const DEFAULT_MEM_KIB: u32 = 64 * 1024;
const DEFAULT_ITERS: u32 = 3;
const DEFAULT_PARALLELISM: u32 = 1;

/// Sane bounds on Argon2id cost parameters. Enforced on BOTH encrypt (so we never
/// write an absurd blob) and decrypt (so an attacker-supplied blob cannot make
/// `decrypt_seed` attempt a multi-terabyte allocation / hang — the KDF runs before
/// the AEAD tag is checked, so this guard must precede `derive_key`). See SEED-1 in
/// `docs/security-review-phase7.md`.
const MIN_MEM_KIB: u32 = 8; // Argon2 itself requires >= 8 * parallelism
const MAX_MEM_KIB: u32 = 2 * 1024 * 1024; // 2 GiB ceiling
const MAX_ITERS: u32 = 100;
const MAX_PARALLELISM: u32 = 16;

/// Reject out-of-range Argon2id parameters before they reach the KDF.
fn validate_kdf_params(p: &KdfParams) -> Result<(), CardanoError> {
    let bad = |field: &str, reason: String| CardanoError::InvalidParameter {
        field: field.to_string(),
        reason,
    };
    if p.mem_kib < MIN_MEM_KIB || p.mem_kib > MAX_MEM_KIB {
        return Err(bad(
            "mem_kib",
            format!(
                "Argon2 memory {} KiB out of range [{}, {}]",
                p.mem_kib, MIN_MEM_KIB, MAX_MEM_KIB
            ),
        ));
    }
    if p.iterations == 0 || p.iterations > MAX_ITERS {
        return Err(bad(
            "iterations",
            format!(
                "Argon2 iterations {} out of range [1, {}]",
                p.iterations, MAX_ITERS
            ),
        ));
    }
    if p.parallelism == 0 || p.parallelism > MAX_PARALLELISM {
        return Err(bad(
            "parallelism",
            format!(
                "Argon2 parallelism {} out of range [1, {}]",
                p.parallelism, MAX_PARALLELISM
            ),
        ));
    }
    Ok(())
}

/// Argon2id cost parameters. Embedded in every ciphertext header so decryption
/// is self-contained (it always uses the params the blob was written with).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KdfParams {
    /// Memory cost in KiB.
    pub mem_kib: u32,
    /// Time cost (number of passes).
    pub iterations: u32,
    /// Degree of parallelism (lanes).
    pub parallelism: u32,
}

impl Default for KdfParams {
    fn default() -> Self {
        KdfParams {
            mem_kib: DEFAULT_MEM_KIB,
            iterations: DEFAULT_ITERS,
            parallelism: DEFAULT_PARALLELISM,
        }
    }
}

/// The recommended default Argon2id parameters for this build.
#[frb(sync)]
pub fn default_kdf_params() -> KdfParams {
    KdfParams::default()
}

/// Result of [`encrypt_seed`] — the at-rest container plus an echo of the KDF
/// parameters that were actually used (also embedded in `blob_hex`).
#[derive(Clone, Debug)]
pub struct EncryptedSeed {
    /// Versioned, self-describing `CFS1` container, hex-encoded. Store this.
    pub blob_hex: String,
    /// KDF parameters used (informational; authoritative copy is in `blob_hex`).
    pub kdf: KdfParams,
}

/// Encrypt a recovery secret (e.g. a BIP-39 mnemonic) with the default,
/// device-appropriate Argon2id parameters.
///
/// - `secret`: the plaintext to protect (mnemonic phrase or other UTF-8 secret).
/// - `password`: the user's password; the sole gate to recovery.
///
/// Returns a hex container safe to persist. Salt and nonce are freshly random
/// per call, so encrypting the same secret twice yields different blobs.
#[frb(sync)]
pub fn encrypt_seed(secret: String, password: String) -> Result<EncryptedSeed, String> {
    encrypt_seed_internal(secret.as_bytes(), password.as_bytes(), KdfParams::default())
        .map_err(|e| e.to_string())
}

/// Like [`encrypt_seed`] but with explicit Argon2id cost parameters (tune via
/// [`benchmark_kdf`]). Parameters are stored in the header, so decryption does
/// not need them supplied again.
#[frb(sync)]
pub fn encrypt_seed_with_params(
    secret: String,
    password: String,
    mem_kib: u32,
    iterations: u32,
    parallelism: u32,
) -> Result<EncryptedSeed, String> {
    let params = KdfParams {
        mem_kib,
        iterations,
        parallelism,
    };
    encrypt_seed_internal(secret.as_bytes(), password.as_bytes(), params).map_err(|e| e.to_string())
}

/// Decrypt a `CFS1` container produced by [`encrypt_seed`]. Returns the original
/// UTF-8 secret. A wrong password and a tampered blob are indistinguishable —
/// both surface as an authentication failure (fails closed, never partial).
#[frb(sync)]
pub fn decrypt_seed(blob_hex: String, password: String) -> Result<String, String> {
    decrypt_seed_internal(&blob_hex, password.as_bytes()).map_err(|e| e.to_string())
}

/// Measure the wall-clock cost (milliseconds) of the Argon2id KDF for the given
/// parameters on this device. Use to tune params to a target unlock latency.
#[frb(sync)]
pub fn benchmark_kdf(mem_kib: u32, iterations: u32, parallelism: u32) -> Result<u64, String> {
    let params = KdfParams {
        mem_kib,
        iterations,
        parallelism,
    };
    let salt = [0u8; SALT_LEN];
    let start = std::time::Instant::now();
    let _key = derive_key(b"benchmark-password", &salt, params).map_err(|e| e.to_string())?;
    Ok(start.elapsed().as_millis() as u64)
}

// ---- internals -------------------------------------------------------------

fn derive_key(
    password: &[u8],
    salt: &[u8],
    p: KdfParams,
) -> Result<Zeroizing<[u8; KEY_LEN]>, CardanoError> {
    let params =
        Params::new(p.mem_kib, p.iterations, p.parallelism, Some(KEY_LEN)).map_err(|e| {
            CardanoError::InvalidParameter {
                field: "kdf_params".to_string(),
                reason: format!("invalid Argon2 parameters: {e}"),
            }
        })?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut key = Zeroizing::new([0u8; KEY_LEN]);
    argon2
        .hash_password_into(password, salt, key.as_mut())
        .map_err(|e| CardanoError::SerializationError(format!("KDF failure: {e}")))?;
    Ok(key)
}

/// Header (everything before the ciphertext), used both as the on-disk prefix
/// and as the AEAD associated data so any tampering with params/salt/nonce fails.
fn build_header(p: KdfParams, salt: &[u8], nonce: &[u8]) -> Vec<u8> {
    let mut h = Vec::with_capacity(19 + SALT_LEN + NONCE_LEN);
    h.extend_from_slice(MAGIC);
    h.push(VERSION);
    h.push(KDF_ID_ARGON2ID);
    h.extend_from_slice(&p.mem_kib.to_le_bytes());
    h.extend_from_slice(&p.iterations.to_le_bytes());
    h.extend_from_slice(&p.parallelism.to_le_bytes());
    h.push(salt.len() as u8);
    h.extend_from_slice(salt);
    h.extend_from_slice(nonce);
    h
}

fn encrypt_seed_internal(
    secret: &[u8],
    password: &[u8],
    p: KdfParams,
) -> Result<EncryptedSeed, CardanoError> {
    // Never write a blob with out-of-range cost (mirrors the decrypt-side guard).
    validate_kdf_params(&p)?;

    let mut salt = [0u8; SALT_LEN];
    OsRng.fill_bytes(&mut salt);
    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);

    let key = derive_key(password, &salt, p)?;
    let cipher = XChaCha20Poly1305::new(key.as_ref().into());
    let nonce = XNonce::from_slice(&nonce_bytes);

    let header = build_header(p, &salt, &nonce_bytes);
    let ciphertext = cipher
        .encrypt(
            nonce,
            Payload {
                msg: secret,
                aad: &header,
            },
        )
        .map_err(|_| CardanoError::SerializationError("encryption failed".to_string()))?;

    let mut blob = header;
    blob.extend_from_slice(&ciphertext);

    Ok(EncryptedSeed {
        blob_hex: hex::encode(blob),
        kdf: p,
    })
}

fn decrypt_seed_internal(blob_hex: &str, password: &[u8]) -> Result<String, CardanoError> {
    let blob = hex::decode(blob_hex).map_err(|_| CardanoError::InvalidParameter {
        field: "blob_hex".to_string(),
        reason: "not valid hex".to_string(),
    })?;

    // Fixed prefix: magic(4) ver(1) kdf(1) mem(4) iters(4) par(4) salt_len(1) = 19
    const FIXED: usize = 19;
    if blob.len() < FIXED {
        return Err(CardanoError::InvalidCbor(
            "ciphertext too short".to_string(),
        ));
    }
    if &blob[0..4] != MAGIC {
        return Err(CardanoError::InvalidParameter {
            field: "blob".to_string(),
            reason: "bad magic (not a CFS1 container)".to_string(),
        });
    }
    if blob[4] != VERSION {
        return Err(CardanoError::InvalidParameter {
            field: "version".to_string(),
            reason: format!("unsupported container version {}", blob[4]),
        });
    }
    if blob[5] != KDF_ID_ARGON2ID {
        return Err(CardanoError::InvalidParameter {
            field: "kdf_id".to_string(),
            reason: format!("unsupported KDF id {}", blob[5]),
        });
    }
    let mem_kib = u32::from_le_bytes(blob[6..10].try_into().unwrap());
    let iterations = u32::from_le_bytes(blob[10..14].try_into().unwrap());
    let parallelism = u32::from_le_bytes(blob[14..18].try_into().unwrap());
    let salt_len = blob[18] as usize;

    // SEED-2: the salt length is a fixed invariant; reject anything else early
    // (it's AAD-bound so a wrong value would fail auth anyway, but this matches the
    // documented format and rejects malformed input before the KDF).
    if salt_len != SALT_LEN {
        return Err(CardanoError::InvalidParameter {
            field: "salt_len".to_string(),
            reason: format!("expected {}, got {}", SALT_LEN, salt_len),
        });
    }

    // SEED-1: clamp attacker-controlled KDF cost BEFORE deriving (the KDF runs
    // before the AEAD tag is verified, so this guards against a DoS blob).
    validate_kdf_params(&KdfParams {
        mem_kib,
        iterations,
        parallelism,
    })?;

    let salt_end = FIXED + salt_len;
    let nonce_end = salt_end + NONCE_LEN;
    if blob.len() < nonce_end {
        return Err(CardanoError::InvalidCbor(
            "ciphertext truncated (header)".to_string(),
        ));
    }
    let salt = &blob[FIXED..salt_end];
    let nonce_bytes = &blob[salt_end..nonce_end];
    let ciphertext = &blob[nonce_end..];

    let header = &blob[0..nonce_end]; // AAD = exact on-disk header bytes
    let params = KdfParams {
        mem_kib,
        iterations,
        parallelism,
    };
    let key = derive_key(password, salt, params)?;
    let cipher = XChaCha20Poly1305::new(key.as_ref().into());
    let nonce = XNonce::from_slice(nonce_bytes);

    let plaintext = Zeroizing::new(
        cipher
            .decrypt(
                nonce,
                Payload {
                    msg: ciphertext,
                    aad: header,
                },
            )
            .map_err(|_| {
                CardanoError::InvalidKey(
                    "decryption failed: wrong password or corrupted/tampered data".to_string(),
                )
            })?,
    );

    // Validate UTF-8 by borrowing the zeroized buffer (no extra un-zeroized Vec
    // copy), then allocate exactly one owned String for the FFI return value.
    // The returned String crosses to Dart and cannot be zeroized there — that
    // is documented in docs/seed-encryption.md as an accepted out-of-scope item.
    std::str::from_utf8(&plaintext)
        .map(|s| s.to_owned())
        .map_err(|_| {
            CardanoError::SerializationError("decrypted secret is not valid UTF-8".to_string())
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    // Fast params keep the test suite quick; production uses DEFAULT_*.
    const T_MEM: u32 = 8 * 1024; // 8 MiB
    const T_ITERS: u32 = 1;
    const T_PAR: u32 = 1;
    const MNEMONIC: &str = "test walk nut penalty hip pave soap entry language right filter choice";

    fn enc(secret: &str, pw: &str) -> EncryptedSeed {
        encrypt_seed_internal(
            secret.as_bytes(),
            pw.as_bytes(),
            KdfParams {
                mem_kib: T_MEM,
                iterations: T_ITERS,
                parallelism: T_PAR,
            },
        )
        .unwrap()
    }

    #[test]
    fn round_trip_recovers_secret() {
        let e = enc(MNEMONIC, "correct horse battery staple");
        let out = decrypt_seed_internal(&e.blob_hex, b"correct horse battery staple").unwrap();
        assert_eq!(out, MNEMONIC);
    }

    #[test]
    fn wrong_password_fails() {
        let e = enc(MNEMONIC, "right-password");
        let r = decrypt_seed_internal(&e.blob_hex, b"wrong-password");
        assert!(r.is_err());
    }

    #[test]
    fn tampered_ciphertext_fails() {
        let e = enc(MNEMONIC, "pw");
        let mut blob = hex::decode(&e.blob_hex).unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 0x01; // flip a ciphertext/tag bit
        let r = decrypt_seed_internal(&hex::encode(blob), b"pw");
        assert!(r.is_err());
    }

    #[test]
    fn tampered_kdf_params_fail() {
        // Downgrade-attack resistance: mem_kib lives at bytes 6..10 (in the AAD).
        let e = enc(MNEMONIC, "pw");
        let mut blob = hex::decode(&e.blob_hex).unwrap();
        blob[6] ^= 0xFF;
        let r = decrypt_seed_internal(&hex::encode(blob), b"pw");
        assert!(r.is_err());
    }

    #[test]
    fn distinct_salt_nonce_per_call() {
        let a = enc(MNEMONIC, "pw");
        let b = enc(MNEMONIC, "pw");
        assert_ne!(a.blob_hex, b.blob_hex, "salt+nonce must be random per call");
        // But both decrypt to the same secret.
        assert_eq!(
            decrypt_seed_internal(&a.blob_hex, b"pw").unwrap(),
            decrypt_seed_internal(&b.blob_hex, b"pw").unwrap()
        );
    }

    #[test]
    fn params_round_trip_through_header() {
        let e = enc(MNEMONIC, "pw");
        let blob = hex::decode(&e.blob_hex).unwrap();
        assert_eq!(&blob[0..4], MAGIC);
        assert_eq!(blob[4], VERSION);
        assert_eq!(blob[5], KDF_ID_ARGON2ID);
        assert_eq!(u32::from_le_bytes(blob[6..10].try_into().unwrap()), T_MEM);
        assert_eq!(
            u32::from_le_bytes(blob[10..14].try_into().unwrap()),
            T_ITERS
        );
        assert_eq!(u32::from_le_bytes(blob[14..18].try_into().unwrap()), T_PAR);
        assert_eq!(blob[18] as usize, SALT_LEN);
        // Decryption uses embedded params — caller need not supply them.
        assert_eq!(decrypt_seed_internal(&e.blob_hex, b"pw").unwrap(), MNEMONIC);
    }

    #[test]
    fn bad_magic_rejected() {
        let r = decrypt_seed_internal(&hex::encode(b"NOPEnope....."), b"pw");
        assert!(r.is_err());
    }

    #[test]
    fn non_hex_rejected() {
        let r = decrypt_seed_internal("zzzz", b"pw");
        assert!(r.is_err());
    }

    #[test]
    fn empty_secret_round_trips() {
        let e = enc("", "pw");
        assert_eq!(decrypt_seed_internal(&e.blob_hex, b"pw").unwrap(), "");
    }

    #[test]
    fn invalid_kdf_params_error() {
        // parallelism 0 is invalid for Argon2.
        let r = encrypt_seed_internal(
            MNEMONIC.as_bytes(),
            b"pw",
            KdfParams {
                mem_kib: T_MEM,
                iterations: T_ITERS,
                parallelism: 0,
            },
        );
        assert!(r.is_err());
    }

    #[test]
    fn benchmark_returns_value() {
        let ms = benchmark_kdf(T_MEM, T_ITERS, T_PAR).unwrap();
        let _ = ms; // wall-clock; just assert it ran without error
    }

    // SEED-1: a crafted blob with an absurd Argon2 memory cost must be rejected
    // BEFORE the KDF runs (no multi-terabyte allocation / hang).
    #[test]
    fn decrypt_rejects_oversized_mem_param() {
        let e = enc(MNEMONIC, "pw");
        let mut blob = hex::decode(&e.blob_hex).unwrap();
        blob[6..10].copy_from_slice(&u32::MAX.to_le_bytes()); // mem_kib = ~4 TiB
        let r = decrypt_seed_internal(&hex::encode(blob), b"pw");
        assert!(r.is_err(), "oversized mem_kib must be rejected pre-KDF");
    }

    // SEED-2: salt_len must equal the fixed invariant.
    #[test]
    fn decrypt_rejects_bad_salt_len() {
        let e = enc(MNEMONIC, "pw");
        let mut blob = hex::decode(&e.blob_hex).unwrap();
        blob[18] = 15; // != SALT_LEN (16)
        let r = decrypt_seed_internal(&hex::encode(blob), b"pw");
        assert!(r.is_err(), "salt_len != 16 must be rejected");
    }

    // SEED-1 (encrypt side): never write a blob with out-of-range cost.
    #[test]
    fn encrypt_rejects_oversized_mem_param() {
        let r = encrypt_seed_internal(
            MNEMONIC.as_bytes(),
            b"pw",
            KdfParams {
                mem_kib: MAX_MEM_KIB + 1,
                iterations: T_ITERS,
                parallelism: T_PAR,
            },
        );
        assert!(r.is_err());
    }
}
