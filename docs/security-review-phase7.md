# Phase 7 — Pre-1.0 Security Review

> Date: 2026-06-06. Scope: secret/key handling, COSE/CIP-8 message signing,
> fee/coin-selection/tx-building, seed-at-rest (`CFS1`) encryption. Method: four
> focused audits against the **actual code** (not docs), each finding then
> re-verified by hand at the cited `file:line` (per the project rule: verify
> security claims against code, never trust a doc/agent claim alone).

Severity scale: **critical** (arbitrary fund loss / key compromise) · **high**
(bounded fund loss, forgery, or rejected/stuck tx on a normal path) · **medium**
(DoS, defense-in-depth gap reachable by attacker input) · **low/info** (hardening,
fidelity).

---

## Summary

The **cryptographic cores are sound.** The COSE/CIP-8 identity-binding path is
genuinely implemented and enforced at both sign and verify, in both the native
(CSL) and web (CML-JS) backends, regression-locked by tests including a real
captured wallet vector — the historical commit-026e696 "doc claims binding the
code lacks" gap does **not** recur. The `CFS1` AEAD construction (XChaCha20-Poly1305
+ Argon2id, fresh per-call salt/nonce, AAD-bound KDF params, fails-closed) is
correct.

The real work is in **transaction building**: a double-change/double-fee seam
between `selectCoinsForTransaction` and `build_tx` that can leak dust to fee and
produce inconsistent fee previews (same *class* as the native-token-drop bug fixed
during Phase 6), plus two attacker-input hardening gaps in `decrypt_seed`.

No **critical** issues found.

---

## Findings (verified)

### TX-1 [high] Double change/fee: selection change is passed as an explicit output, then `build_tx` adds change again
`rust/src/tx.rs:226` calls `add_change_if_needed` **unconditionally**, while the
canonical call pattern (`example/lib/send_screen.dart:136,262`,
`example/lib/ledger_screen.dart:137`, `dart/test/providers/blockfrost_live_test.dart`,
`example/integration_test/send_flow_test.dart:143`) passes
`selectCoinsForTransaction`'s `changeOutputs` **into** `outputs`. So the selector's
change becomes a locked explicit output and CSL balances the remainder with a
*second* change engine using a *different* (real) fee. CSL conserves value, so this
is not arbitrary loss — but when the residual is below min-ADA, CSL folds it into
**fee** (bounded dust loss on normal sends), and otherwise emits a redundant second
change output (tx bloat) and a fee preview that disagrees with the built fee.
Verified live: my 2026-06-06 on-chain send succeeded only because the two fee
estimates coincided at ~0 residual — luck, not correctness.
**Fix:** one engine. Pass only `selectedInputs` + `targetOutputs` to
`buildTransaction` and let `add_change_if_needed` create the single change output
(CSL's intended use); keep `selectCoinsForTransaction` for input choice + fee
preview. Add an end-to-end test asserting `sum(inputs) == sum(body outputs) +
body.fee()` including native assets. (Not covered by the conformance suite, which
is serialization-only — that's why it slipped.)

### SEED-1 [medium] `decrypt_seed` runs Argon2id on attacker-controlled params before authentication (DoS)
`rust/src/seed.rs:230-232,252` parses `mem_kib`/`iterations`/`parallelism` from the
blob and calls `derive_key` (the expensive KDF) at line 252 **before** the AEAD tag
is checked (line 256+). A crafted blob with `mem_kib = 0xFFFFFFFF` triggers a
multi-terabyte allocation / hang. `decrypt_seed` is a public FFI API, so any blob
an app is handed can freeze/OOM it. AAD doesn't help — the KDF runs first.
**Fix:** validate parsed params immediately after parsing — reject `mem_kib == 0`,
`mem_kib > 2 GiB` (`2*1024*1024` KiB), `iterations == 0`, `iterations > 100`,
`parallelism == 0`/absurd — returning `CardanoError` before `derive_key`.

### SEED-2 [low] `salt_len` is read from the blob but never validated `== 16`
`rust/src/seed.rs:233` trusts the attacker-supplied `salt_len`. The bounds check at
:237 prevents OOB and the AAD makes a wrong value fail authentication, so this is
not forgery/key-weakening — but it contradicts the documented invariant
(`docs/seed-encryption.md:62` "salt_len (= 16)") and lets obviously-malformed input
reach the KDF. **Fix:** `if salt_len != SALT_LEN { reject }` right after :233.

### COSE-1 [medium] Legacy `message.rs` `sign_message`/`verify_message` bind against an *unsigned* address field
`rust/src/message.rs:146-212`: the custom (non-COSE) structure signs only the
message hash; `public_key` and `address` are caller-supplied and outside the
signature, so the "binding" is weaker than the COSE path's protected-header binding.
It's loudly documented as legacy/non-interop, but it remains a `pub` FFI export, so
an integrator could use it for auth and inherit the weaker semantics.
**Fix:** deprecate `sign_message`/`verify_message` in the public API (dartdoc
`@Deprecated` + a clear note that the address is **not** cryptographically bound,
unlike `cip30VerifyData`); consider feature-gating.

### TX-2 [medium] Unchecked `u64` accumulation of asset/coin sums in coin selection
`rust/src/coin_selection.rs:119-127,302-310` sum per-asset `u64` quantities with
`+=`. A high-supply token spread across many UTxOs whose **sum** exceeds `u64::MAX`
overflows (debug: panic; release: wrap → conservation violated). Single-UTxO values
are u64-bounded on-chain, so only aggregation is reachable. Also the Dart→Rust
boundary (`putBigUint64`) silently truncates a `BigInt ≥ 2^64`.
**Fix:** `checked_add` in the accumulation loops → `CardanoError` on overflow; in
`utxoToTxInput` (Dart) reject `BigInt > u64::MAX` before FFI.

### TX-3 [medium] No TTL default — txs are valid forever
`rust/src/tx.rs:217-219` sets a validity interval only if `ttl` is `Some`; the
example send path passes `ttl: null` (`send_screen.dart:138,265`). A no-TTL tx never
expires — a delayed/retried submission can confirm much later than intended and
can't be safely replaced. **Fix:** the reference example should fetch the tip slot
and set `ttl = slot + ~7200`; document that production callers must set a TTL.

### SEC-1 [medium] Committed Blockfrost dev key in two example files
`example/lib/main.dart:56` (has `// TODO: remove before release`) and
`example/lib/web_cip30_screen.dart:28` (`_devKey`, **no** TODO — easy to miss in the
release sweep). It's a rate-limited credential already in git history.
**Fix:** before `0.12.0`, require `String.fromEnvironment('BLOCKFROST_PROJECT_ID')`
in both, fail loudly when empty, rotate the key on Blockfrost, and add a
`git grep previewAmnr` release-gate check.

### COSE-2 [low] Verify does not assert `alg == EdDSA`
`rust/src/cip30.rs:386-442`, `dart/lib/src/conformance/cml_web_backend.dart:454-511`.
Not exploitable (the pubkey is forced through Ed25519 `from_bytes` and verification
is hard-wired to Ed25519 — no suite agility), but spec-strictness/defense-in-depth.
**Fix:** assert the protected-header `alg` is EdDSA and reject otherwise, both
backends.

### COSE-3 [low] Empty/absent COSE payload verifies silently when caller passes no expected payload
`rust/src/cip30.rs:379` (`unwrap_or_default()`), web `:470`. Robustness corner;
CIP-30 signData always carries a payload. **Fix:** treat absent payload as an error
when no `expected_payload_hex` is pinned, or document the requirement.

### SEED-3 [low, accepted] Decrypted secret crosses FFI as an un-zeroizable Dart `String`
`rust/src/seed.rs:272-275` — honestly disclosed in code + `docs/seed-encryption.md`.
Rust-side plaintext is `Zeroizing`; the returned `String` cannot be wiped by Dart.
Acceptable to defer past 1.0 if it stays in the public security model. **Future:**
return `Uint8List` (zeroable) or keep decrypt+derive entirely in Rust.

---

## Verified correct (no action)

- **COSE/CIP-8 identity binding is real and enforced** — bound in the *protected*
  (signed) header at sign (`cip30.rs:316-321`), checked before trusting the
  signature at verify (`cip30.rs:412-440` native, `cml_web_backend.dart:484-508`
  web), Ed25519 signature actually verified over a reconstructed Sig_structure.
  Regression-locked: forged-identity rejection (`cip30.rs:669-697`), swapped-key on
  a real external vector (`:846-859`), real Eternl mainnet vector accepted
  (`:876-891`), tamper/wrong-payload golden vectors. Native and web are equivalent.
- **`CFS1` AEAD** — XChaCha20-Poly1305, fresh 16-byte salt + 24-byte nonce per call
  via `OsRng` (`seed.rs:170-173`), KDF params + full header bound as AAD
  (`:179-186`/`:246,262`) so KDF-downgrade tampering fails closed, authenticate-
  before-use, key + plaintext `Zeroizing`. Argon2id v0x13, defaults 64 MiB/t=3/p=1.
- **Multi-asset value conservation in `value_to_csl`** (`tx.rs:89-122`, merges
  per-policy assets; CIP-68 regression test) and `utxoToTxInput` (carries all
  assets — the Phase 6 drop-assets fix). Coin selection terminates (80-input cap),
  fails safely on empty/insufficient, never emits coin=0 asset outputs *in
  isolation* (the break is the TX-1 integration seam).
- **Secret hygiene** — no private key/mnemonic/entropy is logged, formatted into
  errors, or rendered (only public xpubs, truncated, in the example UI); the only
  `println!`s are in `#[cfg(test)]`; secure-storage composition uses a real `0x1f`
  separator (injection-safe) and `Random.secure()`. No committed secrets beyond the
  known Blockfrost dev key. The public Cardano test mnemonic is fine.

---

## Doc-vs-code fidelity

No "doc claims a security property the code lacks" mismatches in the COSE or AEAD
*security properties*. The one fidelity gap: `docs/seed-encryption.md:62` presents
`salt_len = 16` as fixed, but decrypt doesn't enforce it (SEED-2).

---

## Recommended fix order before 0.12.0 RC

1. **TX-1** (double change) — correctness + value leak; add the end-to-end
   conservation test.
2. **SEED-1** (KDF DoS clamp) — public-API DoS on attacker input.
3. **TX-2** (`checked_add` overflow), **SEED-2** (`salt_len`), **COSE-2/3**
   (alg + empty payload) — additive hardening, low risk.
4. **COSE-1** (deprecate legacy `message.rs`), **TX-3** (TTL default in example),
   **SEC-1** (example key cleanup) — API/release hygiene.

---

## Resolution (2026-06-06)

All findings except the accepted SEED-3 were fixed in the same pass and verified.

| ID | Status | Fix |
|----|--------|-----|
| TX-1 | ✅ fixed | Call sites pass only target outputs; `build_tx`'s `add_change_if_needed` is the single change engine (`send_screen`, `ledger_screen`, `send_flow_test`, `blockfrost_live_test`, `wrappers` doc). **Re-verified on-chain** from the macOS build (tx `a4f7d589…`, 1 input → 2 outputs, value conserved). |
| SEED-1 | ✅ fixed | `validate_kdf_params` clamps mem/iters/parallelism on **both** encrypt and decrypt, before `derive_key` (`seed.rs`). Tests: `decrypt_rejects_oversized_mem_param`, `encrypt_rejects_oversized_mem_param`. |
| SEED-2 | ✅ fixed | `salt_len != SALT_LEN` rejected early (`seed.rs`). Test: `decrypt_rejects_bad_salt_len`. |
| COSE-1 | ✅ fixed | `sign_message`/`verify_message` dartdoc now states they're legacy and the address is **not** cryptographically bound; steers to `cip30_*`. |
| TX-2 | ✅ fixed | `checked_sum` on all coin/asset accumulation (`coin_selection.rs`); Dart `utxoToTxInput` rejects `BigInt > u64::MAX` before FFI. |
| TX-3 | ✅ fixed | `BlockfrostProvider.fetchTipSlot()` added; example send sets `ttl = tip + 7200`. |
| SEC-1 | ✅ fixed | Dev key centralized in `example/lib/dev_config.dart` as a **debug-only** fallback (release builds embed no key, fail loud); env override first. **Action still required: rotate the key on Blockfrost** (it's in git history) before public release. |
| COSE-2 | ✅ fixed | Verify asserts protected-header `alg == EdDSA (-8)` in native (`cip30.rs`) and web (`cml_web_backend.dart`). Web gate re-run: PASS 32/32. |
| COSE-3 | ✅ fixed | Absent payload with no pinned `expected_payload_hex` now fails closed (native + web). |
| SEED-3 | ⏸ accepted | Decrypted secret crosses FFI as a `String`; documented, deferred past 1.0. |

Verification after fixes: Rust 138/138 (clippy + fmt clean), Dart 178 passed / 4
skipped, web in-browser conformance PASS 32/32, macOS send-tx re-broadcast
confirmed on-chain. One residual owner action: **rotate the Blockfrost dev key**.
