# Property-based testing scope

The Rust crate uses `proptest` for serialization-sensitive and value-conservation
invariants. The current acceptance criteria are deliberately domain-specific:

- generated native-asset values remain canonical CSL CBOR and preserve every
  generated `(policy, asset)` entry;
- generated Plutus byte payloads and signed integer values round-trip through
  CSL without changing bytes;
- generated CIP-25 text is either one valid text value or UTF-8-safe chunks of
  at most 64 bytes that reassemble exactly;
- generated coin-selection pools conserve ADA as `target + fee + change` and
  return every asset from selected inputs for ADA-only targets; and
- generated fixed-width hardware witness bytes survive assemble → extract
  unchanged at the device boundary.

The focused command is:

```bash
cd rust
cargo test coin_selection
cargo test hardware
cargo test tx
cargo test plutus
cargo test metadata
```

The strategies are chosen so related fields shrink together where possible.
Targeted tests remain necessary for values such as `i64::MIN`, empty payloads,
maximum asset-name length, malformed CBOR, and invalid addresses because a
single exceptional value may be unlikely to appear in random sampling. A green
property suite does not prove exhaustive coverage, cryptographic correctness,
device behavior, provider behavior, or production safety.

This scope follows the current [Proptest reference
documentation](https://docs.rs/proptest/latest/proptest/) and its guidance on
strategies and shrinking. The test-layer boundary also follows Flutter's
[unit/widget/integration testing guidance](https://docs.flutter.dev/testing/overview):
property tests cover pure domain invariants, while widget, integration, device,
provider, and store evidence remain separate.
