import 'dart:typed_data';

/// Decodes an even-length hexadecimal string into bytes.
///
/// Invalid input is rejected instead of being truncated or deferred to a
/// backend-specific parser. An empty string is valid hexadecimal and decodes
/// to an empty byte array.
Uint8List decodeHex(String value, {String label = 'hex'}) {
  if (value.length.isOdd) {
    throw FormatException('$label must have an even number of characters');
  }

  final bytes = Uint8List(value.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final position = i * 2;
    final high = _hexNibble(value.codeUnitAt(position));
    final low = _hexNibble(value.codeUnitAt(position + 1));
    if (high < 0 || low < 0) {
      final invalidPosition = high < 0 ? position : position + 1;
      throw FormatException(
        '$label contains a non-hex character at position $invalidPosition',
      );
    }
    bytes[i] = high * 16 + low;
  }
  return bytes;
}

int _hexNibble(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
  if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x41 + 10;
  if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x61 + 10;
  return -1;
}
