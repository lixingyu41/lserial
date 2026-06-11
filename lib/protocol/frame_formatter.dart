import 'dart:convert';

import '../core/encoding/data_format.dart';
import '../core/encoding/hex_codec.dart';
import '../domain/data_frame.dart';

class ConsoleFormatOptions {
  const ConsoleFormatOptions({
    required this.viewMode,
    required this.showTimestamp,
    required this.showDirection,
    this.showSource = false,
    this.showContent = true,
    this.showLineEndingSymbols = true,
  });

  final ConsoleViewMode viewMode;
  final bool showTimestamp;
  final bool showDirection;
  final bool showSource;
  final bool showContent;
  final bool showLineEndingSymbols;

  ConsoleFormatOptions copyWith({
    ConsoleViewMode? viewMode,
    bool? showTimestamp,
    bool? showDirection,
    bool? showSource,
    bool? showContent,
    bool? showLineEndingSymbols,
  }) {
    return ConsoleFormatOptions(
      viewMode: viewMode ?? this.viewMode,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showDirection: showDirection ?? this.showDirection,
      showSource: showSource ?? this.showSource,
      showContent: showContent ?? this.showContent,
      showLineEndingSymbols:
          showLineEndingSymbols ?? this.showLineEndingSymbols,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConsoleFormatOptions &&
        other.viewMode == viewMode &&
        other.showTimestamp == showTimestamp &&
        other.showDirection == showDirection &&
        other.showSource == showSource &&
        other.showContent == showContent &&
        other.showLineEndingSymbols == showLineEndingSymbols;
  }

  @override
  int get hashCode => Object.hash(
        viewMode,
        showTimestamp,
        showDirection,
        showSource,
        showContent,
        showLineEndingSymbols,
      );
}

class FrameFormatter {
  const FrameFormatter();

  String formatFrame(DataFrame frame, ConsoleFormatOptions options) {
    final prefix = <String>[];
    if (options.showTimestamp) {
      prefix.add(formatTimestamp(frame.timestamp));
    }
    if (options.showSource && frame.direction != FrameDirection.system) {
      prefix.add(sourceToken(frame));
    }
    if (options.showDirection) {
      prefix.add('${directionToken(frame)}:');
    } else if (options.showSource && frame.direction == FrameDirection.system) {
      prefix.add('${sourceToken(frame)}:');
    }
    final payload = options.showContent ? formatPayload(frame, options) : '';
    if (prefix.isEmpty) {
      return payload;
    }
    if (payload.isEmpty) {
      return prefix.join(' ');
    }
    return '${prefix.join(' ')} $payload';
  }

  String sourceToken(DataFrame frame) {
    if (frame.direction == FrameDirection.system) {
      return 'SYS';
    }
    final source = frame.source.trim();
    return source.isEmpty ? frame.direction.label : source;
  }

  String directionToken(DataFrame frame) {
    return switch (frame.direction) {
      FrameDirection.rx => 'R',
      FrameDirection.tx => 'T',
      FrameDirection.system => 'SYS',
    };
  }

  String formatPayload(DataFrame frame, ConsoleFormatOptions options) {
    if (frame.direction == FrameDirection.system) {
      return _ascii(frame,
          showLineEndingSymbols: options.showLineEndingSymbols);
    }
    return switch (options.viewMode) {
      ConsoleViewMode.ascii =>
        _ascii(frame, showLineEndingSymbols: options.showLineEndingSymbols),
      ConsoleViewMode.hex => HexCodec.encode(frame.bytes),
    };
  }

  String _ascii(
    DataFrame frame, {
    required bool showLineEndingSymbols,
  }) {
    final text = utf8.decode(frame.bytes, allowMalformed: true);
    if (showLineEndingSymbols) {
      return text.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
    }
    return text.replaceAll('\r', '').replaceAll('\n', '');
  }

  String formatTimestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.${three(value.millisecond)}';
  }
}
