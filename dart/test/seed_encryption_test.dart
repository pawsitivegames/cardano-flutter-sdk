import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';

  setUpAll(() async {
    await RustLib.init();
  });

  // Fast Argon2id params keep the suite quick; production uses defaultKdfParams().
  const fastMem = 8 * 1024; // 8 MiB
  const fastIters = 1;
  const fastPar = 1;

  EncryptedSeed encFast(String secret, String password) => encryptSeedWithParams(
        secret: secret,
        password: password,
        memKib: fastMem,
        iterations: fastIters,
        parallelism: fastPar,
      );

  group('encrypt/decrypt round-trip', () {
    test('recovers the exact mnemonic', () {
      final e = encFast(mnemonic, 'correct horse battery staple');
      final out = decryptSeed(
        blobHex: e.blobHex,
        password: 'correct horse battery staple',
      );
      expect(out, mnemonic);
    });

    test('blob is a CFS1 hex container echoing the KDF params', () {
      final e = encFast(mnemonic, 'pw');
      // "CFS1" magic = 0x43 0x46 0x53 0x31
      expect(e.blobHex.startsWith('43465331'), isTrue);
      expect(e.kdf.memKib, fastMem);
      expect(e.kdf.iterations, fastIters);
      expect(e.kdf.parallelism, fastPar);
    });

    test('empty secret round-trips', () {
      final e = encFast('', 'pw');
      expect(decryptSeed(blobHex: e.blobHex, password: 'pw'), '');
    });

    test('unicode secret round-trips', () {
      const secret = 'café ☕ 助记词 🔑';
      final e = encFast(secret, 'pw');
      expect(decryptSeed(blobHex: e.blobHex, password: 'pw'), secret);
    });
  });

  group('failure modes', () {
    test('wrong password throws', () {
      final e = encFast(mnemonic, 'right');
      expect(
        () => decryptSeed(blobHex: e.blobHex, password: 'wrong'),
        throwsA(anything),
      );
    });

    test('tampered ciphertext throws', () {
      final e = encFast(mnemonic, 'pw');
      // Flip the last hex nibble (a ciphertext/tag byte).
      final chars = e.blobHex.split('');
      final last = chars.length - 1;
      chars[last] = chars[last] == '0' ? '1' : '0';
      final tampered = chars.join();
      expect(
        () => decryptSeed(blobHex: tampered, password: 'pw'),
        throwsA(anything),
      );
    });

    test('non-hex blob throws', () {
      expect(
        () => decryptSeed(blobHex: 'zzzz', password: 'pw'),
        throwsA(anything),
      );
    });

    test('bad magic throws', () {
      // Valid hex but wrong magic.
      expect(
        () => decryptSeed(blobHex: '00112233445566', password: 'pw'),
        throwsA(anything),
      );
    });

    test('invalid KDF params (parallelism 0) throws', () {
      expect(
        () => encryptSeedWithParams(
          secret: mnemonic,
          password: 'pw',
          memKib: fastMem,
          iterations: fastIters,
          parallelism: 0,
        ),
        throwsA(anything),
      );
    });
  });

  group('randomness', () {
    test('two encryptions of the same input differ but both decrypt', () {
      final a = encFast(mnemonic, 'pw');
      final b = encFast(mnemonic, 'pw');
      expect(a.blobHex, isNot(b.blobHex), reason: 'salt+nonce must be random');
      expect(decryptSeed(blobHex: a.blobHex, password: 'pw'), mnemonic);
      expect(decryptSeed(blobHex: b.blobHex, password: 'pw'), mnemonic);
    });
  });

  group('KDF params & benchmark', () {
    test('defaultKdfParams are the documented mobile defaults', () {
      final p = defaultKdfParams();
      expect(p.memKib, 64 * 1024); // 64 MiB
      expect(p.iterations, 3);
      expect(p.parallelism, 1);
    });

    test('benchmarkKdf returns a non-negative duration', () {
      final ms = benchmarkKdf(
        memKib: fastMem,
        iterations: fastIters,
        parallelism: fastPar,
      );
      expect(ms, isA<BigInt>());
      expect(ms >= BigInt.zero, isTrue);
    });
  });
}
