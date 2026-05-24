# Contributing to Cardano Flutter SDK

Thank you for your interest in contributing to the Cardano Flutter SDK! This document explains how to participate.

## Code of Conduct

Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing. We are committed to providing a welcoming and inclusive community for all.

## Getting Started

### Prerequisites

- Rust (stable, edition 2021)
- Flutter >=3.19.0
- Dart >=3.3.0
- See README.md for detailed setup

### Fork & Clone

```bash
# Fork the repo on GitHub, then:
git clone https://github.com/YOUR_USERNAME/cardano-flutter-sdk.git
cd cardano-flutter-sdk
git remote add upstream https://github.com/ORIGINAL_ORG/cardano-flutter-sdk.git

# Create a feature branch
git checkout -b feature/my-feature
```

### Running Tests

```bash
# Rust tests
cd rust && cargo test && cargo clippy --all-targets -- -D warnings

# Dart tests
cd dart && flutter test

# Integration tests
cd dart && flutter test integration_test/

# All in one
./scripts/test-all.sh  # (if it exists)
```

### Linting

```bash
# Rust
cd rust && cargo fmt && cargo clippy

# Dart
cd dart && flutter analyze && dart format lib/ test/
```

## Making Changes

### Scope

- **Keep changes focused:** One feature or bug fix per PR
- **Avoid scope creep:** If you're fixing a bug, don't refactor other code in the same PR
- **Document breaking changes:** If changing public API, explain migration path in PR description

### Code Style

#### Rust

- **Format:** `cargo fmt` (automatic, non-negotiable)
- **Linting:** `cargo clippy --all-targets -- -D warnings` must pass
- **Comments:** Explain WHY, not WHAT. Code should be self-documenting.
- **Errors:** Use `thiserror`-derived error enums. Never panic in public API.
- **Example:**
  ```rust
  /// Validate a Bech32 address.
  /// 
  /// Returns true if the address is valid on any supported network.
  pub fn is_valid_bech32(addr: &str) -> Result<bool, Error> {
      csl::Address::from_bech32(addr).map(|_| true).or_else(|e| {
          Err(Error::ValidationError(format!("Invalid address: {}", e)))
      })
  }
  ```

#### Dart

- **Format:** `dart format` (automatic)
- **Linting:** `flutter analyze` must pass with no warnings
- **Dartdoc:** Public functions must have dartdoc comments with examples
- **Tests:** ≥2 tests per public function
- **Example:**
  ```dart
  /// Validate a Bech32 address.
  /// 
  /// Returns true if [address] is a valid Bech32 address on any supported network.
  /// 
  /// Example:
  /// ```dart
  /// final isValid = await validateAddress('addr1...');
  /// print('Valid: $isValid');
  /// ```
  Future<bool> validateAddress(String address) async {
    // implementation
  }
  ```

### Testing

- **Unit tests:** For all public functions
  - Minimum 2 tests per function (happy path + error case)
  - Location: `tests/` (Rust) or `test/` (Dart)
  
- **Integration tests:** For end-to-end flows
  - Location: `tests/integration_tests.rs` (Rust) or `dart/test/integration_test/` (Dart)
  - Test against Cardano testnet preview (if applicable)
  
- **Run before pushing:**
  ```bash
  cargo test && dart test
  ```

### Documentation

- **Code comments:** Explain non-obvious logic or design decisions
- **Dartdoc:** All public APIs must have dartdoc with usage example
- **README updates:** If changing setup, build, or test commands
- **docs/:** If adding major feature, consider adding guide in `docs/`

## Submitting a Pull Request

### Before You Start

1. Check [open issues](../../issues) — your idea might already be discussed
2. Open an issue to discuss large changes before coding
3. Ensure your local branch is up-to-date:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

### PR Description

Use the template in `.github/pull_request_template.md`. Include:

- **Clear title:** Summarize the change (e.g., "Fix address validation for Byron era addresses")
- **Type:** Bug fix, feature, breaking change, docs update
- **Description:** What and why (not just what)
- **Testing:** How you tested the change
- **Related issues:** `Closes #123` (auto-closes issue on merge)

### Example PR

```markdown
## Description
Fix validation of Byron-era addresses, which were previously rejected as invalid.

## Type
Bug fix

## Testing
- Added unit test for Byron address validation
- Verified against Cardano testnet preview with known Byron address

## Related Issues
Closes #456
```

### CI Requirements

Your PR must pass:
- ✅ `cargo test` and `cargo clippy` (Rust)
- ✅ `flutter test` and `flutter analyze` (Dart)
- ✅ GitHub Actions CI workflow
- ✅ At least 1 maintainer review

### Review Process

1. **Submit PR** with clear description
2. **CI runs automatically** — fix any failures
3. **Maintainers review** (typically within 1 week)
4. **Address feedback** — push new commits (don't force-push)
5. **Re-request review** once feedback is addressed
6. **Merge** when approved by ≥1 maintainer

### Merging

Maintainers will:
- Use "Squash and merge" for clarity (one commit per PR)
- Ensure commit message is clear
- Delete the feature branch

---

## Reporting Bugs

Found a bug? Open an [issue](../../issues) with:

1. **Clear title:** "Address validation fails for X"
2. **Reproducible steps:**
   ```
   1. Enter address "addr1..."
   2. Call validate()
   3. Observe: error instead of success
   ```
3. **Expected vs. actual behavior**
4. **Environment:** Flutter version, Dart version, platform (iOS/Android/web)
5. **Logs:** Error messages, stack traces (if applicable)

**Security bug?** Do NOT open a public issue. Email [security@cardano-flutter-sdk.dev] instead.

---

## Suggesting Features

Have an idea? Open an [issue](../../issues) or [discussion](../../discussions) with:

1. **Clear motivation:** Why is this needed?
2. **Proposed solution:** How should it work?
3. **Alternatives:** Any other approaches?
4. **Example use case:** Real-world usage

---

## Questions?

- **Discord:** [Link to community Discord]
- **Forum:** https://forum.cardano.org
- **Discussions:** [GitHub Discussions](../../discussions)
- **Email:** maintainers@cardano-flutter-sdk.dev

---

## License

By contributing, you agree your work is licensed under the MIT license. See [LICENSE](LICENSE) for details.

Thank you for building Cardano together! 🙏
