# Task: Dart Bindings Agent — Code Generation & Type-Safe API

**Assigned to:** Dart Bindings Agent  
**Duration:** ~5 hours  
**Deliverable:** Auto-generated `bridge_generated.dart`, type-safe public wrappers, full dartdoc coverage, lints passing  
**Blocked by:** Rust Scaffolding Agent (Rust code to bind to)  
**Coordinator:** Main chat

## Objective

Set up the flutter_rust_bridge codegen pipeline, generate Dart bindings from Rust PoC functions, wrap them in type-safe Dart APIs with dartdoc examples, and ensure all lints pass.

## Scope

### 1. flutter_rust_bridge Setup
- Verify `Cargo.toml` in Rust crate has correct `[lib]` section for FFI (`crate-type = ["rlib", "cdylib"]`)
- Create `pubspec.yaml` in `dart/` with:
  - `flutter_rust_bridge: ^2.x` (check latest on pub.dev)
  - `ffi: ^2.x`
  - Any platform-specific dependencies (for iOS/Android/web)
  - `cargokit` for native builds (if not already there)
- Generate `pubspec.lock` via `flutter pub get`
- Verify setup with a quick `flutter_rust_bridge_codegen generate` dry-run

### 2. Codegen Configuration
- Create or update `flutter_rust_bridge_codegen.yaml` (or `cargokit.toml` + config):
  - Rust crate path: `../rust/cardano_flutter_rs`
  - Output Dart file: `lib/src/bridge_generated.dart`
  - Enable platform-specific code generation (iOS, Android, web, macOS, Linux, Windows)
- Run codegen: `flutter_rust_bridge_codegen generate`
- Verify `bridge_generated.dart` is generated and free of parse errors

### 3. Type-Safe Dart Wrappers
- Create `lib/src/cardano_flutter.dart` (or similar) to export clean public APIs
- Wrap raw `bridge_generated.dart` functions with idiomatic Dart:
  - Convert C errors to Dart exceptions (thiserror → Dart Exception subclasses)
  - Use `Future<T>` for async operations (none in Phase 1, but future-proof)
  - Use typed enums or sealed classes instead of raw C enums if needed
  - Add input validation (e.g., null checks) before calling Rust

Example structure:
```dart
// lib/src/cardano_flutter.dart
import 'bridge_generated.dart';

class CardanoValidationError implements Exception {
  final String message;
  CardanoValidationError(this.message);
  @override
  String toString() => 'CardanoValidationError: $message';
}

/// Validate a Bech32 address.
/// 
/// Returns true if the address is valid on any supported network.
/// Throws [CardanoValidationError] if validation fails.
/// 
/// Example:
/// ```dart
/// try {
///   bool isValid = await validateAddress('addr1...');
///   print('Valid: $isValid');
/// } on CardanoValidationError catch (e) {
///   print('Error: ${e.message}');
/// }
/// ```
Future<bool> validateAddress(String address) async {
  final result = native_validate_address(address);
  if (result.isError) {
    throw CardanoValidationError(result.error);
  }
  return result.value;
}

// ... wrap other PoC functions similarly
```

### 4. Dartdoc Comments
- All public functions in the wrapper must have dartdoc comments:
  - One-line summary (first line)
  - Optional detailed description
  - `@param` or inline parameter docs
  - `@return` or inline return docs
  - `@throws` for exceptions
  - **Required:** one usage example per public function
- Run `dart doc --validate-links` to check for broken references
- Export public APIs from `lib/cardano_flutter.dart` (the main library file)

### 5. Linting
- `flutter analyze` must pass with no errors or warnings
- Enable strict linting in `analysis_options.yaml` if not already present:
  ```yaml
  linter:
    rules:
      - prefer_final_locals
      - prefer_const_declarations
      - avoid_empty_else
  ```
- Format code: `dart format lib/`

### 6. Test Scaffold (Optional for This Task)
- Create `test/cardano_flutter_test.dart` with placeholder tests for each wrapper function
- Tests will be implemented by the Test Automation Agent, but create the file structure here
- Placeholder tests can be stubs that call the wrapper functions (will be filled in later)

## Files to Create/Modify

```
dart/
  pubspec.yaml                          # flutter_rust_bridge dependency
  analysis_options.yaml                 # (create if not present)
  lib/
    cardano_flutter.dart                # public API, re-exports
    src/
      bridge_generated.dart             # auto-generated (DO NOT EDIT)
      cardano_flutter.dart              # type-safe wrappers
  test/
    cardano_flutter_test.dart           # placeholder test file
  flutter_rust_bridge_codegen.yaml      # codegen config (if separate from pubspec)
```

## Acceptance Criteria

- [ ] `flutter pub get` succeeds
- [ ] `flutter_rust_bridge_codegen generate` completes without errors
- [ ] `bridge_generated.dart` exists and compiles
- [ ] All 3 PoC functions are wrapped with type-safe Dart APIs
- [ ] All public functions have dartdoc with examples
- [ ] `dart doc --validate-links` passes (no broken references)
- [ ] `flutter analyze` passes with no errors or warnings
- [ ] `dart format lib/` applied; no style violations
- [ ] Wrapper module is documented explaining architecture (Rust → FFI → Dart type mapping)
- [ ] Example app can import and use the wrapper APIs (verified by Dart Bindings Agent or Coordinator)

## Dependency on Other Agents

- **Blocked by:** Rust Scaffolding Agent (needs Rust PoC functions to bind)
- **Unblocks:** Test Automation Agent (needs wrappers to test) and Example Agent (needs APIs to demonstrate)

---

Once complete, commit to a feature branch and notify the Coordinator. The example app and tests will consume these bindings.
