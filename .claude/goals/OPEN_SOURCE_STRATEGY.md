# Cardano Flutter SDK — Open Source Strategy

**Goal:** Make the SDK genuinely open-source from day 1, enabling community contribution and long-term sustainability.

---

## 1. Licensing & Legal Foundation

### MIT License (Already Chosen ✓)

**Why MIT:**
- Matches upstream `cardano-serialization-lib` (Emurgo's license)
- Catalyst-friendly (Cardano community preference)
- Permissive: allows commercial use, modification, distribution
- Compatible with Swift/Kotlin downstream SDKs (no GPL viral clause)
- Simple, widely understood

**Action Items:**
- ✅ `LICENSE` file in repo root (MIT full text)
- ✅ License header in every source file (Rust, Dart, config):
  ```rust
  // SPDX-License-Identifier: MIT
  // Copyright (c) 2026 Cardano Flutter SDK Contributors
  //
  // This source code is licensed under the MIT license found in the
  // LICENSE file in the root directory of this source tree.
  ```
  ```dart
  // SPDX-License-Identifier: MIT
  // Copyright (c) 2026 Cardano Flutter SDK Contributors
  ```
- ✅ Ownership statement in README: "This project is **open-source and owned by the community**. No single entity controls the SDK."

### Copyright Attribution

**Decision:** "Cardano Flutter SDK Contributors" = shared copyright model

**Why:** Recognizes that v1.0+ will have many authors. Avoids single-person or corporate ownership claims. Enables transfer of maintainership.

**Implementation:**
- Copyright notices use "Contributors" not individual names
- CONTRIBUTORS.md file lists all major contributors (updated quarterly)
- No contributor agreement (CLA) required — MIT doesn't require one
- Each PR merged = implicit MIT license grant

---

## 2. GitHub Repository Setup

### Repository Settings

**Visibility:** Public from day 1 (week 1, phase 1)

**Settings to configure:**
- ✅ Description: "Production-grade Flutter SDK for Cardano, powered by Rust + cardano-serialization-lib"
- ✅ Website: link to docs site (once live)
- ✅ Topics: `cardano`, `flutter`, `sdk`, `blockchain`, `rust`, `mobile`
- ✅ Discussions enabled (for community Q&A, not just issues)
- ✅ Sponsorships enabled (link to Catalyst, OpenCollective if fundraising)
- ✅ Branch protection on `main`:
  - Require pull request reviews before merging (≥1 approval)
  - Require status checks to pass (CI must pass)
  - Require branches to be up to date before merge
  - Allow auto-merge (for dependabot, trusted maintainers)

### Issue Templates

Create `.github/ISSUE_TEMPLATE/`:

**bug_report.md:**
```markdown
---
name: Bug Report
about: Report a bug in the SDK
---

## Description
[Clear description of the bug]

## Steps to Reproduce
1. ...
2. ...

## Expected vs. Actual
Expected: ...
Actual: ...

## Environment
- Flutter version: ...
- Dart version: ...
- Platform: iOS/Android/web
- SDK version: ...

## Logs / Screenshots
[Attach if helpful]
```

**feature_request.md:**
```markdown
---
name: Feature Request
about: Suggest a feature
---

## Motivation
[Why is this needed?]

## Proposed Solution
[How should it work?]

## Alternatives Considered
[Any other approaches?]
```

**question.md:**
```markdown
---
name: Question
about: Ask a question
---

## Question
[What are you wondering about?]

## Context
[Where did you encounter this?]
```

### Pull Request Template

Create `.github/pull_request_template.md`:
```markdown
## Description
[What does this PR do?]

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed (describe)

## Checklist
- [ ] Code follows style guidelines (`cargo fmt`, `flutter analyze`)
- [ ] Tests pass (`cargo test`, `flutter test`)
- [ ] Documentation updated
- [ ] No new warnings or errors

## Related Issues
Closes #[issue number]
```

---

## 3. Community Guidelines

### CONTRIBUTING.md

Create comprehensive contributor guide:

```markdown
# Contributing to Cardano Flutter SDK

Thank you for your interest in contributing! This guide explains how.

## Code of Conduct
See CODE_OF_CONDUCT.md. TL;DR: Be respectful, inclusive, professional.

## Getting Started
1. Fork the repo
2. Clone your fork
3. Follow setup in README.md
4. Create a feature branch: `git checkout -b feature/my-feature`

## Making Changes
- Keep changes focused (one feature/fix per PR)
- Follow style guidelines (see below)
- Add tests for new code
- Update docs if changing public API

## Style Guidelines
### Rust
- `cargo fmt` — automatic formatting
- `cargo clippy --all-targets -- -D warnings` — no warnings
- Comments: explain WHY, not WHAT
- Error types: use `thiserror`, never panic in public API

### Dart
- `flutter analyze` — must pass
- `dart format` — automatic formatting
- Dartdoc comments on public APIs with examples
- Tests: ≥2 per public function

## Testing
- Rust: `cd rust && cargo test`
- Dart: `cd dart && flutter test`
- Integration: `cd dart && flutter test integration_test/`

## Submitting a PR
1. Push to your fork
2. Open a PR to `main` with clear description
3. CI checks must pass
4. Wait for ≥1 maintainer review
5. Address feedback, re-request review
6. Maintainer merges when approved

## Reporting Security Issues
**Do NOT open a public issue for security bugs.**
Email security@cardano-flutter-sdk.dev with:
- Description of vulnerability
- Affected versions
- Proposed fix (if you have one)

We'll respond within 48 hours and coordinate a fix.

## Licensing
By contributing, you agree your work is licensed under MIT.
```

### CODE_OF_CONDUCT.md

Use Contributor Covenant v2.1 (industry standard):

```markdown
# Contributor Covenant Code of Conduct

## Our Pledge
We are committed to providing a welcoming and inspiring community for all.

## Our Standards
- Use inclusive language
- Be respectful of different viewpoints
- Accept constructive criticism
- Focus on what is best for the community

## Enforcement
Instances of unacceptable behavior may be reported to [maintainers]. 
All complaints will be reviewed and investigated.

[Full Contributor Covenant v2.1 text...]
```

### SECURITY.md

```markdown
# Security Policy

## Reporting a Vulnerability
**Do not open a public GitHub issue for security vulnerabilities.**

Email: security@cardano-flutter-sdk.dev

Include:
- Description of vulnerability
- Affected versions
- Steps to reproduce
- Proposed fix (if available)

**Response:** We will acknowledge within 48 hours and coordinate a fix.

## Supported Versions
- Latest minor version (v1.x.y) receives security fixes
- v0.x is best-effort; consider upgrading to v1.0+

## Security Practices
- Regular security audits (quarterly)
- Dependency scanning (dependabot)
- No hardcoded secrets in repo
- All Rust code passes `cargo clippy --all-targets -- -D warnings`
```

---

## 4. Documentation for Users & Contributors

### README.md (Public-Facing)

```markdown
# Cardano Flutter SDK

Production-grade, open-source Flutter SDK for Cardano blockchain.

[![CI](https://github.com/YOUR_ORG/cardano-flutter-sdk/actions/workflows/ci.yml/badge.svg)](...)
[![Pub Version](https://img.shields.io/pub/v/cardano_flutter)](...)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features
- ✅ Bech32 address generation and validation
- ✅ BIP-32 HD wallet derivation (CIP-1852)
- ✅ Transaction building and signing
- ✅ Smart contract interaction (Plutus V2/V3)
- ✅ NFT minting (CIP-25/68)
- ✅ Multi-platform: iOS, Android, web, macOS, Linux, Windows
- ✅ Built on Emurgo's `cardano-serialization-lib` (canonical CSL)
- ✅ 100% open-source (MIT license)

## Quick Start
[See docs/getting-started.md for full guide]

```bash
flutter pub add cardano_flutter
```

## Contributing
We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Community
- **Discord:** [link]
- **Forum:** https://forum.cardano.org
- **Issues:** [GitHub Issues](../../issues)
- **Discussions:** [GitHub Discussions](../../discussions)

## License
MIT — see [LICENSE](LICENSE) for details.
This project is **open-source and owned by the community.**

## Security
Found a vulnerability? Email security@cardano-flutter-sdk.dev (do not open public issue).
See [SECURITY.md](SECURITY.md) for details.
```

### docs/ARCHITECTURE.md

Deep-dive on the codebase for maintainers:

```markdown
# Architecture Guide

## For Contributors

### Directory Structure
```
rust/
  src/
    lib.rs          — Main FFI surface
    address.rs      — Address validation/generation
    wallet.rs       — Key derivation
    tx.rs           — Transaction building
    ...
  tests/            — Integration tests

dart/
  lib/
    src/
      bridge_generated.dart  — Auto-generated (do not edit)
      cardano_flutter.dart   — Public API
      ...
  test/             — Dart unit tests

docs/
  architecture.md   — This file
  getting-started.md
  ...
```

### Adding a New Function

1. **Implement in Rust** (`rust/src/lib.rs` or dedicated module)
   - Use `#[frb(sync)]` or `#[frb]` for flutter_rust_bridge
   - Return `Result<T, Error>` (no panics)
   - Add inline comments explaining WHY
   
2. **Run code generation**
   ```bash
   flutter_rust_bridge_codegen generate
   ```
   
3. **Add Dart wrapper** (`dart/lib/src/cardano_flutter.dart`)
   - Type-safe wrapper around auto-generated binding
   - Dartdoc comment with usage example
   
4. **Write tests**
   - Rust: `tests/integration_tests.rs` (≥2 tests)
   - Dart: `dart/test/cardano_flutter_test.dart` (≥2 tests)
   
5. **Test locally**
   ```bash
   cargo test && flutter test
   ```
   
6. **Submit PR** with clear commit message

### Modifying an Existing Function

- If signature changes, must bump minor version (v1.1.0 → v1.2.0)
- If only docs/internals change, patch version is OK
- Run tests and regenerate bindings after any Rust change

### Rust + CSL Version Pinning

- CSL is pinned in `Cargo.toml` (e.g., `cardano-serialization-lib = "15.*"`)
- Before bumping CSL major version:
  1. Test against all 3 PoC functions
  2. Run integration tests on testnet
  3. Document any breaking API changes
  4. Bump SDK minor version at least

---

## 5. Making it Discoverable

### Package Publishing

**Dart package (pub.dev):**
```bash
# In dart/ directory
flutter pub publish --dry-run  # Test before real publish
flutter pub publish              # Publish v0.1.0, v0.2.0, etc.
```

**Rust crate (crates.io):**
```bash
# In rust/ directory
cargo publish --dry-run
cargo publish
```

**Documentation:**
- pub.dev auto-generates dartdoc
- crates.io auto-generates Rust docs
- Host custom site at docs.cardano-flutter-sdk.dev (optional)

### Community Visibility

**On Day 1 (Week 1):**
- [ ] Push code to public GitHub repo
- [ ] Publish Phase 1 demo on X (Twitter) with `#Cardano #BuildOnCardano`
- [ ] Post in Cardano Developer Discord: "New open-source Flutter SDK"
- [ ] Create topic on Cardano Forum with architecture overview

**By Week 4 (Phase 1 done):**
- [ ] Publish to pub.dev and crates.io
- [ ] Submit to Awesome Cardano list (https://github.com/input-output-hk/awesome-cardano)
- [ ] Post v0.1.0 release on X with demo video
- [ ] Tag on HackerNews "Show HN: Cardano Flutter SDK"

**Ongoing:**
- [ ] Quarterly release announcements
- [ ] Feature spotlight posts
- [ ] Community contributor spotlight (monthly)
- [ ] CSL upgrade announcements + compatibility notes

### Badges & Social Proof

Add to README:
```markdown
[![GitHub Stars](https://img.shields.io/github/stars/YOUR_ORG/cardano-flutter-sdk?style=social)](...)
[![Pub Version](https://img.shields.io/pub/v/cardano_flutter)](...)
[![Pub Points](https://img.shields.io/pub/points/cardano_flutter)](...)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/YOUR_ORG/cardano-flutter-sdk/actions/workflows/ci.yml/badge.svg)](...)
```

---

## 6. Governance & Maintainership

### Maintainer Model

**Phase 1–4 (v0.1–v1.0):** Core team (you) + review board
- You (founder) as lead maintainer
- 2–3 experienced contributors as reviewers (after they've merged ≥5 PRs)
- Decisions by consensus; you have tie-breaking vote

**Phase 5+ (v1.1+):** Community governance (optional upgrade)
- Consider moving to GitHub org (shared maintainership)
- MAINTAINERS.md file listing all active maintainers
- Clear process for adding/removing maintainers
- Regular maintainer meetings (monthly video call)

### Decision Making

**Small PRs (bug fixes, docs):**
- Single maintainer approval + CI pass = merge

**Larger changes (new APIs, breaking changes):**
- ≥2 maintainer reviews
- Discuss in issue or discussion thread first
- Announce in release notes with migration guide

**Version bumps:**
- Patch (1.0.0 → 1.0.1): bug fixes only
- Minor (1.0.0 → 1.1.0): new features, no breaking changes
- Major (1.0.0 → 2.0.0): breaking changes (rare in v1.x era)

---

## 7. Long-Term Sustainability

### Funding Model

**This is an independent, self-funded project.** No external funders. No grants. No milestone deadlines. Sustainability comes from real usage and contributor goodwill.

**If funding ever becomes useful (not required):**

1. **OpenCollective** (optional, low-pressure)
   - Transparent fund management
   - Donor recognition
   - Use for: hosting costs, occasional contractor work
   
2. **Sponsorships** (optional, only if a partner offers)
   - Exchanges, wallets, dApp platforms using SDK
   - No obligation, no time commitment
   - Sponsor gets logo in README, nothing more
   - Transparency: list sponsors on website
   
### Maintenance Effort (Best Effort, Not SLA)

This is an independent project, so promises are made on a best-effort basis, not formal SLAs:

- **Security bugs:** Highest priority. Aim to fix within days, not weeks.
- **Critical bugs:** Address as time allows; usually within 1-2 weeks.
- **Feature requests:** Reviewed periodically; not all will be implemented.
- **PRs:** Reviewed when time permits.
- **Releases:** When meaningful changes accumulate, not on a fixed schedule.

Setting realistic expectations protects against burnout and dishonest commitments.

---

## 8. Transition to Community Ownership

**If you step back or hand off (later):**

1. **Announce transition** in forum post + release notes
2. **Create MAINTAINERS.md** with new lead(s)
3. **Document decision-making process** in GOVERNANCE.md
4. **Transfer GitHub org** to community (if applicable)
5. **Archive your personal fork** if you step back entirely
6. **Ensure continuity:** month of overlap with new maintainer(s)

**Key principle:** The SDK exists to serve Cardano, not any single person. Plan for succession early.

---

## Checklist for Open-Source Launch

- [ ] MIT license in repo with SPDX headers in all source files
- [ ] CONTRIBUTING.md with setup, testing, submission guidelines
- [ ] CODE_OF_CONDUCT.md (Contributor Covenant v2.1)
- [ ] SECURITY.md with responsible disclosure process
- [ ] GitHub issue templates (bug, feature, question)
- [ ] GitHub PR template with checklist
- [ ] README with contributing link, community channels, security contact
- [ ] MAINTAINERS.md or CONTRIBUTORS.md with attribution
- [ ] .github/workflows/ci.yml running tests on every PR
- [ ] .github/workflows/publish.yml auto-publishing on release
- [ ] Branch protection rules on `main` (require CI pass, ≥1 review)
- [ ] GitHub Discussions enabled
- [ ] Public roadmap (`.claude/goals/PHASES_WITH_VERIFICATION.md`)
- [ ] docs/architecture.md for contributors
- [ ] Publish to pub.dev and crates.io by Phase 1 end
- [ ] List on Awesome Cardano + Cardano Forum
- [ ] Launch docs site (docs.cardano-flutter-sdk.dev or similar)

---

**Last Updated:** 2026-05-24  
**Aligned with:** MIT license, Cardano ecosystem values, open-source best practices
