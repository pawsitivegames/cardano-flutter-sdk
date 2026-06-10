# Cross-wallet `verifyData` interop check (Phase 6)

**Goal:** prove our CIP-30 `verifyData` accepts a message signed by a *real*
third-party wallet (Lace, Eternl, …), not just signatures our own `signData`
produced. This is the in-our-control external-interop signal in the RC gate
(`docs/PLAN.md`).

It needs no web build and no hardware — just a browser wallet extension and ~10
minutes. The verify side is fully automated: paste the wallet's output into a
fixture and a test asserts it verifies (and that a tampered copy is rejected).

Current status: the fixture already includes a real Eternl mainnet vector. Use
the steps below to add more Lace/Eternl/Nami vectors over time.

## What you capture

A CIP-30 `signData(addr, payload)` call returns `{ signature, key }` — a
`COSE_Sign1` and a `COSE_Key`, both hex. You capture those two hex strings plus
the `payload` hex you signed (and, optionally, the signer address hex).

## Steps

1. Open any CIP-30 dApp playground in a browser with Lace or Eternl installed —
   e.g. the Cardano **cardano-signer** / **cip30 dApp** demos, or your own page.
   (You can also just use the extension's devtools console on a connected dApp.)

2. In the page console, connect and sign a known payload. Example with the
   injected API (works for Lace/Eternl; `cardano.lace` / `cardano.eternl`):

   ```js
   const api = await window.cardano.lace.enable();   // or .eternl
   const [addrHex] = await api.getUsedAddresses();    // hex address
   // payload = hex of the bytes you want to sign. "hello" = 68656c6c6f
   const payloadHex = '68656c6c6f';
   const sig = await api.signData(addrHex, payloadHex);
   console.log(JSON.stringify({ addrHex, payloadHex, ...sig }, null, 2));
   // → { addrHex, payloadHex, signature: "<COSE_Sign1 hex>", key: "<COSE_Key hex>" }
   ```

   > Some wallets pop a confirmation dialog — approve it. Eternl may return the
   > address from `getUsedAddresses()` already hex; if you have a bech32 address,
   > convert it with our `addressToHex(addressBech32: ...)`.

3. Add the captured values to `dart/test/fixtures/cross_wallet_signatures.json`,
   appending an object to the `signatures` array:

   ```json
   {
     "signatures": [
       {
         "wallet": "lace 1.20",
         "network": "mainnet",
         "message": "hello",
         "payloadHex": "68656c6c6f",
         "addressHex": "<addrHex from step 2, optional>",
         "signature": "<signature hex>",
         "key": "<key hex>"
       }
     ]
   }
   ```

4. Run the gate:

   ```bash
   cd dart && flutter test test/cross_wallet_verify_test.dart
   ```

   It asserts the signature **verifies** under native `verifyData` (with identity
   binding to the header address) and that a **tampered** payload is rejected.
   While the array is empty the test skips, so CI stays green until you add one.

## What a pass proves

- Our `COSE_Sign1` parsing + `Sig_structure` reconstruction match the wallet's.
- Our Ed25519 verification accepts a real-world signature.
- Our identity-binding (key → header-address credential) agrees with how shipping
  wallets populate the protected-header `address`.

If verification *fails*, that is a real interop finding — capture the raw
`signature`/`key` hex in the fixture (with `"expectAccept": false` so CI records
it) and open an issue; it usually means a COSE protected-header or address-binding
difference worth reconciling against the wallet.
