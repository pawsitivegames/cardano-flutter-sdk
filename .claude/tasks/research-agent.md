# Task: Research Agent — Phase 1 Foundations

**Assigned to:** Research Agent  
**Duration:** ~4 hours  
**Deliverable:** `research-summary.md` in `.claude/research/`  
**Coordinator:** Main chat

## Objective

Provide a deep-dive research summary on `flutter_rust_bridge` v2.x, Cardano Serialization Lib v15+ API surface, and platform-specific FFI quirks. Output should de-risk the parallel implementation workstreams.

## Scope

### 1. flutter_rust_bridge v2.x Best Practices
- Current stable version on crates.io; verify against `Cargo.toml` guidance
- Setup checklist: what's required to get codegen working per platform (macOS, Linux, Windows)
- Common gotchas: async boundaries, platform-specific build flags, native library linking
- Example projects from the flutter_rust_bridge repo that use CSL or similar large crypto libraries
- Code generation: how to structure Rust code for optimal binding ergonomics

### 2. Cardano Serialization Lib v15.x API Surface
- Public types and functions relevant to Phase 1 read-only operations:
  - Address validation and parsing (Bech32, Byron, Shelley)
  - UTXO serialization and deserialization
  - Transaction inspection (outputs, fees, inputs)
  - Network IDs and protocol parameters
- Error types in CSL; how to map them to Rust error enums
- Documentation links (docs.rs, GitHub repo) for reference
- Any breaking changes vs. v14.x (if relevant)

### 3. Platform-Specific FFI Quirks
- iOS: native library linking, simulator vs. device builds
- Android: .so linking, API level considerations
- Web: WASM limitations; does flutter_rust_bridge support web in v2.x?
- macOS/Linux/Windows: static vs. dynamic linking trade-offs

### 4. Function Candidates for Phase 1 PoCs
- At least 3 functions to implement as proof-of-concept:
  - Address validation (simple input → bool/error)
  - Serialization round-trip (serialize something, deserialize it back)
  - CDDL inspection or schema query (if available in CSL)
- For each, note: parameter types, return types, likely error cases

### 5. Reference Projects
- Search GitHub/crates.io for projects using flutter_rust_bridge + large Rust libraries
- Look at CardanoKit (Swift version) architecture for comparison
- Note any FFI pitfalls or best practices from similar projects

## Output Format

Markdown file `research-summary.md` with sections for each of the above. Include:
- Direct quotes or links to official docs (max 1–2 per section)
- Bullet-point summaries of findings
- A "risks/unknowns" subsection flagging any unresolved questions
- A "recommended PoC functions" subsection with function signatures

## Acceptance Criteria

- [ ] Research summary addresses all 5 scope points above
- [ ] Links to CSL docs and flutter_rust_bridge examples are verified (not dead)
- [ ] At least 3 PoC function candidates identified with signatures
- [ ] Platform-specific quirks are documented with mitigation strategies
- [ ] No unresolved blockers (risks/unknowns are flagged, not hidden)
- [ ] File is < 5 pages when printed; concise and scannable

---

Once this is complete, signal the Coordinator. The Rust Scaffolding Agent will use these findings to unblock their work.
