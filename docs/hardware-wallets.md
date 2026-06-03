# Hardware wallets (Ledger / Trezor) — Phase 4.5

> **Status (2026-06-02):** Core protocol layer **complete & unit-tested**; example
> Ledger BLE integration **code-complete (read path)**; **on-device signing
> awaiting verification on a physical Ledger** (no device available yet). v1.0.0
> is *not* published — the phase's v1.0 gate ("Ledger TX signing round-trip
> verified on device") is intentionally still open. No "verified" claim is made
> for anything that hasn't run on hardware.

## What ships in the core SDK (tested, device-agnostic)

A hardware wallet never exposes private keys. It returns a BIP-32 *account
extended public key* (xpub) and, on request, signs and returns raw vkey
witnesses. The SDK provides the pure primitives to make that usable:

| Primitive | Purpose |
|-----------|---------|
| `xpubToAccount(accountXpubHex, networkId)` | Soft-derive base + reward addresses and payment/stake key hashes from the account xpub (CIP-1852 roles 0 & 2, index 0). No private keys — also serves watch-only wallets. |
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

**Pending on-device verification:**
- `LedgerHardwareWallet.signTransaction` currently throws. Reason: the Cardano
  Ledger app does not sign raw CBOR — it must be handed a structured
  `ParsedSigningRequest` (`ParsedTransaction`: inputs with their address
  derivation params, outputs, fee, ttl, certificates, …), and it returns
  `Witness(path, signatureHex)` pairs that carry **no public key**. Turning those
  into `HardwareVkeyWitness` requires deriving each path's public key from the
  account xpub. That structured mapping is error-prone and must be validated
  against real hardware, so it is **not shipped unverified**.

## Why Trezor is deferred

Trezor has no BLE and is USB-only; its mobile integration relies on the
web-based Trezor Connect bridge, which is impractical on a phone (and would need
a WebView bridge similar to the CIP-45 transport). Ledger (BLE) is the realistic
mobile hardware wallet, so v1.0 targets Ledger; Trezor is a future follow-up.

## On-device signing checklist (to close the v1.0 gate)

When a physical Ledger (Nano X / Stax / Flex) is available:

1. **Read path** — scan → connect → confirm the derived base address matches the
   device's own `deriveReceiveAddress`/`deriveChangeAddress`. (Sanity-checks
   `xpubToAccount` against the device.)
2. **Implement `signTransaction`** in `ledger_hardware_wallet.dart`:
   - Map the SDK transaction → `ParsedSigningRequest`/`ParsedTransaction`.
   - Call `_connection.signTransaction(parsed)`.
   - For each returned `Witness`, derive its path's public key from the account
     xpub (add a Rust `xpubDerivePublicKey(accountXpubHex, role, index)` helper
     returning the 32-byte raw pubkey hex — symmetric with `xpubToAccount`),
     then build `HardwareVkeyWitness(vkeyHex, signatureHex)`.
   - `HardwareCip30Wallet.signTransaction` already assembles + returns the tx.
3. **Round-trip** — build a small payment on **preview**, sign on device, submit,
   and confirm on-chain. Capture the tx hash.
4. **Update status** — only then mark the gate closed and the read+sign path
   "verified on device", and publish v1.0.0.

## Platform configuration

- **iOS:** `NSBluetoothAlwaysUsageDescription` /
  `NSBluetoothPeripheralUsageDescription` are set in
  `example/ios/Runner/Info.plist`.
- **Android:** add `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (and, pre-Android-12,
  location) permissions to the app manifest; the screen requests them at runtime
  via `permission_handler`.
