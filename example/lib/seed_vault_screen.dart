import 'dart:math';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Phase 5b example: at-rest seed encryption with a hardware-backed wrapping key.
///
/// Demonstrates the recommended composition (see `docs/seed-encryption.md`):
///
/// 1. A random 32-byte **wrapping secret** is stored in platform secure storage
///    (iOS Keychain / Android Keystore) — bound to the device, not the password.
/// 2. The Argon2id password is composed as `userPassword␟wrappingSecretHex`, so
///    decryption needs **both** the user's password *and* device possession.
///    (Composition is plain input encoding — all cryptography stays in Rust.)
/// 3. `encryptSeed` (Argon2id + XChaCha20-Poly1305, in Rust) produces the
///    `CFS1` blob, which is also persisted in secure storage.
///
/// An exfiltrated blob alone is useless: without the Keychain/Keystore secret an
/// attacker cannot even begin the password search.
class SeedVaultScreen extends StatefulWidget {
  const SeedVaultScreen({super.key});

  @override
  State<SeedVaultScreen> createState() => _SeedVaultScreenState();
}

class _SeedVaultScreenState extends State<SeedVaultScreen> {
  static const _kBlob = 'cfs_vault_blob';
  static const _kWrap = 'cfs_vault_wrap_secret';
  // ASCII unit separator (0x1f) — cannot appear in a password or hex string,
  // so password‖secret composition is unambiguous.
  static const _sep = '';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  final _mnemonicCtrl = TextEditingController(
    text: 'test walk nut penalty hip pave soap entry language right filter choice',
  );
  final _passwordCtrl = TextEditingController();

  bool _busy = false;
  bool _hasVault = false;
  String? _status;
  String? _error;
  String? _revealed;

  @override
  void initState() {
    super.initState();
    _refreshVaultState();
  }

  @override
  void dispose() {
    _mnemonicCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshVaultState() async {
    final blob = await _storage.read(key: _kBlob);
    if (mounted) setState(() => _hasVault = blob != null);
  }

  void _clear() => setState(() {
        _status = null;
        _error = null;
        _revealed = null;
      });

  /// Read the device wrapping secret, generating + persisting one on first use.
  Future<String> _getOrCreateWrapSecret() async {
    final existing = await _storage.read(key: _kWrap);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _kWrap, value: hex);
    return hex;
  }

  String _compose(String password, String wrapSecretHex) =>
      '$password$_sep$wrapSecretHex';

  Future<void> _encryptAndStore() async {
    _clear();
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Enter a password.');
      return;
    }
    setState(() => _busy = true);
    try {
      final wrap = await _getOrCreateWrapSecret();
      final composed = _compose(_passwordCtrl.text, wrap);

      // Tunable cost — measure on-device once and tune to taste.
      final p = defaultKdfParams();
      final ms = benchmarkKdf(
        memKib: p.memKib,
        iterations: p.iterations,
        parallelism: p.parallelism,
      );

      final enc = encryptSeed(secret: _mnemonicCtrl.text, password: composed);
      await _storage.write(key: _kBlob, value: enc.blobHex);

      if (!mounted) return;
      setState(() {
        _status = 'Encrypted & stored in ${_platformStoreName()}.\n'
            'KDF: ${p.memKib ~/ 1024} MiB / t=${p.iterations} (~$ms ms)\n'
            'Blob: ${_short(enc.blobHex)} (${enc.blobHex.length ~/ 2} bytes)';
        _revealed = null;
      });
      await _refreshVaultState();
    } catch (e) {
      if (mounted) setState(() => _error = 'Encrypt failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    _clear();
    setState(() => _busy = true);
    try {
      final blob = await _storage.read(key: _kBlob);
      final wrap = await _storage.read(key: _kWrap);
      if (blob == null || wrap == null) {
        setState(() => _error = 'No vault stored yet.');
        return;
      }
      final composed = _compose(_passwordCtrl.text, wrap);
      // Wrong password OR a tampered blob both throw here (fails closed).
      final secret = decryptSeed(blobHex: blob, password: composed);
      if (!mounted) return;
      setState(() {
        _status = 'Unlocked ✓';
        _revealed = secret;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unlock failed — wrong password or tampered data.';
          _revealed = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wipe() async {
    _clear();
    setState(() => _busy = true);
    try {
      await _storage.delete(key: _kBlob);
      await _storage.delete(key: _kWrap);
      if (mounted) setState(() => _status = 'Vault wiped (blob + wrapping key).');
      await _refreshVaultState();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _platformStoreName() {
    final t = Theme.of(context).platform;
    if (t == TargetPlatform.iOS || t == TargetPlatform.macOS) return 'Keychain';
    if (t == TargetPlatform.android) return 'Keystore';
    return 'secure storage';
  }

  String _short(String s) =>
      s.length <= 24 ? s : '${s.substring(0, 12)}…${s.substring(s.length - 8)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seed Vault (Phase 5b)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.indigo.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Argon2id + XChaCha20-Poly1305 (Rust). The wrapping secret '
                  'lives in the OS Keychain/Keystore and is combined with your '
                  'password, so a stolen blob is useless without the device.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mnemonicCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Recovery phrase (secret)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_hasVault ? Icons.lock : Icons.lock_open,
                    size: 16, color: Colors.indigo),
                const SizedBox(width: 6),
                Text(_hasVault ? 'Vault present' : 'No vault stored',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _busy ? null : _encryptAndStore,
                  icon: const Icon(Icons.enhanced_encryption),
                  label: const Text('Encrypt & store'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy || !_hasVault ? null : _unlock,
                  icon: const Icon(Icons.key),
                  label: const Text('Unlock'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !_hasVault ? null : _wipe,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Wipe'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status!,
                    style: const TextStyle(color: Colors.green, fontSize: 13)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            if (_revealed != null)
              Card(
                margin: const EdgeInsets.only(top: 12),
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Decrypted secret:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      SelectableText(_revealed!,
                          style: const TextStyle(fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
