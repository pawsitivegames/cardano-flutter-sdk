# Feature verification ledger

> Last reviewed: 2026-08-02

This ledger records the contract, failure behavior, acceptance criteria, and
evidence boundary for each user-facing SDK or example feature. A passing local
test does not imply device, provider, store, or production verification.

## Evidence labels

- **L — local:** deterministic unit, widget, analyzer, build, or browser-harness
  evidence available in this checkout.
- **D — device:** a physical iOS/Android/macOS runtime journey.
- **P — provider:** a live Blockfrost or other chain-service request.
- **S — store:** App Store / Play Store packaging and review acceptance.
- **R — production:** a real external dApp or deployed production journey.

Flutter's current testing guidance recommends many fast unit/widget tests plus
integration tests for important complete use cases. The ledger therefore keeps
the test pyramid and the runtime evidence separate. CIP-30 features additionally
follow the privacy and approval boundary in the [CIP-30
specification](https://cips.cardano.org/cip/CIP-0030): wallet access is consented,
keys remain with the wallet, and signing is an explicit request.

## 1. Package entrypoints and backend boundary

**Contract:** native consumers import `cardano_flutter_rs.dart` and get CSL/Rust
FFI; web consumers import `cardano_flutter_rs_web.dart` and get only the scoped
CML-JS/provider surface. The web entrypoint must not pull in `dart:ffi`.

**Edges and failures:** wrong entrypoint or missing host CML/WASM must fail at
compile/initialization time; a backend byte mismatch must fail the conformance
gate rather than be normalized.

**Acceptance and evidence:** Dart analysis and native tests pass; the web
entrypoint compiles, the browser harness reports `PASS 32 FAIL 0`, and the
scoped wallet harness reports `PASS 19 FAIL 0`. **Status: L + browser verified;
host deployment remains a consumer responsibility.**

## 2. Keys, addresses, and HD discovery

**Contract:** derive deterministic account/payment/stake keys from a valid
mnemonic, passphrase, account index, and network; produce valid network-specific
addresses; scan external/change accounts with the documented gap limit.

**Edges and failures:** invalid mnemonic/key/xpub, malformed address, wrong
network, account/index changes, passphrase changes, and consecutive unused
addresses must produce rejection or a deterministic scan stop—not a plausible
but wrong result.

**Acceptance and evidence:** `dart/test/widget_test.dart`,
`dart/test/hd_wallet_test.dart`, `dart/test/hardware_test.dart`, and golden
vectors cover deterministic derivation, invalid inputs, network prefixes,
account gaps, and public soft derivation. iPhone 13 evidence is historical in
the release plan; the 2026-08-02 CPH2841 smoke run added Android physical
evidence for JNI load, version, address validation, and key derivation. **Status:
L; iOS D historical; Android physical smoke D verified; store/provider S pending.**

## 3. Transaction building, signing, and coin selection

**Contract:** build valid Cardano transaction bodies, preserve ADA and every
native asset, calculate/sign the canonical body, and assemble witnesses without
duplicating or dropping change.

**Edges and failures:** empty inputs/outputs, malformed CBOR/hex, insufficient
funds, multi-asset change, TTL/network mismatch, witness-size effects, and
unsupported script features must fail explicitly or produce conserved values.

**Acceptance and evidence:** Rust transaction/coin-selection tests,
`dart/test/widget_test.dart`, `dart/test/cip30_test.dart`, and
`example/integration_test/bugfix_verification_test.dart` cover local invariants
and regression cases. The documented macOS preview send is historical D+P
evidence; the current live send requires `BLOCKFROST_PROJECT_ID`. **Status: L;
historical macOS D+P; current provider/production runs external.**

## 4. Plutus data, metadata, minting, and native scripts

**Contract:** encode valid deterministic Plutus/CBOR data, CIP-25/CIP-68
metadata, native scripts, policy IDs, and mint transactions while preserving
large/negative quantities where the domain permits them.

**Edges and failures:** empty/invalid hex, malformed CBOR, nested data, long
metadata URIs, empty inputs/specs, burning, and integer-boundary values must be
covered by explicit error or round-trip assertions.

**Acceptance and evidence:** `dart/test/plutus_test.dart`,
`dart/test/metadata_test.dart`, `dart/test/minting_test.dart`, Rust property
tests, and `example/integration_test/bugfix_verification_test.dart` provide L
coverage. Preview minting is in `example/integration_test/live_mint_test.dart`
but is conditional on provider credentials and spends testnet funds. **Status:
L verified; current P/D production-like mint remains external.**

## 5. Staking builders and reward operations

**Contract:** produce registration, delegation, withdrawal, and deregistration
transactions with the correct stake credentials, pool identifiers, deposits,
rewards, and change.

**Edges and failures:** malformed hashes/pool IDs, empty inputs, missing rewards,
network mismatch, and invalid protocol parameters must surface typed failures or
produce a transaction the node accepts.

**Acceptance and evidence:** wrapper validation and builder failure behavior are
covered in `dart/test/widget_test.dart` and Rust staking tests; the dated plan
records historical preview on-chain staking checks. A fresh provider-backed
transaction requires credentials and intentional testnet spending. **Status: L;
historical P/D; current live recheck external.**

## 6. Legacy message signing

**Contract:** the retained `signMessage`/`verifyMessage` API signs and verifies
the legacy CBOR message container with payment or stake material. It is not the
CIP-8/CIP-30 wallet-interoperability format; callers needing that contract use
`cip30SignData`/`cip30VerifyData`.

**Edges and failures:** malformed message hex, forged key/address claims, wrong
expected address, tampered container, invalid key, and valid payment/stake
round-trips must be rejected or accepted deterministically.

**Acceptance and evidence:** `dart/test/message_test.dart` and Rust message
tests cover round-trip, identity binding, wrong-address, and malformed-input
behavior. **Status: L verified as legacy compatibility; R wallet interop is not
claimed.**

## 7. At-rest seed encryption

**Contract:** encrypt and decrypt arbitrary UTF-8 secrets using the documented
CFS1 format, Argon2id parameters, random salt/nonce, and authenticated
XChaCha20-Poly1305; wrong credentials or altered ciphertext fail closed.

**Edges and failures:** empty/unicode secrets, wrong password, tampering, bad
magic/hex, invalid KDF parameters, repeated encryption, and device secure-store
absence must be distinguishable and safe.

**Acceptance and evidence:** `dart/test/seed_encryption_test.dart` covers the
cryptographic contract locally; `example/integration_test/seed_vault_test.dart`
covers Keychain/Keystore composition on a real target when run. iPhone 13
evidence is historical; the Android smoke run did not exercise secure storage.
**Status: L; historical iOS D; Android secure-store D/S external.**

## 8. Native CIP-30 wallet

**Contract:** expose CIP-30-shaped network ID, UTxOs, balance, change/used/
unused/reward addresses, transaction signing, data signing, and submission. Used
status is based on address history, not merely current UTxOs; `signData` binds
the COSE key to the protected-header address.

**Edges and failures:** empty wallet, spent-but-used address, native assets,
passphrases, invalid/mismatched addresses, malformed hex/CBOR, wrong payload,
unknown signer address, provider errors, user refusal, and network mismatch must
not yield a false successful wallet result.

**Acceptance and evidence:** `dart/test/cip30_test.dart`,
`dart/test/cross_wallet_verify_test.dart`, fixture-contract tests, Rust tests,
golden vectors, and the documented Eternl fixture provide L evidence. Live
Blockfrost reads/submission are conditional P evidence; no R claim is made.
**Status: L + external fixture verified; current P/D/S/R remain separate.**

## 9. Scoped web CIP-30 wallet

**Contract:** `WebCip30Wallet` matches the native scoped CIP-30 behavior using
CML-JS, including passphrases, address encodings, balance/UTxO serialization,
`signData`/`verifyData`, `signTx`, and submission seams.

**Edges and failures:** missing host CML/MS/WASM or mnemonic bridge, malformed
hex/CBOR, unknown address, wrong payload, tampering, and provider failure must
fail explicitly; unsupported full transaction building must remain out of scope.

**Acceptance and evidence:** `tool/web_conformance` compiles the Dart JS and
runs both deterministic harnesses in Chromium: conformance `32/32` and wallet
`19/19`. **Status: L browser verified for the stated scope; host/provider and
production deployment remain external.**

## 10. Blockfrost provider

**Contract:** map REST responses to typed UTxO, protocol, account, address,
pool, transaction-status, retry, and submission models; select the requested
network and include the project header.

**Edges and failures:** 400/401/403/404/429/500, missing fields, pagination,
rate limits, retries, pending/confirmed transitions, timeouts, and malformed
responses must map to typed errors or documented empty results.

**Acceptance and evidence:** `dart/test/providers/blockfrost_test.dart` uses
mock HTTP responses for parsing, errors, retries, headers, paging, and polling.
Live tests are explicitly skipped unless `BLOCKFROST_PROJECT_ID` is supplied;
the credential, provider availability, and chain state are **P external**.
**Status: L verified; current P/R not claimed.**

## 11. CIP-45 transport core and example transport

**Contract:** parse/build the `web+cardano://` connection URI, announce the
CIP-30 method surface, dispatch supported calls, reject invalid/unsupported
methods, and preserve request/response correlation through the chosen transport.

**Edges and failures:** wrong scheme/authority, missing identifier, whitespace,
missing/null parameters, unsupported methods, tracker/WebRTC disconnect, timeout,
and callback error responses must be explicit and recoverable.

**Acceptance and evidence:** `dart/test/cip45_test.dart` covers the pure
protocol core and dispatch failures. The WebView/Bugout two-peer path has dated
iOS live evidence; Android-device and native WebRTC two-peer runs remain
external. **Status: L verified core; historical iOS D; Android/two-peer current
verification pending.**

## 12. Hardware wallet seam

**Contract:** derive watch-only addresses from an account xpub, decompose a
supported payment body, delegate signing to a device adapter, re-derive witness
keys, assemble witnesses, and expose a CIP-30-shaped read surface without ever
exporting private keys.

**Edges and failures:** malformed xpub/CBOR, unsupported certificates/minting/
withdrawals/reference inputs, wrong derivation path, missing device, rejected
approval, output/token ordering, partial signing, and invalid witness data must
fail closed.

**Acceptance and evidence:** `dart/test/hardware_test.dart` and Rust hardware
tests use real software signatures plus a mock device and prove byte-identical
assembly. No physical Ledger signing or on-device UX is claimed; the adapter
remains `@experimental` pending the checklist in `docs/hardware-wallets.md`.
**Status: L verified seam; D/S/R blocked on hardware and external review.**

## 13. Example app and release journeys

**Contract:** the example exposes understandable first-run actions, remains
accessible at small viewport sizes, and routes to the scoped demos without
claiming unverified platform capabilities.

**Edges and failures:** narrow layouts, missing provider configuration, invalid
input, loading/error states, platform permissions, absent hardware, and absent
WASM/FFI artifacts must be visible and recoverable.

**Acceptance and evidence:** `example/test/widget_test.dart` checks the home
journey and tap-target guidance, and the diagnostics regression covers injected
failure → visible recovery state → retry success. The web target builds; local
example analysis and integration-test sources cover send, mint, seed, packaging,
and bug-fix journeys. iOS/macOS results and Android emulator/16 KB results are
separate dated evidence; the 2026-08-02 CPH2841 run adds physical smoke
evidence, while Play Store acceptance remains open. **Status: L; historical
iOS/macOS D, Android physical smoke D, and store/provider S/R pending.**

Current local evidence: `PUB_CACHE=/tmp/cardano_flutter_sdk_pub_cache flutter
test test/widget_test.dart` — 2 passed, including the failure/retry journey;
`flutter analyze --no-fatal-warnings` — no errors, with 13 known warnings for
explicitly experimental hardware and scoped web APIs.

## Ledger decision

The feature pass found and completed one actionable contract defect: the legacy
message API and example falsely described a non-COSE container as CIP-8/COSE
Sign1. The public tests, generated docs, wrapper docs, example labels, and plan
now distinguish legacy compatibility from the interoperable CIP-30 path.

Remaining entries are either locally verified within their stated scope or
explicitly blocked by credentials, physical hardware, store acceptance, or a
real production consumer. Those external conditions are not silently converted
into local pass claims.
