# CML ↔ CSL conformance spike

A Node harness that proves the **CML** library (the web backend's engine)
reproduces the frozen **CSL** golden CBOR vectors
(`dart/test/conformance/golden_cbor.json`) **byte-for-byte**.

This is the de-risking step behind the web backend: web has no Rust FFI, so the
same Dart API is served by CML-via-JS-interop instead of CSL-via-FFI. "CML and
CSL produce the same bytes" is an assumption a one-byte divergence in an address
or witness set would turn into an interop bug — so it is **proven here**, not
trusted.

## Run

```bash
cd tool/cml_conformance_spike
npm install
node harness.mjs       # expect: PASS 24  FAIL 0  SKIP(unimpl ops) 0  / 24
```

It runs against the **nodejs** CML build, whose WASM core is identical to the
`@dcspark/cardano-multiplatform-lib-browser` bundle the Dart `CmlWebBackend`
binds — so byte-equality proven here transfers to the browser. (What this does
*not* prove: the Dart JS-interop wiring + a real Flutter web build. That gate is
tracked in `docs/web-backend.md`.)

## What it found (baked into `CmlWebBackend`)

Two CML↔CSL encoding divergences had to be resolved for parity — do not
"simplify" them out of the Dart backend:

| Op | CML default | CSL-matching call |
|----|-------------|-------------------|
| Plutus constr / list | definite-length arrays (`d87981…`, `82…`) | `to_cardano_node_format()` → indefinite (`d8799f…ff`, `9f…ff`) |
| `Value` multi-asset | insertion order | `to_canonical_cbor_hex()` → length-then-lexicographic key sort |

It also confirmed CML's deterministic Ed25519 + `cardano-message-signing`
produce a **byte-identical** `COSE_Sign1` + `COSE_Key` to CSL's for the CIP-30
`signData` vector — the interop-critical path.

The proven call sequences are transcribed in
`dart/lib/src/conformance/cml_web_backend.dart`.
