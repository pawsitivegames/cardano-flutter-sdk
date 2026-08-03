# Fixture data contract

The checked-in JSON fixtures are executable interoperability inputs, not
production chain data. Their quality contract is intentionally scoped to the
consumers that load them:

- `dart/test/conformance/golden_cbor.json` is the frozen CSL↔CML byte-parity
  corpus. Every record has a stable unique `id`, an allowed operation and
  category, the exact operation input shape, lowercase even-length hex where a
  field represents bytes, and a non-empty expected result.
- `dart/test/fixtures/cross_wallet_signatures.json` contains real third-party
  CIP-30 `signData` output. It retains dataset-level provenance in `_README`
  and `_schema`, requires at least one active fixture, validates the declared
  network and byte fields, and is exercised by both acceptance and
  tampered-payload rejection tests.
- `tools/cose-interop/vectors.json` is generated reference-library output used
  to maintain the Rust interop regression vectors. It is test material derived
  from the documented Emurgo libraries and shared fixture mnemonic, not a user
  secret or a claim about live chain state. Dart contract tests validate its
  source, shared 12-word fixture, named vector keys, and lowercase even-length
  hex shape; a Rust test also compares both named vectors with embedded
  constants, so regeneration cannot silently leave the checked-in source and
  executable gates out of sync.

The executable gate is:

```bash
cd dart
flutter test test/fixture_contract_test.dart \
  test/conformance_test.dart test/cross_wallet_verify_test.dart
cd ../rust
cargo test cip30::tests::test_interop_json_matches_embedded_constants
```

These checks establish parseability, structure, identity, and consumer
integrity. They do not establish that an external wallet remains available,
that a fixture represents current chain state, or that every wallet vendor is
covered. New or changed vectors still require the backend conformance and
cross-wallet verification gates.

The contract follows the contextual quality and provenance approach in the
[W3C Data on the Web Best Practices](https://www.w3.org/TR/dwbp/) and uses
JSON's machine-readable structure in the spirit of the current
[JSON Schema specification](https://json-schema.org/specification); the
repository uses consumer-aligned Dart assertions rather than claiming formal
JSON Schema compliance.
