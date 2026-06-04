# Hardware wallets (Ledger / Trezor) — Phase 4.5

> **Status (2026-06-03):** Core protocol layer **complete & unit-tested**; example
> Ledger BLE integration **code-complete, including transaction signing**; the
> signing path is **awaiting verification on a physical Ledger** (no device
> available yet). v1.0.0 is *not* published — the phase's v1.0 gate ("Ledger TX
> signing round-trip verified on device") is intentionally still open. No
> "verified" claim is made for anything that hasn't run on hardware.

## What ships in the core SDK (tested, device-agnostic)

A hardware wallet never exposes private keys. It returns a BIP-32 *account
extended public key* (xpub) and, on request, signs and returns raw vkey
witnesses. The SDK provides the pure primitives to make that usable:

| Primitive | Purpose |
|-----------|---------|
| `xpubToAccount(accountXpubHex, networkId)` | Soft-derive base + reward addresses and payment/stake key hashes from the account xpub (CIP-1852 roles 0 & 2, index 0). No private keys — also serves watch-only wallets. |
| `xpubDerivePublicKey(accountXpubHex, role, index)` | Soft-derive a single raw Ed25519 public key at `role`/`index`. Symmetric with `xpubToAccount`; used to rebuild a vkey witness from a device's `(path, signature)` pair (the device returns no public key). |
| `decomposeTxBody(txBodyCborHex)` | CSL-parse a transaction body into device-signable primitives (inputs, outputs with ADA + native tokens, fee, ttl, validity start, network id) plus a `hasUnsupportedFeatures` flag. The device adapter maps these into its own structured signing request. |
| `assembleVkeyWitnessSet(witnesses)` | Fold device `(publicKey, signature)` pairs into a CBOR `transaction_witness_set`. |
| `extractVkeyWitnesses(witnessSetCborHex)` | Inverse of the above — pull raw pairs out of a witness set (partial-sign / multi-sig / cosigner merging). |
| `HardwareWallet` (interface) | Device-agnostic contract: `getAccountXpub`, `signTransaction`. Implemented per device outside the core. |
| `HardwareCip30Wallet` | CIP-30-shaped wallet whose keys live on a device: addresses derived locally from the xpub, balance/UTxO queries via a provider, signing delegated to the device + assembled into a submittable tx. |

These are proven in `rust/src/hardware.rs` (Rust unit tests, incl. that public
soft-derivation lands on the *same* credentials as the private mnemonic path,
and an assemble↔extract identity over a real Ed25519 signature) and
`dart/test/hardware_test.dart` (incl. a **real-crypto round-trip**: software-sign
a tx → extract its witnesses → feed them to a mock device → `HardwareCip30Wallet`
assembles a transaction **byte-identical** to the software-signed one).

## What ships in the example (Ledger over BLE)

`example/lib/ledger_hardware_wallet.dart` implements `HardwareWallet` on top of
Vespr's MIT-licensed [`ledger_cardano_plus`](https://github.com/vespr-wallet/ledger-cardano-plus)
(Cardano Ledger-app APDU protocol) + [`ledger_flutter_plus`](https://github.com/vespr-wallet/ledger-flutter-plus)
(BLE/USB transport). `example/lib/ledger_screen.dart` is the demo screen.

**Working today (logic verifiable without a device):**
- Scan & connect to a Ledger over BLE; read the Cardano-app version.
- `getAccountXpub` → `publicKeyHex + chainCodeHex` (the 64-byte account xpub).
- `HardwareCip30Wallet.fromDevice` → derive base/reward addresses locally and
  query balance/UTxOs through Blockfrost.

**Implemented, awaiting on-device verification:**
- `LedgerHardwareWallet.signTransaction` is now implemented. The Cardano Ledger
  app does not sign raw CBOR — it is handed a structured `ParsedSigningRequest`
  (`ParsedTransaction`: inputs, outputs, fee, ttl, …) and returns
  `Witness(path, signatureHex)` pairs that carry **no public key**. The adapter:
  1. decomposes the SDK body with `decomposeTxBody` (authoritative CSL parse);
  2. refuses bodies with `hasUnsupportedFeatures` (certs/withdrawals/mint/
     collateral/reference inputs/votes) — only ordinary payments are mapped;
  3. maps inputs/outputs/fee/ttl into `ParsedSigningRequest`. Plain outputs use
     `ParsedOutput.alonzo` (legacy array format) to match CSL's serialization so
     the device's recomputed body hash equals ours — **this format assumption is
     the single most likely thing to need adjustment on real hardware**;
  4. rebuilds each `HardwareVkeyWitness` by re-deriving the path's public key via
     `xpubDerivePublicKey(accountXpub, role, index)`.
- A device-free test (`hardware_test.dart` → "device witness reconstruction")
  proves step 4 with a **real** software signature: it discards the pubkey, keeps
  only `(path, signature)`, re-derives the pubkey from the xpub, and asserts the
  assembled tx is **byte-identical** to the software-signed reference.
- **Still unverified on hardware:** the `ParsedTransaction` ↔ CSL body byte
  match (output format, multi-asset/canonical ordering), and the on-device UX.
  The signing path therefore is **not** treated as verified until the checklist
  below is run on a physical Ledger.

## Why Trezor is deferred

Trezor has no BLE and is USB-only; its mobile integration relies on the
web-based Trezor Connect bridge, which is impractical on a phone (and would need
a WebView bridge similar to the CIP-45 transport). Ledger (BLE) is the realistic
mobile hardware wallet, so v1.0 targets Ledger; Trezor is a future follow-up.

## On-device signing checklist (to close the v1.0 gate)

The mapping is implemented (`xpubDerivePublicKey` + `decomposeTxBody` in
`rust/src/hardware.rs`; `LedgerHardwareWallet.signTransaction` in the example).
When a physical Ledger (Nano X / Stax / Flex) is available, verify:

1. **Read path** — scan → connect → confirm the derived base address matches the
   device's own `deriveReceiveAddress`/`deriveChangeAddress`. (Sanity-checks
   `xpubToAccount` against the device.)
2. **Round-trip** — use the example's **"Sign 1 ₳ → self"** button on the Ledger
   screen: it builds a 1-ADA self-payment from the wallet's UTxOs on **preview**,
   has the device sign, assembles, submits, and logs the tx hash. Confirm:
   - the device displays the correct outputs/fee (the body decomposition is faithful);
   - submission succeeds — i.e. the device-signed body hash matched ours (this is
     where the `ParsedOutput.alonzo` / output-format assumption is validated; if
     submission fails with a witness/hash error, the output format or canonical
     ordering is the first suspect — see step "implemented" notes above);
   - the tx confirms on-chain. Capture the tx hash.
3. **Multi-asset** — repeat with an output carrying a native token to exercise the
   `tokenBundle` mapping and asset-group ordering.
4. **Update status** — only then mark the gate closed and the read+sign path
   "verified on device", and publish v1.0.0.

## Platform configuration

- **iOS:** `NSBluetoothAlwaysUsageDescription` /
  `NSBluetoothPeripheralUsageDescription` are set in
  `example/ios/Runner/Info.plist`.
- **Android:** add `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (and, pre-Android-12,
  location) permissions to the app manifest; the screen requests them at runtime
  via `permission_handler`.
