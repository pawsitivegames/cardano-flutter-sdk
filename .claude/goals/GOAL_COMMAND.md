# How to Invoke Phase Goals

## Quick Command Reference

Use these commands to invoke phase goals in Claude Code:

### Phase 1: Core FFI & Read-Only Wallet

```
/goal Build Phase 1 of the production-grade Cardano Flutter SDK with complete end-to-end FFI integration, test coverage, and documentation. Success means: flutter_rust_bridge toolchain bootstrapped, cardano-serialization-lib v15+ wrapped in Rust, read-only wallet APIs (address validation, balance queries, transaction inspection) exposed to Dart with full type safety, all code passing clippy/flutter_analyze, example app demonstrating core flows, and integration tests against Cardano testnet preview. Use 5 parallel agents for research, Rust scaffolding, Dart bindings, test automation, and example app development. This chat is the coordinator—it assigns tasks and validates outcomes; agents execute independently. Deep-dive research on flutter_rust_bridge best practices and CSL API surface before any implementation. Ship only what the project plan explicitly calls for Phase 1. Goal file: .claude/goals/phase-1.md
```

### Phase 2: Transaction Building & Signing

```
/goal Build Phase 2 of the Cardano Flutter SDK with complete transaction building, signing, and multi-asset support. Success means: transaction builder API fully implemented, coin selection algorithms (largest-first, random-improve) working, witness/signature construction via CSL, native asset transfers tested, on-chain submission to Cardano testnet preview verified, example app demonstrating send flow with ADA + native tokens, full test coverage (fee math, witness generation, round-trip serialization). Use 5 parallel agents for research, Rust implementation, Dart wrappers, test automation, and example updates. Phase 1 must be complete and stable before starting. Deep-dive research on fee calculation and coin selection best practices. Test extensively on testnet before shipping v0.2.0. Goal file: .claude/goals/PHASES_WITH_VERIFICATION.md (Phase 2 section)
```

### Phase 3: Smart Contracts & NFTs

```
/goal Build Phase 3 of the Cardano Flutter SDK with full smart contract and NFT support. Success means: Plutus V2 and V3 script attachment and execution, datum and redeemer encoding via CSL, native token minting/burning, CNFT support (CIP-25 and CIP-68 metadata standards), reference inputs and collateral handling fully implemented, example app demonstrating NFT minting on testnet, comprehensive test coverage (script validation, datum serialization, on-chain interaction). Use 5 parallel agents for research, Rust implementation, Dart wrappers, test automation, and example updates. Phase 2 must be complete and stable. Test all features on Cardano testnet preview before releasing v0.3.0. Goal file: .claude/goals/PHASES_WITH_VERIFICATION.md (Phase 3 section)
```

### Phase 4: Wallet Connectors & dApp Integration

```
/goal Build Phase 4 of the Cardano Flutter SDK with complete dApp integration support. Success means: CIP-30 dApp connector API fully implemented and tested, CIP-45 WalletConnect v2 for Cardano integrated, deep linking for iOS/Android wallet handoff working, message signing for dApp authentication complete, example Flutter dApp connecting to production wallets (Lace, Eternl, Vespr) on testnet, comprehensive security testing (origin validation, signature verification). Use 5 parallel agents for research, Rust implementation, Dart wrappers, test automation, and example dApp development. Phase 3 must be complete. Coordinate with production wallet teams for testing. Ship v1.0.0 only after full validation on live wallets. Goal file: .claude/goals/PHASES_WITH_VERIFICATION.md (Phase 4 section)
```

### Open-Source Setup & Maintenance

```
/goal Establish sustainable open-source foundation for Cardano Flutter SDK. Success means: MIT license in place with SPDX headers in all files, CONTRIBUTING.md with complete contributor workflow, CODE_OF_CONDUCT.md for community standards, SECURITY.md with responsible disclosure process, GitHub issue and PR templates configured, branch protection rules enforced on main, MAINTAINERS.md documenting governance, v0.1.0 published to pub.dev and crates.io, community discovery complete (Awesome Cardano list, Cardano Forum post, X announcements). Ensure all code follows style guidelines (cargo clippy, flutter analyze), all tests pass, documentation is complete and tested. Goal file: .claude/goals/OPEN_SOURCE_STRATEGY.md
```

---

## General Command Format

```
/goal [Phase Goal Statement]

Use coordinated agent approach:
- Research Agent: deep-dive on technologies and best practices
- Implementation Agents: Rust, Dart, Tests, Documentation
- Coordinator (this chat): assigns tasks, validates outcomes, gates progression
- Each agent has explicit scope, acceptance criteria, and dependencies in .claude/tasks/
```

## Tips

1. **Include the goal file reference** at the end (e.g., `.claude/goals/phase-1.md`)
2. **Be specific about success criteria** (what "done" looks like)
3. **Name the parallel agents** if using agent coordination
4. **Mention testing/verification requirements** early
5. **Gate progression** (e.g., "Phase 2 only starts after Phase 1 stable")

---

**Last Updated:** 2026-05-24
