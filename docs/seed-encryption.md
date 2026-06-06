# Seed Encryption & Backup — Design + Threat Model (Phase 5b)

> Status: v0.9.1 target. Rust-side at-rest encryption for recovery secrets
> (mnemonic phrases / entropy). All cryptography runs in Rust via FFI — **no
> hand-rolled Dart crypto** (per project policy).

## Goal

Protect a wallet's recovery secret (BIP-39 mnemonic) **at rest** on a mobile
device, so that a copy of the encrypted blob — exfiltrated from app storage, a
device backup, or a stolen-but-locked phone — is useless without the user's
password (and, where wired, a hardware-backed wrapping key).

## Primitives (locked)

| Layer | Choice | Why |
|-------|--------|-----|
| KDF | **Argon2id** | Memory-hard; OWASP-recommended password KDF; resists GPU/ASIC brute force. The `id` variant defends both side-channel and GPU attacks. |
| AEAD | **XChaCha20-Poly1305** | 24-byte random nonce → safe to generate randomly with negligible collision risk (no nonce-reuse footgun of 12-byte GCM/ChaCha). Fast in software on ARM without AES-NI. Authenticated → tamper-evident. |
| CSPRNG | OS entropy (`getrandom`/`OsRng`) | Salt + nonce from the platform CSPRNG. |
| Memory hygiene | `zeroize` | Derived key + plaintext buffers wiped on drop in Rust. |

### Default KDF parameters

`m = 64 MiB, t = 3, p = 1`, 32-byte output.

Rationale: comfortably above OWASP's 2024 floor (19 MiB / t=2) while staying
~sub-second on mobile. Parameters are **embedded in the ciphertext header**, so a
future hardening (e.g. raising memory) does not break existing blobs — decrypt
always uses the params the blob was written with. Callers may override via
`encrypt_seed_with_params`, and `benchmark_kdf` measures cost on the actual
device to tune.

Measured cost (`benchmark_kdf`):

| params | dev Mac (Apple silicon) | iPhone 13 |
|--------|------------------------|-----------|
| 64 MiB / t=3 / p=1 (default) | ~101 ms | **~158 ms** |
| 46 MiB / t=1 / p=1 | ~17 ms | — |
| 19 MiB / t=2 / p=1 (OWASP floor) | ~15 ms | — |

The iPhone 13 default-param figure (**~158 ms**, measured 2026-06-06 via the
example app's Seed Vault screen) is a comfortable one-time unlock latency — well
under the ~300–500 ms we budgeted, so the defaults need no tuning down. The same
on-device run exercised the full hardware-backed round-trip: encrypt → `CFS1`
blob (145 bytes) written to the iOS Keychain → read back → decrypt → exact secret
recovery.

## At-rest container format (`CFS1`)

Self-describing, versioned, little-endian. Returned/accepted as a **hex string**
(matches the codebase's hex-everywhere convention; trivially storable anywhere).

```
off  size  field
0    4     magic            = ASCII "CFS1"
4    1     version          = 0x01
5    1     kdf_id           = 0x01 (Argon2id)
6    4     argon2 mem_kib   (u32 LE)
10   4     argon2 iters     (u32 LE)
14   4     argon2 parallel  (u32 LE)
18   1     salt_len         (= 16)
19   N     salt             (16 bytes)
19+N 24    nonce            (XChaCha20 192-bit nonce)
...  M     ciphertext+tag   (plaintext_len + 16-byte Poly1305 tag)
```

The entire header (`offset 0 .. start-of-ciphertext`) is passed as **AEAD
associated data (AAD)**. Consequence: flipping any version byte, KDF parameter,
salt, or nonce makes authentication fail — an attacker cannot downgrade the KDF
cost or swap the salt without detection.

## What it protects against (in scope)

- **Offline brute force of an exfiltrated blob.** Argon2id makes per-guess cost
  high (memory-hard); a strong password is infeasible to crack offline.
- **Tampering / bit-flipping** of the stored blob — Poly1305 tag + AAD-bound
  header → decrypt fails closed.
- **KDF-downgrade attacks** — params are authenticated (AAD), not just advisory.
- **Nonce reuse** — 192-bit random nonces; reuse probability is negligible.
- **Wrong password** — indistinguishable from tamper (both → AEAD failure); no
  oracle that says "password right, data corrupt."

## What it does NOT protect against (out of scope — stated honestly)

- **A compromised runtime / rooted-or-jailbroken device while unlocked.** Once
  the user enters the password and the mnemonic is decrypted into process memory,
  malware with code execution in the app can read it. At-rest encryption is not
  runtime sandboxing.
- **Weak user passwords.** Argon2id raises the cost per guess; it cannot save a
  4-digit PIN used as the sole secret. The wrapping-key path (below) is the
  mitigation — bind decryption to hardware so the password alone is insufficient.
- **The decrypted secret crossing the FFI boundary.** `decrypt_seed` returns a
  `String` to Dart; Dart strings are immutable and GC-managed and **cannot be
  reliably zeroized**. Rust wipes its own copies; the Dart-side lifetime is the
  caller's responsibility (use immediately, avoid logging, drop references).
- **Screen capture, keyloggers, shoulder-surfing** of password entry.
- **Coercion / rubber-hose.** No plausible-deniability / hidden-volume scheme.

## Platform secure storage (wrapping-key path)

Password-only encryption is the baseline. Where available we additionally bind to
hardware-backed storage so an exfiltrated blob is useless **even with the
password**, and so a strong random key can replace a weak password:

- **iOS Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, optionally
  Secure Enclave / biometric ACL) holds a random 32-byte **wrapping key**.
- **Android Keystore** (StrongBox where present, `setUserAuthenticationRequired`)
  holds the equivalent.

Composition: the example composes the user password with the hardware wrapping
key **at the input to Argon2id** — `Argon2id(password ‖ 0x1F ‖ wrapSecretHex)` —
using an ASCII Unit-Separator (`0x1F`, which cannot appear in a password text
field or in lowercase hex) so the concatenation is unambiguous. Feeding both
secrets through the memory-hard KDF means decryption requires *both* device
possession (the Keychain/Keystore wrap secret) and the password. This is
integrated in the **example app** via `flutter_secure_storage` (kept out of the
core package to preserve the minimal FFI surface); the core ships the
password-based primitives that the wrapping-key layer composes over.

> Note on the "useless without the device" claim: it holds against a **blob-only**
> leak (e.g. an iCloud/file backup that excludes the Keychain — iOS
> `ThisDeviceOnly` accessibility enforces this). It does *not* help if an attacker
> compromises the secure store itself, since the example stores the encrypted blob
> and the wrap secret in the same `FlutterSecureStorage`.

> Implementation note: the core SDK exposes `encrypt_seed`/`decrypt_seed`
> (+ `_with_params`) and `benchmark_kdf`. The Keychain/Keystore wiring lives in
> the example to demonstrate the recommended composition without dragging a
> platform-storage dependency into the library.

## Verification (Phase 5b gate)

- [ ] Encrypt → drop key → decrypt round-trip recovers the exact mnemonic
- [ ] Wrong password → `AEAD failure` error (no partial plaintext, no panic)
- [ ] Tamper any header/ciphertext byte → decrypt fails
- [ ] KDF params round-trip through the header (decrypt ignores caller params)
- [ ] Distinct salt+nonce per call → two encryptions of the same input differ
- [ ] KDF benchmarked on iPhone 13; default params documented here
- [ ] Security review of this format (folded into the Phase 7 review pass)
```

