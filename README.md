# cardano_flutter

A production-grade Flutter SDK for Cardano, built on Emurgo's Cardano Serialization Library (CSL) via Rust FFI.

> **Status:** Pre-development. See [`docs/project-plan.md`](docs/project-plan.md) for the full architecture and 4-phase roadmap.

## Why

The Cardano ecosystem has lacked a production-grade Flutter SDK for 4+ years across 7+ Project Catalyst funding rounds. Existing attempts (e.g., `reaster/cardano_wallet_sdk`) reimplemented Cardano cryptography in pure Dart and have stayed at "not yet production quality" since 2022.

This SDK takes a different approach: wrap `cardano-serialization-lib` (the canonical Rust library, auto-generated from Cardano's CDDL spec) via FFI, then provide an idiomatic Dart API on top. Protocol upgrades flow downstream automatically.

## Architecture

```
┌──────────────────────────────────────────┐
│  Your Flutter app                        │
├──────────────────────────────────────────┤
│  cardano_flutter (Dart package)          │  ← idiomatic, null-safe API
├──────────────────────────────────────────┤
│  flutter_rust_bridge generated bindings  │  ← auto-generated FFI
├──────────────────────────────────────────┤
│  cardano_flutter_rs (Rust wrapper)       │  ← ergonomic wrapper, ~1-2K LOC
├──────────────────────────────────────────┤
│  cardano-serialization-lib v15.x         │  ← Emurgo's canonical lib
└──────────────────────────────────────────┘
```

## Project layout

```
cardano-flutter-sdk/
├── CLAUDE.md           # Claude Code project memory
├── README.md           # this file
├── docs/
│   └── project-plan.md # full strategic plan, roadmap, Catalyst strategy
├── rust/               # Rust wrapper crate (cardano_flutter_rs)
├── dart/               # Dart package (cardano_flutter)
└── example/            # Reference Flutter app
```

## Getting started

```bash
# This project uses Claude Code. Open in your terminal:
cd cardano-flutter-sdk
claude

# Or work directly. First-weekend bootstrap is in docs/project-plan.md §5.
```

## License

MIT (matches CSL upstream).
