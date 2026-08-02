import 'package:cardano_flutter_rs/src/hex.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodeHex accepts upper- and lower-case bytes', () {
    expect(decodeHex('84aB01ff'), equals([0x84, 0xab, 0x01, 0xff]));
  });

  test('decodeHex accepts an empty string', () {
    expect(decodeHex(''), isEmpty);
  });

  test('decodeHex rejects odd-length input', () {
    expect(
      () => decodeHex('abc', label: 'transaction CBOR'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('transaction CBOR must have an even number'),
        ),
      ),
    );
  });

  test('decodeHex rejects non-hex input and reports its position', () {
    expect(
      () => decodeHex('84010g', label: 'transaction CBOR'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('position 5'),
        ),
      ),
    );
  });
}
