import 'dart:convert';
import 'dart:typed_data';

import '../core/encoding/data_format.dart';
import '../core/encoding/hex_codec.dart';

class SendRequest {
  SendRequest({
    required this.text,
    required this.format,
    required this.lineEnding,
  }) : bytes = _encode(text, format, lineEnding);

  final String text;
  final PayloadFormat format;
  final LineEnding lineEnding;
  final Uint8List bytes;

  static Uint8List _encode(
    String text,
    PayloadFormat format,
    LineEnding lineEnding,
  ) {
    final payload = switch (format) {
      PayloadFormat.ascii => Uint8List.fromList(utf8.encode(text)),
      PayloadFormat.hex => HexCodec.decode(text),
    };
    if (lineEnding.bytes.isEmpty) {
      return payload;
    }
    return Uint8List.fromList(<int>[...payload, ...lineEnding.bytes]);
  }
}
