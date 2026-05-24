# Task: Example & Docs Agent — App Demo & Documentation

**Assigned to:** Example & Docs Agent  
**Duration:** ~4 hours  
**Deliverable:** Working example app on iOS & Android simulators, updated README, architecture diagram  
**Blocked by:** Dart Bindings Agent (SDK APIs) + Test Automation Agent (test patterns to reference)  
**Coordinator:** Main chat

## Objective

Build a working example app demonstrating one end-to-end SDK flow, update the README with setup/build/test instructions, and create an architecture diagram showing the Dart → FFI → Rust → CSL stack.

## Scope

### 1. Example App (`example/`)
- **Existing structure:** should already be scaffolded in the repo (Flutter app template)
- **Dependency:** add path dependency to local `dart/` package in `example/pubspec.yaml`:
  ```yaml
  dependencies:
    cardano_flutter:
      path: ../dart
  ```
- **One end-to-end flow:** Implement a simple demo, e.g.:
  - User enters a Bech32 address in a text field
  - Tap "Validate" button
  - SDK validates the address using the Rust wrapper
  - Show result: "✓ Valid mainnet address" or error message
- **UI elements:**
  - Text input field for address
  - Validate button
  - Result display (Text widget showing success/error)
  - Loading indicator while validating (even if fast, for UX)
- **Error handling:** Catch CardanoValidationError and display user-friendly messages
- **State management:** Use Provider (if already in pubspec) or simple StatefulWidget for Phase 1
- **Run locally:**
  - `cd example && flutter run` (defaults to iOS simulator on macOS)
  - Also test on Android emulator: `flutter run -d <emulator-id>`
  - Should launch without build errors
- **No hardcoded secrets:** Externalize any config to `.env` (see Test Automation Agent)

### 2. README Update
- **Location:** `README.md` in repo root
- **Sections to add/update:**
  - **Overview:** One-paragraph summary of what the SDK is and why (Dart → CSL via FFI)
  - **Quick Start:**
    - Prerequisites (Flutter >=3.19.0, Rust stable, etc.)
    - Clone and setup: `flutter pub get`, `cargo build`, etc.
    - Run example app: `cd example && flutter run`
  - **Build Commands:**
    ```bash
    # Generate Rust bindings
    flutter_rust_bridge_codegen generate
    
    # Run Rust tests
    cd rust && cargo test && cargo clippy --all-targets -- -D warnings
    
    # Run Dart tests
    cd dart && flutter test
    
    # Run example app
    cd example && flutter run
    ```
  - **Project Structure:**
    ```
    .
    ├── rust/           Rust wrapper crate
    ├── dart/           Dart package (SDK)
    ├── example/        Flutter app demo
    └── docs/           Architecture, guides
    ```
  - **Platform Support:** iOS, Android, web, macOS, Linux, Windows (list current status: e.g., "iOS/Android tested in Phase 1")
  - **Documentation:** Link to CSL docs, Cardano developer portal, CIP-30/45
  - **Contributing:** Point to CLAUDE.md and project-plan.md
- **Tone:** Professional, clear, minimal jargon
- **Length:** ~2–3 pages when rendered (not exhaustive; detailed info goes in linked docs)

### 3. Architecture Diagram
- **Format:** Mermaid diagram (can be rendered in GitHub markdown) or PNG (if Mermaid isn't preferred)
- **Content:** Visual representation of:
  ```
  Flutter App (Dart)
    ↓ (FFI / flutter_rust_bridge)
  Rust Wrapper (cardano_flutter_rs)
    ↓ (Rust crate dependency)
  Cardano Serialization Lib (CSL v15)
  ```
- **Additional annotations:**
  - Show data types crossing boundaries (e.g., "Bech32 string → Rust validation → bool result")
  - Note platforms: iOS, Android, web, etc.
  - Call out error handling (Rust Error → Dart Exception)
- **Location:** Include in README via `![Architecture](docs/architecture.md)` or embed Mermaid
- **Example Mermaid:**
  ```mermaid
  graph TD
      A["Flutter App<br/>(Dart)"] -->|FFI Call| B["Rust Wrapper<br/>(cardano_flutter_rs)"]
      B -->|Rust crate| C["Cardano Serialization Lib<br/>(CSL v15.x)"]
      C -->|CDDL Codec| D["Cardano Protocol"]
      B -->|Error Mapping| E["Dart Exception"]
  ```

### 4. Documentation Structure
- **docs/architecture.md:** Detailed explanation of the FFI boundary, type marshaling, async patterns
- **docs/project-plan.md:** (should already exist; verify Phase 1 scope vs. implementation)
- **docs/phase-1-checklist.md:** (optional) Quick reference for Phase 1 completion

### 5. Example App Testing
- **Manual testing checklist:**
  - [ ] Build succeeds on iOS simulator
  - [ ] Build succeeds on Android emulator
  - [ ] App launches without crashes
  - [ ] Entering a valid address and tapping Validate shows success
  - [ ] Entering an invalid address and tapping Validate shows error
  - [ ] No unhandled exceptions in the debugger console
  - [ ] App exits cleanly
- **Supported platforms in Phase 1:** iOS simulator + Android emulator (desktop platforms tested later)

## Files to Create/Modify

```
example/
  pubspec.yaml           # add cardano_flutter path dependency
  lib/
    main.dart            # main app
    pages/
      address_validation_demo.dart  # example flow

docs/
  architecture.md        # FFI architecture deep-dive
  project-plan.md        # (verify exists)

README.md               # updated with quick start, build commands, structure
```

## Acceptance Criteria

- [ ] Example app builds and runs on iOS simulator without errors
- [ ] Example app builds and runs on Android emulator without errors
- [ ] Example flow works end-to-end (user input → validation → result display)
- [ ] Error handling is tested (invalid input → error message)
- [ ] No hardcoded secrets in code; config is externalized
- [ ] README has all sections: overview, quick start, build commands, structure, platform support, links
- [ ] README is tested: fresh clone can follow it to build and run the app
- [ ] Architecture diagram is present, clear, and accurate
- [ ] docs/architecture.md explains the FFI boundary and type marshaling
- [ ] All internal links in README and docs are verified (no broken references)
- [ ] Committed with clear message (e.g., "docs: Add Phase 1 architecture and example app demo")

## Dependency on Other Agents

- **Blocked by:** Dart Bindings Agent (SDK APIs to use) + Test Automation Agent (test patterns to reference)
- **Unblocks:** Coordinator (ready to validate Phase 1 ship)

---

Once complete, run the app on both simulators in front of the Coordinator. The Coordinator will verify that Phase 1 is complete and ready for v0.1 release.
