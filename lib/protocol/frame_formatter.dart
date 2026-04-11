import 'dart:convert';

import '../core/encoding/data_format.dart';
import '../core/encoding/hex_codec.dart';
import '../domain/data_frame.dart';

class ConsoleFormatOptions {
  const ConsoleFormatOptions({
    required this.viewMode,
    required this.showTimestamp,
    required this.showDirection,
  });

  final ConsoleViewMode viewMode;
  final bool showTimestamp;
  final bool showDirection;

  ConsoleFormatOptions copyWith({
    ConsoleViewMode? viewMode,
    bool? showTimestamp,
    bool? showDirection,
  }) {
    return ConsoleFormatOptions(
      viewMode: viewMode ?? this.viewMode,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showDirection: showDirection ?? this.showDirection,
    );
  }
}

class FrameFormatter {
  const FrameFormatter();

  String formatFrame(DataFrame frame, ConsoleFormatOptions options) {
    final prefix = <String>[];
    if (options.showTimestamp) {
      prefix.add(_formatTime(frame.timestamp));
    }
    if (options.showDirection) {
      prefix.add(frame.direction.label);
    }
    if (frame.source.isNotEmpty) {
      prefix.add(frame.source);
    }

    final payload = switch (options.viewMode) {
      ConsoleViewMode.ascii => _ascii(frame),
      ConsoleViewMode.hex => HexCodec.encode(frame.bytes),
    };
    return prefix.isEmpty ? payload : '${prefix.join(' ')} | $payload';
  }

  String _ascii(DataFrame frame) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    return text.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
  }

  String _formatTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.${three(value.millisecond)}';
  }
}
