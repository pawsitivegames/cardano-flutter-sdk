# COSE / CIP-30 cross-implementation interop vectors

Generates `signData` (`COSE_Sign1` + `COSE_Key`) vectors **outside** this crate,
using Emurgo's reference WASM libraries — the same COSE/CIP-8 implementation that
Lace, Eternl, Nami and MeshJS use — and CSL-nodejs for key derivation from the
shared test mnemonic.

The frozen output (`vectors.json`) is embedded in `rust/src/cip30.rs` tests as a
regression gate: the hardened `cip30_verify_data` (CSL-based identity binding)
must **accept** a genuine wallet-shaped signature for both address forms a wallet
emits — a base address signed by the payment key, and a reward (stake) address
signed by the stake key — and **reject** a mismatched COSE_Key.

```bash
cd tools/cose-interop
npm install
npm run gen        # prints + can be redirected to vectors.json
```

`node_modules/` is intentionally not committed; `npm install` reproduces it.
