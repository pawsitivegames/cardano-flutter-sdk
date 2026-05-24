# Phase 1 Coordinator Guide

**Role:** You are the coordinator overseeing Phase 1 implementation via parallel agents.  
**Responsibility:** Assign tasks, validate outcomes, unblock agents, gate Phase 1 completion.

---

## Quick Start

1. **Read the goal:** [`.claude/goals/phase-1.md`](.claude/goals/phase-1.md)
2. **Assign agents** to the 5 tasks in `.claude/tasks/`:
   - Research Agent → `research-agent.md`
   - Rust Scaffolding Agent → `rust-scaffolding-agent.md`
   - Dart Bindings Agent → `dart-bindings-agent.md`
   - Test Automation Agent → `test-automation-agent.md`
   - Example & Docs Agent → `example-docs-agent.md`
3. **Track dependencies:** See the dependency graph below
4. **Validate outcomes** against acceptance criteria in each task file
5. **Ship Phase 1** when all agents report completion and checklist passes

---

## Agent Dependency Graph

```
Research Agent
    ↓ (provides CSL API surface, PoC function candidates)
Rust Scaffolding Agent ──┐
    ↓                   │
Dart Bindings Agent     │
    ↓ ─────────────────┼─→ Example & Docs Agent
    ↑                 ↑
Test Automation Agent ──┘
```

### Key Blocking Points

1. **Research → Rust:** Research Agent must complete before Rust Scaffolding starts
2. **Rust → Dart:** Rust code must compile and expose 3 PoC functions before Dart codegen runs
3. **Rust + Dart → Test:** Both must be complete before Test Automation writes tests
4. **Dart + Test → Example:** Both must be complete before Example & Docs app runs integration tests

---

## Coordination Checklist

### Pre-Launch

- [ ] All agents have read `.claude/goals/phase-1.md` and their assigned task file
- [ ] Each agent has clarified dependencies with the coordinator
- [ ] CLAUDE.md matches current project state (versions, conventions)
- [ ] Git repo is clean (or on a feature branch, preferably `phase-1-bootstrap`)

### During Execution

- [ ] Research Agent completes → provides `research-summary.md`
  - Coordinator reviews and confirms PoC function choices
  - Rust Scaffolding Agent unblocked
- [ ] Rust Scaffolding Agent completes → provides compiling crate
  - Coordinator verifies `cargo test && cargo clippy` pass
  - Dart Bindings Agent unblocked
- [ ] Dart Bindings Agent completes → provides generated bindings + wrappers
  - Coordinator verifies `flutter analyze` passes
  - Test Automation + Example agents unblocked
- [ ] Test Automation Agent completes → provides passing tests
  - Coordinator verifies `cargo test && flutter test` pass
- [ ] Example & Docs Agent completes → provides working app + docs
  - Coordinator verifies app runs on iOS simulator + Android emulator
  - Coordinator tests README setup on fresh clone

### Phase 1 Completion Checklist

Before shipping, verify:

- [ ] **Rust**
  - [ ] `cargo build` succeeds
  - [ ] `cargo test` passes (all PoC functions have ≥2 tests)
  - [ ] `cargo clippy --all-targets -- -D warnings` passes
  - [ ] `cargo fmt` applied (no style violations)
  - [ ] No panics in public API
  - [ ] Committed with clear messages

- [ ] **Dart**
  - [ ] `flutter pub get` succeeds
  - [ ] `flutter_rust_bridge_codegen generate` completes without errors
  - [ ] `flutter analyze` passes
  - [ ] `dart format lib/` applied
  - [ ] All public functions have dartdoc + examples
  - [ ] Committed with clear messages

- [ ] **Tests**
  - [ ] `cargo test` passes
  - [ ] `flutter test` passes
  - [ ] Testnet integration tests pass (or clearly flagged as skipped)
  - [ ] Test fixtures in place (`tests/fixtures/`)
  - [ ] Committed with clear messages

- [ ] **Example App**
  - [ ] Builds on iOS simulator
  - [ ] Builds on Android emulator
  - [ ] Runs without crashes
  - [ ] End-to-end flow works (input → validate → result)
  - [ ] Error handling tested
  - [ ] No hardcoded secrets

- [ ] **Documentation**
  - [ ] README updated with quick start, build commands, structure
  - [ ] README tested on fresh clone
  - [ ] Architecture diagram present and accurate
  - [ ] Links verified (no broken references)
  - [ ] CLAUDE.md and project-plan.md are current

- [ ] **Git**
  - [ ] All commits have clear messages
  - [ ] No merge conflicts
  - [ ] Feature branch ready for PR or can be merged to main
  - [ ] CI passes (if set up)

---

## Validation Process

### For Each Agent's Deliverable

**Step 1: Read the task file** (e.g., `research-agent.md`)  
**Step 2: Review the acceptance criteria** (checklist at bottom)  
**Step 3: Verify the agent's work against those criteria**  
**Step 4: Ask clarifying questions if anything is unclear**  
**Step 5: Either accept or request changes with specific feedback**

### Example Validation Flow

```
Agent: "I've completed Rust scaffolding. Pushed to phase-1-rust branch."

Coordinator:
1. Checks out phase-1-rust
2. Runs: cargo build && cargo test && cargo clippy
3. Verifies 3 PoC functions are FFI-exposed
4. Checks commit messages are clear
5. If all pass: "Rust scaffolding looks good. Dart Bindings Agent, you're unblocked."
6. If issues: "Clippy found 2 warnings in src/ffi.rs. Please fix and re-push."
```

---

## Common Issues & Resolutions

### "Clippy failed on warnings"
**Cause:** Rust code has style issues  
**Resolution:** Have Rust Scaffolding Agent run `cargo fmt && cargo clippy --fix` locally, test, and re-push

### "flutter_rust_bridge_codegen generate fails"
**Cause:** Rust code doesn't expose functions properly, or codegen config is wrong  
**Resolution:** Rust Scaffolding Agent should verify functions have `#[no_mangle]` and correct types; Dart Bindings Agent should verify `flutter_rust_bridge_codegen.yaml` matches Rust crate path

### "Tests pass locally but fail in CI"
**Cause:** Environment mismatch, missing fixtures, or flaky testnet integration tests  
**Resolution:** Test Automation Agent should document known limitations and skip tests that require external resources in CI

### "Example app crashes on launch"
**Cause:** Missing dependency, SDK API mismatch, or platform-specific issue  
**Resolution:** Example & Docs Agent should run `flutter clean && flutter pub get && flutter run -v` to see detailed logs

---

## Communication Template

When signaling completion to the next agent, use this format:

```
✅ [AGENT NAME] completed [TASK]

Deliverables:
- [File/artifact 1]
- [File/artifact 2]

Branch: [branch-name]
Commits: [N commit messages or link to branch]

Acceptance Criteria Met:
- [x] Criterion 1
- [x] Criterion 2
- [x] Criterion 3

Notes/Blockers:
[Any issues or questions]

Next Agent Unblocked: [Agent Name]
```

Example:

```
✅ RESEARCH AGENT completed research phase

Deliverables:
- .claude/research/research-summary.md

Key Findings:
- flutter_rust_bridge v2.4 is stable and well-tested
- CSL v15.1 has good coverage for address validation
- Platform-specific quirks: iOS needs to link libcardano_flutter_rs.a

PoC Functions Recommended:
1. validate_bech32_address (input: String → output: bool)
2. serialize_transaction (input: bytes → output: bytes)
3. get_network_id (input: none → output: u8)

Next Agent Unblocked: RUST SCAFFOLDING AGENT
```

---

## Escalation Path

If an agent gets stuck:

1. **Agent reports blocker** (e.g., "flutter_rust_bridge codegen fails on platform X")
2. **Coordinator investigates:**
   - Check the error message in detail
   - Ping the previous agent if it's a dependency issue
   - Suggest debugging steps (e.g., run with `--verbose`, check logs)
3. **If still stuck:** Coordinator can:
   - Pair with the agent to debug
   - Suggest narrowing scope (e.g., test on one platform first)
   - Ask for external research (update Research Agent findings)
4. **Document the resolution** for future reference

---

## Phase 1 Completion Ceremony

Once all agents report completion and the checklist is ✅:

1. **Merge feature branch** (or keep as main if solo development)
2. **Tag as v0.1-rc0:** `git tag -a v0.1-rc0 -m "Phase 1: Core FFI scaffold, 3 PoC functions, full test coverage"`
3. **Update CLAUDE.md:** Change "Pre-development. No code written yet." → "Phase 1 complete. Core FFI scaffold, 3 PoC functions (address validation, serialization, network queries), full test coverage, working example app."
4. **Announce:** Share commit/tag with stakeholders (e.g., Cardano community, Catalyst reviewers)

---

## Next Steps (Phase 2 Preview)

Once Phase 1 ships, Phase 2 starts with:
- Signing APIs (via CSL)
- Multi-asset support
- UTXO selection
- Settlement via 0x or native Cardano

Update `.claude/goals/phase-2.md` and assign new agents when ready.

---

**Last Updated:** 2026-05-24  
**Coordinator Role Owner:** You (main chat)  
**Agents:** 5 specialized agents (Research, Rust, Dart, Test, Example)
