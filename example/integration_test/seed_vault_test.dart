import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Phase 5b on-device verification: seed-at-rest encryption + real Keychain.
///
/// Runs INSIDE the built app (driven by `flutter test … -d <device>`), so it
/// proves what the host unit-test suite cannot:
///   1. The Rust `seed` FFI symbols (Argon2id + XChaCha20-Poly1305, `benchmark_kdf`)
///      are present in the on-device framework and execute on real hardware.
///   2. The recommended composition round-trips through the *actual* platform
///      secure store (iOS Keychain / Android Keystore) via `flutter_secure_storage`,
///      not an in-memory fake — encrypt → store blob + wrap secret → read back →
///      decrypt → original secret.
///   3. `benchmark_kdf` yields a real on-device unlock-latency figure to record
///      in `docs/seed-encryption.md`.
///
/// Deterministic, no network. Run:
///   cd example && flutter test integration_test/seed_vault_test.dart -d DEVICE_ID
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';
  // Same scheme as SeedVaultScreen: a device-bound wrap secret composed with
  // the user password via the ASCII unit separator (0x1f).
  const sep = '';
  const userPassword = 'correct horse battery staple';

  // Dedicated keys so the test never clobbers a real vault entry.
  const kBlob = 'cfs_vault_blob_itest';
  const kWrap = 'cfs_vault_wrap_secret_itest';

  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions:
        IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  setUpAll(() async {
    await RustLib.init();
  });

  tearDown(() async {
    await storage.delete(key: kBlob);
    await storage.delete(key: kWrap);
  });

  testWidgets('benchmark_kdf reports real on-device cost', (tester) async {
    final p = defaultKdfParams();
    final defaultMs = benchmarkKdf(
      memKib: p.memKib,
      iterations: p.iterations,
      parallelism: p.parallelism,
    );
    final floorMs = benchmarkKdf(memKib: 19 * 1024, iterations: 2, parallelism: 1);

    final line =
        'SEED_BENCH default ${p.memKib ~/ 1024}MiB/t=${p.iterations}/p=${p.parallelism}: '
        '${defaultMs}ms | OWASP-floor 19MiB/t=2/p=1: ${floorMs}ms';
    // ignore: avoid_print
    print(line);
    // Surface to the flutter-drive driver (device stdout isn't reliably captured).
    binding.reportData = <String, dynamic>{
      'seed_bench': line,
      'default_ms': defaultMs.toString(),
      'floor_ms': floorMs.toString(),
      'mem_mib': p.memKib ~/ 1024,
      'iterations': p.iterations,
      'parallelism': p.parallelism,
    };

    // Sanity: the KDF actually did work (non-trivial wall-clock) and the
    // memory-harder default costs at least as much as the floor.
    expect(defaultMs, greaterThan(BigInt.zero));
    expect(defaultMs, greaterThanOrEqualTo(floorMs));
  });

  testWidgets('full encrypt → Keychain → decrypt round-trip on device',
      (tester) async {
    // 1. Device-bound wrapping secret, persisted in the real secure store.
    final wrap = _randHex(32);
    await storage.write(key: kWrap, value: wrap);
    final composed = '$userPassword$sep$wrap';

    // 2. Encrypt the secret in Rust and persist the CFS1 blob.
    final enc = encryptSeed(secret: mnemonic, password: composed);
    expect(enc.blobHex, startsWith('43465331')); // "CFS1" magic, hex
    await storage.write(key: kBlob, value: enc.blobHex);

    // 3. Read BOTH back from the platform store (proves real persistence).
    final blobBack = await storage.read(key: kBlob);
    final wrapBack = await storage.read(key: kWrap);
    expect(blobBack, isNotNull);
    expect(wrapBack, equals(wrap));

    // 4. Recompose and decrypt — must recover the original secret exactly.
    final recovered =
        decryptSeed(blobHex: blobBack!, password: '$userPassword$sep$wrapBack');
    expect(recovered, equals(mnemonic));
  });

  testWidgets('wrong password fails closed', (tester) async {
    final wrap = _randHex(32);
    final enc = encryptSeed(secret: mnemonic, password: '$userPassword$sep$wrap');
    expect(
      () => decryptSeed(blobHex: enc.blobHex, password: 'wrong$sep$wrap'),
      throwsA(anything),
    );
  });

  testWidgets('missing device wrap secret cannot decrypt (blob alone is useless)',
      (tester) async {
    final wrap = _randHex(32);
    final enc = encryptSeed(secret: mnemonic, password: '$userPassword$sep$wrap');
    // Attacker has the exfiltrated blob + user password but NOT the Keychain
    // wrap secret → composition differs → AEAD auth fails.
    expect(
      () => decryptSeed(blobHex: enc.blobHex, password: userPassword),
      throwsA(anything),
    );
  });

  testWidgets('tampered ciphertext fails closed', (tester) async {
    final wrap = _randHex(32);
    final enc = encryptSeed(secret: mnemonic, password: '$userPassword$sep$wrap');
    // Flip the last ciphertext byte (hex nibble) — AEAD must reject.
    final chars = enc.blobHex.split('');
    chars[chars.length - 1] = chars.last == '0' ? '1' : '0';
    final tampered = chars.join();
    expect(
      () => decryptSeed(blobHex: tampered, password: '$userPassword$sep$wrap'),
      throwsA(anything),
    );
  });

  testWidgets('each encryption uses fresh salt/nonce (distinct blobs)',
      (tester) async {
    const pw = 'pw$sep' 'abcd';
    final a = encryptSeed(secret: mnemonic, password: pw);
    final b = encryptSeed(secret: mnemonic, password: pw);
    expect(a.blobHex, isNot(equals(b.blobHex)));
    // Both still decrypt to the same secret.
    expect(decryptSeed(blobHex: a.blobHex, password: pw), equals(mnemonic));
    expect(decryptSeed(blobHex: b.blobHex, password: pw), equals(mnemonic));
  });
}

/// Deterministic-enough random hex for a test wrap secret (not a security
/// boundary here; the Rust CSPRNG protects the actual crypto material).
String _randHex(int bytes) {
  final sb = StringBuffer();
  var x = 0x2545F4914F6CDD1D ^ bytes; // splitmix-ish, host-independent
  for (var i = 0; i < bytes; i++) {
    x = (x * 0x9E3779B97F4A7C15 + 0x1) & 0x7FFFFFFFFFFFFFFF;
    sb.write(((x >> 24) & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
