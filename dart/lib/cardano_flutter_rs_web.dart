/// cardano_flutter_rs — **web** entrypoint (scoped CML-JS backend).
///
/// Flutter web has no Rust FFI (Rust→WASM is banned by project policy), so the
/// web surface is satisfied by `cardano-multiplatform-lib` compiled to JS/WASM
/// via Dart JS interop. Import THIS library on web instead of the native barrel
/// (`cardano_flutter_rs.dart`) — it deliberately re-exports only the web-safe
/// subset and never pulls in `dart:ffi`, so it compiles under dart2js.
///
/// Scope (RC, deliberately reduced — see `docs/web-backend.md`):
///   • address derivation, balance / UTxO read, CIP-30 `signData` / `submitTx`
///   • the CSL↔CML conformance contract ([CmlWebBackend])
/// Full tx-building is out of scope on web for the RC.
///
/// The host page must load the CML + message-signing browser WASM and expose
/// them on `globalThis.CML` / `globalThis.MS`, plus a BIP-39 bridge on
/// `globalThis.CFL_mnemonicToEntropy` (see `example/web/index.html`).
///
/// ```dart
/// import 'package:cardano_flutter_rs/cardano_flutter_rs_web.dart';
///
/// final wallet = await WebCip30Wallet.fromMnemonic(
///   mnemonic: mnemonic,
///   provider: BlockfrostProvider(projectId: id, network: Network.testnetPreview),
///   isTestnet: true,
/// );
/// ```
library cardano_flutter_rs_web;

// Scoped CIP-30 web wallet (CML-JS + Blockfrost REST).
export 'src/web/web_cip30_wallet.dart';

// The CML-via-JS-interop conformance backend (deterministic ser/sign ops).
export 'src/conformance/cml_web_backend.dart';

// The platform-agnostic conformance contract (no FFI, no js_interop).
export 'src/conformance/conformance_contract.dart';

// Chain-data providers — pure-Dart REST, already web-capable.
export 'src/providers/blockfrost.dart';
export 'src/providers/blockfrost_errors.dart';
