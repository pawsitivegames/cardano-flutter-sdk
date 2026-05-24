# Task: Rust Scaffolding Agent — CSL Wrapper & FFI Surface

**Assigned to:** Rust Scaffolding Agent  
**Duration:** ~6 hours  
**Deliverable:** Compiling `rust/cardano_flutter_rs` crate with 3 PoC functions, full test coverage, all lints passing  
**Blocked by:** Research Agent (CSL API surface, PoC functions)  
**Coordinator:** Main chat

## Objective

Bootstrap the Rust crate, integrate `cardano-serialization-lib`, define error types, and implement 3 proof-of-concept functions that will be exposed to Dart via flutter_rust_bridge.

## Scope

### 1. Crate Scaffolding
- Create `rust/cardano_flutter_rs/` with standard layout (src/lib.rs, Cargo.toml, tests/)
- `Cargo.toml`:
  - Edition 2021
  - Dependencies: `cardano-serialization-lib = "15.*"`, `thiserror`, `serde`, `serde_json`
  - Add `[lib]` section if needed for FFI (crate-type = ["cdylib"])
  - Check CLAUDE.md for any version pins; if not specified, use latest stable 15.x on crates.io
- `.gitignore` for Cargo build artifacts
- Verify `cargo build` and `cargo clippy --all-targets -- -D warnings` pass on fresh checkout

### 2. Error Types
- Define a custom error enum using `thiserror`:
  ```rust
  #[derive(thiserror::Error, Debug)]
  pub enum Error {
      #[error("Validation error: {0}")]
      ValidationError(String),
      #[error("Serialization error: {0}")]
      SerializationError(String),
      #[error("CSL error: {0}")]
      CslError(String),
      // ... add more as needed for PoC functions
  }
  
  pub type Result<T> = std::result::Result<T, Error>;
  ```
- Ensure all public functions return `Result<T>`, never panic.
- Document error cases inline.

### 3. FFI Module
- Create `src/ffi.rs` (or inline in lib.rs if small) to expose functions to Dart
- Mark functions with `#[no_mangle]` and `pub extern "C"` as needed for flutter_rust_bridge codegen
- Ensure parameter and return types are FFI-safe (primitives, structs with #[repr(C)], etc.)
- Add comments noting any marshaling needed (Dart ↔ Rust string encoding, etc.)

### 4. Three Proof-of-Concept Functions
Implement based on Research Agent's recommendations. Examples:

**Function 1: Address Validation**
- Input: Bech32 string
- Output: `bool` (is valid) or detailed error
- Uses CSL's address parser
- Test cases: valid mainnet, valid testnet, invalid checksums, wrong HRP

**Function 2: Serialization Round-Trip**
- Input: a Cardano type (e.g., TransactionOutput) as bytes
- Deserialize it using CSL → Serialize it back
- Output: bytes matching original (or describe any differences)
- Validates CSL codec correctness

**Function 3: CDDL Inspection or Schema Query**
- Input: (none, or a query string)
- Output: some metadata about Cardano (e.g., supported network IDs, protocol version, CDDL schema excerpt)
- Proves CSL types are accessible and queryable

For each function:
- Write at least 2 unit tests (happy path + error case)
- Document with comments explaining the CSL API used
- Ensure no panics; return Rust `Error` instead

### 5. Testing
- `cargo test` must pass
- Write tests in `src/lib.rs` or `tests/integration_tests.rs` (integration tests preferred for CSL)
- Each PoC function needs ≥2 test cases
- Use test fixtures (mnemonics, known addresses) from `tests/fixtures/` if created by another agent; otherwise inline literals are fine for Phase 1

### 6. Linting
- `cargo fmt` applied
- `cargo clippy --all-targets -- -D warnings` passes
- No TODO/FIXME comments without context (one-liners only, with why)

## Files to Create/Modify

```
rust/
  cardano_flutter_rs/
    Cargo.toml
    src/
      lib.rs           # main crate, error types, exports
      ffi.rs           # (optional) FFI surface
    tests/
      integration_tests.rs  # PoC function tests
    .gitignore
```

## Acceptance Criteria

- [ ] `cargo build` succeeds
- [ ] `cargo test` passes (all 3 PoC functions have ≥2 tests each)
- [ ] `cargo clippy --all-targets -- -D warnings` passes
- [ ] `cargo fmt` applied (no style violations)
- [ ] No panics in public API; all errors use custom `Result<T>` type
- [ ] 3 PoC functions exposed via FFI (functions ready for flutter_rust_bridge codegen)
- [ ] Inline comments explain non-obvious CSL API usage
- [ ] Committed with clear commit messages (one per logical change)

## Dependency on Other Agents

- **Blocked by:** Research Agent (which 3 PoC functions to implement, CSL API surface)
- **Unblocks:** Dart Bindings Agent (needs Rust code to generate bindings from)

---

Once complete, commit and notify the Coordinator. The Dart Bindings Agent will run `flutter_rust_bridge_codegen` against your code.
