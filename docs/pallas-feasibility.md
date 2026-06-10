# Pallas Backend-Swap Feasibility

Date: 2026-06-09

## Verdict

Pallas is feasible as a long-term native Rust backend, but not as a drop-in
replacement for the current CSL backend in `0.12.0`.

Use Pallas first for deterministic serialization/parsing parity behind the
existing conformance harness. Keep CSL as the production backend until Pallas
reproduces the frozen byte-contract outputs and the SDK owns replacement logic
for CSL builder behavior such as fee balancing, min-ADA, change, and protocol
parameter handling.

The backend-swap feasibility gate is therefore demonstrated, with this migration
strategy:

1. Add a feature-gated native Pallas conformance backend.
2. Prove parity against the existing golden vectors.
3. Extend vectors to cover transaction body CBOR, witness-set assembly,
   metadata, native scripts, minting, and Plutus script-data hash.
4. Only then replace specific CSL modules one at a time.
5. Defer full transaction building until Pallas plus SDK-owned balancing logic
   matches CSL behavior on preview testnet.

## Current Pallas Fit

Observed current crates from crates.io:

| Crate | Current version | Fit |
| --- | ---: | --- |
| `pallas` | 1.1.0 | Umbrella crate; re-exports ledger primitives, addresses, crypto, validation, txbuilder. |
| `pallas-primitives` | 1.1.0 | Era-aware CDDL-shaped CBOR primitives for Byron through Conway. Good fit for byte-parity tests. |
| `pallas-addresses` | 1.1.0 | Bech32/base58/hex Cardano address codec. Good fit for address validation and address bytes. |
| `pallas-crypto` | 1.1.0 | Blake2b and Ed25519 primitives. Important caveat: its docs mark BIP32-Ed25519 derivation and BIP39 mnemonics incomplete. |
| `pallas-txbuilder` | 1.1.0 | Conway raw transaction builder. Useful for explicit serialization, not a CSL builder equivalent. |

Pallas 1.1.0 has MSRV Rust 1.88. The local toolchain is newer (`rustc 1.95.0`),
so the SDK can compile it locally, but CI/release docs should pin or verify a
Rust toolchain before adding Pallas as a real dependency.

## SDK Surface Risk

| SDK area | Current CSL dependency | Pallas feasibility | Risk |
| --- | --- | --- | --- |
| Address validation | `csl::Address::from_bech32`, network id | `pallas-addresses::Address` covers bech32/hex/base58 and network inspection | Low |
| Address derivation | CSL BIP32 xprv/xpub, key hashes, base address creation | Address construction is available, but BIP32/BIP39 derivation is not complete in `pallas-crypto` | High |
| Values / native assets | CSL `Value`, `MultiAsset`, canonical CBOR | Pallas primitives support Conway values and multiassets | Medium |
| Tx building | CSL `TransactionBuilder`, `add_change_if_needed`, min-ADA helpers | `pallas-txbuilder::build_conway_raw` explicitly performs no automatic fee/ex-unit/balancing | High |
| Signing / witnesses | CSL xprv parsing, raw key signing, witness-set assembly | Pallas can sign with Ed25519 keys and attach vkey witnesses, but xprv compatibility must be bridged | Medium-High |
| Metadata | CSL metadata maps and auxiliary-data CBOR | Pallas primitives expose metadata and auxiliary data | Medium |
| Plutus data/hash | CSL Plutus data, cost models, script data hash | Pallas primitives expose Plutus data and Conway script-data hashing | Medium-High |
| CIP-30 `signData` | `cardano-message-signing`, not CSL-only | Keep existing `cardano-message-signing`; Pallas does not replace COSE/CIP-8 | Low |
| Hardware wallet decomposition | CSL authoritative body parse | Pallas primitives can parse bodies, but byte-preservation and field mapping need dedicated vectors | Medium |

## Why Not Swap `build_tx` First

The current SDK relies on CSL for behavior, not just serialization:

- `build_tx` uses `TransactionBuilderConfigBuilder`, `TxInputsBuilder`,
  `add_regular_input`, `add_output`, `set_ttl_bignum`, and
  `add_change_if_needed`.
- `min_ada_for_output` delegates to CSL's min-ADA calculator.
- Plutus transactions rely on specific script-data hash and cost-model behavior.
- Signing parses CSL transaction bodies, hashes canonical body bytes, and
  constructs CSL witness sets.

Pallas' builder is lower level. Its Conway builder documentation and source say
it builds with exactly the fields populated by the caller and does no automatic
balancing. Replacing CSL there without first adding SDK-owned balancing would
change user-visible fees/change outputs and risk invalid mainnet transactions.

## Recommended Implementation Plan

### Step 1: Pallas conformance backend

Add `rust/src/backend/pallas.rs` behind a disabled-by-default feature:

```toml
[features]
default = []
pallas-backend = ["pallas", "pallas-primitives", "pallas-addresses", "pallas-crypto"]
```

Start with deterministic operations only:

- `addressToHex`
- `computeBaseAddress`
- `valueToCbor`
- `plutusDataInt`
- `plutusDataBytes`
- `plutusDataConstr`
- `plutusDataList`
- `assembleVkeyWitnessSet`

Do not start with mnemonic derivation or full transaction building.

### Step 2: Expand golden vectors

The current CSL/CML conformance harness is the right migration contract. Add
native Pallas coverage for:

- transaction body CBOR for ADA-only and multi-asset transfers
- witness-set CBOR with one and two vkey witnesses
- auxiliary data / CIP-25 metadata
- native script policy id
- mint field ordering
- Plutus datum CBOR
- script-data hash for V1/V2/V3 cost-model cases
- hardware-wallet body decomposition round-trip

### Step 3: Preserve key boundary compatibility

Keep CSL-derived bech32 `xprv`/`xpub` compatibility until a dedicated Cardano
BIP32 implementation is selected or Pallas fills that gap. This is required
because the Dart API currently exposes CSL-style account/payment/stake keys,
and CIP-1852 derivation is user-visible.

### Step 4: Replace modules incrementally

Recommended order:

1. Address parsing and address bytes.
2. Value and Plutus data serialization helpers.
3. Metadata and native script serialization.
4. Witness-set assembly with externally supplied public keys/signatures.
5. Transaction body parsing/decomposition.
6. Transaction building only after SDK-owned balancing/min-ADA is implemented
   and preview testnet submission passes.

## Decision

Pallas should stay on the roadmap and can be adopted safely, but the next
engineering milestone is a feature-gated conformance backend, not a production
backend flip.

This satisfies the `0.12.0` feasibility gate because the migration surface,
blockers, and first safe implementation step are now identified against the
current Pallas 1.1.0 API and the SDK's actual CSL usage.

