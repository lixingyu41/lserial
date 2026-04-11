import 'dart:typed_data';

class HexCodec {
  const HexCodec._();

  static Uint8List decode(String input) {
    final clean = input.replaceAll(RegExp(r'[\s,;:_-]+'), '');
    if (clean.isEmpty) {
      return Uint8List(0);
    }
    if (clean.length.isOdd) {
      throw const FormatException(
        'HEX input must contain an even number of digits.',
      );
    }

    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      final byteText = clean.substring(i, i + 2);
      final value = int.tryParse(byteText, radix: 16);
      if (value == null) {
        throw FormatException('Invalid HEX byte: $byteText');
      }
      out[i ~/ 2] = value;
    }
    return out;
  }

  static String encode(Iterable<int> bytes) {
    return bytes
        .map(
          (byte) => byte
              .toUnsigned(8)
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase(),
        )
        .join(' ');
  }
}
