//! Transaction metadata: CIP-25 (NFT standard) and CIP-68 (datum metadata).
//!
//! Both functions return auxiliary-data CBOR hex that can be passed directly
//! to `build_mint_tx` as `aux_data_cbor_hex` and to `sign_tx_with_metadata`.

use cardano_serialization_lib as csl;
use flutter_rust_bridge::frb;

use crate::error::CardanoError;
use crate::tx::hex_to_bytes;

// ── FFI-visible types ────────────────────────────────────────────────────────

/// A single NFT asset within a CIP-25 policy metadata block.
#[derive(Clone, Debug)]
pub struct Cip25Asset {
    /// Hex-encoded asset name bytes (same bytes used in `MintSpec::assets`).
    pub asset_name_hex: String,
    /// Human-readable display name.
    pub name: String,
    /// Token image URI, e.g. `"ipfs://Qm..."` or `"https://..."`.
    pub image: String,
    /// Optional MIME type, e.g. `"image/png"`.
    pub media_type: Option<String>,
    /// Optional description text.
    pub description: Option<String>,
}

/// All NFT assets under one minting policy for CIP-25.
#[derive(Clone, Debug)]
pub struct Cip25Policy {
    /// 28-byte policy ID in lowercase hex (use `compute_policy_id`).
    pub policy_id_hex: String,
    pub assets: Vec<Cip25Asset>,
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn text_datum(s: &str) -> Result<csl::TransactionMetadatum, CardanoError> {
    csl::TransactionMetadatum::new_text(s.to_string())
        .map_err(|e| CardanoError::CslError(format!("{:?}", e)))
}

/// CIP-25 metadatum for a value string. Transaction metadata text strings are
/// capped at 64 **bytes**, so CIP-25 specifies that longer values (e.g. a long
/// `ipfs://`/`https://` image URI or `description`) are encoded as an array of
/// ≤64-byte string chunks. Short values stay a plain text string.
///
/// Chunks are split on UTF-8 character boundaries so every piece is itself valid
/// UTF-8 (never splitting a multi-byte codepoint), and wallets reconstruct the
/// value by concatenating the chunks in order.
fn text_or_chunks(s: &str) -> Result<csl::TransactionMetadatum, CardanoError> {
    const MAX: usize = 64;
    if s.len() <= MAX {
        return text_datum(s);
    }
    let mut list = csl::MetadataList::new();
    let mut chunk = String::new();
    for ch in s.chars() {
        if chunk.len() + ch.len_utf8() > MAX {
            list.add(&text_datum(&chunk)?);
            chunk.clear();
        }
        chunk.push(ch);
    }
    if !chunk.is_empty() {
        list.add(&text_datum(&chunk)?);
    }
    Ok(csl::TransactionMetadatum::new_list(&list))
}

// ── CIP-25 ───────────────────────────────────────────────────────────────────

/// Build CIP-25 v2 NFT auxiliary data (label 721) and return its CBOR hex.
///
/// Pass the result directly to `build_mint_tx` as `aux_data_cbor_hex`.
///
/// # Metadata structure
/// ```text
/// { 721: { "<policy_id>": { "<asset_name_utf8>": {
///   "name": "...",
///   "image": "ipfs://...",
///   "mediaType": "image/png",   -- optional
///   "description": "...",        -- optional
///   "version": 2
/// } } } }
/// ```
///
/// # Errors
/// - `InvalidParameter` if `asset_name_hex` is not valid UTF-8
/// - `CslError` if CSL metadata construction fails
#[frb(sync)]
pub fn build_cip25_metadata(policies: Vec<Cip25Policy>) -> Result<String, CardanoError> {
    let label = csl::BigNum::from(721u64);
    let mut policy_map = csl::MetadataMap::new();

    for policy in &policies {
        let mut asset_map = csl::MetadataMap::new();
        for asset in &policy.assets {
            let mut fields = csl::MetadataMap::new();

            fields.insert(&text_datum("name")?, &text_or_chunks(&asset.name)?);
            fields.insert(&text_datum("image")?, &text_or_chunks(&asset.image)?);

            if let Some(ref mt) = asset.media_type {
                // MIME types are always short; a single text string is correct.
                fields.insert(&text_datum("mediaType")?, &text_datum(mt)?);
            }
            if let Some(ref desc) = asset.description {
                fields.insert(&text_datum("description")?, &text_or_chunks(desc)?);
            }
            // CIP-25 v2 version field
            fields.insert(
                &text_datum("version")?,
                &csl::TransactionMetadatum::new_int(&csl::Int::new_i32(2)),
            );

            // Key is the UTF-8 string representation of the asset name bytes.
            let asset_name_bytes = hex_to_bytes(&asset.asset_name_hex)?;
            let asset_name_str = String::from_utf8(asset_name_bytes).map_err(|e| {
                CardanoError::InvalidParameter {
                    field: "asset_name_hex".to_string(),
                    reason: format!("Asset name bytes are not valid UTF-8: {}", e),
                }
            })?;

            asset_map.insert(
                &text_datum(&asset_name_str)?,
                &csl::TransactionMetadatum::new_map(&fields),
            );
        }

        policy_map.insert(
            &text_datum(&policy.policy_id_hex)?,
            &csl::TransactionMetadatum::new_map(&asset_map),
        );
    }

    let mut general_metadata = csl::GeneralTransactionMetadata::new();
    general_metadata.insert(&label, &csl::TransactionMetadatum::new_map(&policy_map));

    let mut aux_data = csl::AuxiliaryData::new();
    aux_data.set_metadata(&general_metadata);

    Ok(hex::encode(aux_data.to_bytes()))
}

// ── CIP-68 ───────────────────────────────────────────────────────────────────

/// Build a CIP-68 reference-token inline datum (Constr 0 [ fields_map, version ]).
///
/// CIP-68 stores token metadata as a Plutus datum on the (100) reference token
/// instead of in transaction metadata, enabling on-chain datum updates.
///
/// # Returns
/// `PlutusData` CBOR hex suitable for use as an inline datum.
///
/// # Structure
/// ```text
/// Constr 0 [
///   Map { "name"→bytes, "image"→bytes, "mediaType"→bytes, "description"→bytes },
///   Int(version)
/// ]
/// ```
#[frb(sync)]
pub fn build_cip68_datum(
    name: String,
    image: String,
    media_type: Option<String>,
    description: Option<String>,
    version: u64,
) -> Result<String, CardanoError> {
    fn insert_bytes(map: &mut csl::PlutusMap, key: &str, val: &str) {
        let mut vals = csl::PlutusMapValues::new();
        vals.add(&csl::PlutusData::new_bytes(val.as_bytes().to_vec()));
        map.insert(&csl::PlutusData::new_bytes(key.as_bytes().to_vec()), &vals);
    }

    let mut fields_map = csl::PlutusMap::new();
    insert_bytes(&mut fields_map, "name", &name);
    insert_bytes(&mut fields_map, "image", &image);
    if let Some(ref mt) = media_type {
        insert_bytes(&mut fields_map, "mediaType", mt);
    }
    if let Some(ref desc) = description {
        insert_bytes(&mut fields_map, "description", desc);
    }

    let metadata_datum = csl::PlutusData::new_map(&fields_map);
    let version_datum = csl::PlutusData::new_integer(
        &csl::BigInt::from_str(&version.to_string())
            .map_err(|e| CardanoError::CslError(format!("{:?}", e)))?,
    );

    let mut list = csl::PlutusList::new();
    list.add(&metadata_datum);
    list.add(&version_datum);

    let constr = csl::ConstrPlutusData::new(&csl::BigNum::from(0u64), &list);
    let datum = csl::PlutusData::new_constr_plutus_data(&constr);

    Ok(hex::encode(datum.to_bytes()))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn test_policies() -> Vec<Cip25Policy> {
        vec![Cip25Policy {
            policy_id_hex: "a0".repeat(28),
            assets: vec![Cip25Asset {
                asset_name_hex: hex::encode("TestNFT"),
                name: "Test NFT #1".to_string(),
                image: "ipfs://QmTestHash123".to_string(),
                media_type: Some("image/png".to_string()),
                description: Some("A test NFT for Phase 3".to_string()),
            }],
        }]
    }

    #[test]
    fn cip25_metadata_roundtrips_as_aux_data() {
        let hex = build_cip25_metadata(test_policies()).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        csl::AuxiliaryData::from_bytes(bytes).expect("Must deserialise as AuxiliaryData");
    }

    #[test]
    fn cip25_metadata_has_label_721() {
        let hex = build_cip25_metadata(test_policies()).unwrap();
        let bytes = hex::decode(&hex).unwrap();
        let aux = csl::AuxiliaryData::from_bytes(bytes).unwrap();
        let metadata = aux.metadata().expect("AuxiliaryData must have metadata");
        let key = csl::BigNum::from(721u64);
        assert!(
            metadata.get(&key).is_some(),
            "Metadata must contain label 721"
        );
    }

    #[test]
    fn cip25_metadata_multiple_policies() {
        let policies = vec![
            Cip25Policy {
                policy_id_hex: "aa".repeat(28),
                assets: vec![Cip25Asset {
                    asset_name_hex: hex::encode("Alpha"),
                    name: "Alpha".to_string(),
                    image: "ipfs://Qm1".to_string(),
                    media_type: None,
                    description: None,
                }],
            },
            Cip25Policy {
                policy_id_hex: "bb".repeat(28),
                assets: vec![Cip25Asset {
                    asset_name_hex: hex::encode("Beta"),
                    name: "Beta".to_string(),
                    image: "ipfs://Qm2".to_string(),
                    media_type: Some("image/jpeg".to_string()),
                    description: Some("Beta NFT".to_string()),
                }],
            },
        ];
        let hex = build_cip25_metadata(policies).unwrap();
        assert!(!hex.is_empty());
    }

    /// Regression: a CIP-25 `image` URI longer than 64 bytes must be encoded as
    /// an array of ≤64-byte chunks (per the spec), not rejected. The old code
    /// called `new_text` directly, which errors for strings > 64 bytes — so a
    /// normal long `ipfs://`/`https://` image URI could not be minted.
    #[test]
    fn cip25_long_image_uri_is_chunked() {
        let long_image = format!("ipfs://{}", "Q".repeat(90)); // 97 bytes > 64
        assert!(long_image.len() > 64);

        let policies = vec![Cip25Policy {
            policy_id_hex: "a0".repeat(28),
            assets: vec![Cip25Asset {
                asset_name_hex: hex::encode("LongNFT"),
                name: "Long NFT".to_string(),
                image: long_image.clone(),
                media_type: Some("image/png".to_string()),
                description: None,
            }],
        }];

        let hex =
            build_cip25_metadata(policies).expect("long image URI must be chunked, not rejected");
        let bytes = hex::decode(&hex).unwrap();
        let aux = csl::AuxiliaryData::from_bytes(bytes).expect("must deserialise");

        // Navigate 721 → policy → asset → "image".
        let md = aux.metadata().expect("has metadata");
        let top = md.get(&csl::BigNum::from(721u64)).expect("721 present");
        let policy_map = top.as_map().expect("721 value is a map");
        let policy_val = policy_map
            .get(&text_datum(&"a0".repeat(28)).unwrap())
            .expect("policy present");
        let asset_map = policy_val.as_map().expect("policy value is a map");
        let asset_val = asset_map
            .get(&text_datum("LongNFT").unwrap())
            .expect("asset present");
        let fields = asset_val.as_map().expect("asset value is a map");
        let image = fields
            .get(&text_datum("image").unwrap())
            .expect("image present");

        // The image must be a LIST of chunks, each ≤64 bytes, concatenating back
        // to the original URI.
        let list = image
            .as_list()
            .expect("image must be a metadata list when > 64 bytes");
        assert!(
            list.len() >= 2,
            "long URI should split into multiple chunks"
        );

        let mut reassembled = String::new();
        for i in 0..list.len() {
            let chunk = list.get(i).as_text().expect("each chunk is text");
            assert!(
                chunk.len() <= 64,
                "each chunk must be ≤64 bytes, got {}",
                chunk.len()
            );
            reassembled.push_str(&chunk);
        }
        assert_eq!(
            reassembled, long_image,
            "chunks must concatenate to the original URI"
        );
    }

    /// A short value (≤64 bytes) stays a single text string, not a list.
    #[test]
    fn cip25_short_image_uri_stays_text() {
        let policies = vec![Cip25Policy {
            policy_id_hex: "a0".repeat(28),
            assets: vec![Cip25Asset {
                asset_name_hex: hex::encode("ShortNFT"),
                name: "Short NFT".to_string(),
                image: "ipfs://QmShort".to_string(),
                media_type: None,
                description: None,
            }],
        }];
        let hex = build_cip25_metadata(policies).unwrap();
        let aux = csl::AuxiliaryData::from_bytes(hex::decode(&hex).unwrap()).unwrap();
        let md = aux.metadata().unwrap();
        let top = md.get(&csl::BigNum::from(721u64)).unwrap();
        let policy_val = top
            .as_map()
            .unwrap()
            .get(&text_datum(&"a0".repeat(28)).unwrap())
            .unwrap();
        let fields = policy_val
            .as_map()
            .unwrap()
            .get(&text_datum("ShortNFT").unwrap())
            .unwrap()
            .as_map()
            .unwrap();
        let image = fields.get(&text_datum("image").unwrap()).unwrap();
        assert!(
            image.as_text().is_ok(),
            "a short image URI must stay a single text string"
        );
    }

    #[test]
    fn cip68_datum_roundtrips_as_plutus_data() {
        let hex = build_cip68_datum(
            "My NFT".to_string(),
            "ipfs://QmTest".to_string(),
            Some("image/png".to_string()),
            Some("A CIP-68 NFT".to_string()),
            1,
        )
        .unwrap();
        let bytes = hex::decode(&hex).unwrap();
        csl::PlutusData::from_bytes(bytes).expect("Must deserialise as PlutusData");
    }

    #[test]
    fn cip68_datum_minimal_fields() {
        let hex = build_cip68_datum(
            "Minimal".to_string(),
            "https://example.com/img.png".to_string(),
            None,
            None,
            1,
        )
        .unwrap();
        let bytes = hex::decode(&hex).unwrap();
        csl::PlutusData::from_bytes(bytes).expect("Must deserialise as PlutusData");
    }
}
