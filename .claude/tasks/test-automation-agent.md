# Task: Test Automation Agent — Unit & Integration Tests

**Assigned to:** Test Automation Agent  
**Duration:** ~5 hours  
**Deliverable:** Full Rust unit tests, Dart unit tests, Cardano testnet integration tests, all passing  
**Blocked by:** Rust Scaffolding Agent (Rust code) + Dart Bindings Agent (Dart wrappers)  
**Coordinator:** Main chat

## Objective

Write comprehensive unit tests for Rust and Dart code, plus integration tests against Cardano testnet preview. Ensure test fixtures are in place and all tests pass locally.

## Scope

### 1. Rust Unit Tests
- **Location:** `rust/cardano_flutter_rs/tests/integration_tests.rs` or inline in `src/lib.rs`
- **Coverage:** Every public function from the 3 PoC implementations
- **Test structure:** At least 2 tests per function (happy path + error case)
- **Examples:**
  ```rust
  #[test]
  fn test_validate_address_valid_mainnet() {
      let result = validate_address("addr1...");
      assert!(result.is_ok());
  }
  
  #[test]
  fn test_validate_address_invalid_checksum() {
      let result = validate_address("addr1bad");
      assert!(result.is_err());
  }
  ```
- **Fixtures:** Use known test addresses from Cardano docs or create them in `tests/fixtures/addresses.txt`
- **Run:** `cargo test` must pass
- **Linting:** No clippy warnings in tests (`cargo clippy --tests`)

### 2. Dart Unit Tests
- **Location:** `dart/test/cardano_flutter_test.dart`
- **Coverage:** Every public wrapper function (from Dart Bindings Agent)
- **Test structure:** At least 2 tests per function
- **Examples:**
  ```dart
  void main() {
    group('CardanoFlutter', () {
      test('validateAddress returns true for valid Bech32', () async {
        final result = await validateAddress('addr1...');
        expect(result, isTrue);
      });
      
      test('validateAddress throws on invalid input', () async {
        expect(
          () => validateAddress('invalid'),
          throwsA(isA<CardanoValidationError>()),
        );
      });
    });
  }
  ```
- **Setup:** Use Flutter test framework (included in `flutter test`)
- **Run:** `cd dart && flutter test` must pass
- **Linting:** `flutter analyze` must pass

### 3. Cardano Testnet Preview Integration Tests
- **Location:** `dart/test/integration_test/cardano_integration_test.dart` (separate from unit tests)
- **Purpose:** Verify SDK works against real Cardano infrastructure
- **Tests (examples):**
  - Fetch a UTXO from testnet preview via Blockfrost API
  - Deserialize it using SDK
  - Re-serialize and verify round-trip
  - Query network parameters from testnet
- **Setup:**
  - Create `tests/fixtures/testnet-config.yaml` (or similar) with:
    - Blockfrost API endpoint for testnet preview
    - A test address with known UTXOs (or use a known public address)
  - Environment variables: `BLOCKFROST_API_KEY` (can be public testnet key)
  - Create `.env.example` (public, no secrets) with:
    ```
    BLOCKFROST_API_KEY=your-testnet-preview-key-here
    CARDANO_NETWORK=testnet_preview
    ```
- **Run:** `cd dart && flutter test integration_test/` (may require running emulator or device)
- **Async handling:** Use `testWidgets` or `test` with `async`/`await`

### 4. Test Fixtures
- **Location:** `tests/fixtures/`
- **Files:**
  - `addresses.txt`: Known valid/invalid Bech32 addresses for each network (mainnet, testnet, Byron)
  - `mnemonics.txt`: Test mnemonics (public ones, e.g., from BIP39 spec)
  - `transactions.hex`: Sample serialized transactions for deserialization tests
  - `testnet-config.yaml`: Testnet URLs and test data endpoints
- **Format:** Markdown or YAML, clearly documented
- **Example:**
  ```yaml
  # testnet-config.yaml
  networks:
    testnet_preview:
      blockfrost_url: https://cardano-preview.blockfrost.io/api/v0
      known_utxos:
        - txHash: "abc123..."
          index: 0
          lovelace: 2000000
  ```

### 5. CI Integration (Optional for Phase 1, but Plan For It)
- **Location:** `.github/workflows/test.yml` (if GitHub Actions is set up)
- **Jobs:**
  - `rust_tests`: `cargo test && cargo clippy`
  - `dart_tests`: `flutter test`
  - `dart_integration`: `flutter test integration_test/` (requires emulator or test mode)
- **Triggers:** On every PR and push to main
- **Note:** Integration tests may skip in CI if emulator setup is too complex; flag this as a known limitation

### 6. Test Report
- Create `TEST_RESULTS.md` documenting:
  - Rust test results (unit tests)
  - Dart test results (unit tests)
  - Testnet integration results (which tests run, which are skipped, why)
  - Coverage estimates (informal; Phase 1 = 100% of public API)
  - Known limitations (e.g., web platform not tested in CI yet)

## Files to Create/Modify

```
rust/cardano_flutter_rs/
  tests/
    integration_tests.rs    # Rust integration tests
  src/
    lib.rs                  # Inline unit tests if preferred

dart/
  test/
    cardano_flutter_test.dart              # Dart unit tests
    integration_test/
      cardano_integration_test.dart        # Testnet integration tests
  .env.example                             # Testnet config (public)

tests/
  fixtures/
    addresses.txt
    mnemonics.txt
    transactions.hex
    testnet-config.yaml

.github/workflows/
  test.yml                  # (optional) CI pipeline

TEST_RESULTS.md             # Test report
```

## Acceptance Criteria

- [ ] `cargo test` passes (all Rust unit tests)
- [ ] `cargo clippy --tests` passes (no warnings)
- [ ] `cd dart && flutter test` passes (all Dart unit tests)
- [ ] `flutter analyze` passes
- [ ] Testnet integration tests run without errors (may have external failures if network is down)
- [ ] Test fixtures are in place and documented
- [ ] `.env.example` exists and is public (no secrets)
- [ ] At least 2 tests per public function (Rust + Dart)
- [ ] Error cases are tested explicitly (not just happy path)
- [ ] TEST_RESULTS.md summarizes coverage and known gaps

## Dependency on Other Agents

- **Blocked by:** Rust Scaffolding Agent (needs Rust PoC functions) + Dart Bindings Agent (needs Dart wrappers)
- **Unblocks:** Example Agent (tests inform example app design), Coordinator (gating Phase 1 ship)

---

Once complete, commit tests and fixtures. Coordinate with other agents to ensure the example app also runs integration tests.
