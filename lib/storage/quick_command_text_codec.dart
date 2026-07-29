import '../core/encoding/data_format.dart';
import '../domain/quick_command.dart';

const String _header = '''
# LSerial Quick Commands v1
# One command per line: FORMAT<TAB>NAME<TAB>CONTENT
# FORMAT: ASCII or HEX
# Escapes in NAME and CONTENT: \\n \\r \\t \\\\
''';

String encodeQuickCommandsText(Iterable<QuickCommand> commands) {
  final buffer = StringBuffer(_header);
  for (final command in commands) {
    buffer
      ..write(command.format.label)
      ..write('\t')
      ..write(_escape(command.name))
      ..write('\t')
      ..writeln(_escape(command.content));
  }
  return buffer.toString();
}

List<QuickCommand> decodeQuickCommandsText(String text) {
  final normalized = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final lines =
      normalized.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final commands = <QuickCommand>[];

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) {
      continue;
    }

    final firstTab = line.indexOf('\t');
    final secondTab = firstTab < 0 ? -1 : line.indexOf('\t', firstTab + 1);
    if (firstTab <= 0 || secondTab < 0) {
      throw FormatException(
        'Line ${index + 1}: expected FORMAT<TAB>NAME<TAB>CONTENT.',
      );
    }

    final format = _parseFormat(line.substring(0, firstTab), index + 1);
    final name = _unescape(line.substring(firstTab + 1, secondTab)).trim();
    final content = _unescape(line.substring(secondTab + 1));
    if (name.isEmpty || content.isEmpty) {
      throw FormatException(
        'Line ${index + 1}: NAME and CONTENT cannot be empty.',
      );
    }

    commands.add(
      QuickCommand(
        id: commands.length + 1,
        name: name,
        content: content,
        format: format,
      ),
    );
  }

  return commands;
}

PayloadFormat _parseFormat(String value, int lineNumber) {
  return switch (value.trim().toUpperCase()) {
    'ASCII' => PayloadFormat.ascii,
    'HEX' => PayloadFormat.hex,
    _ => throw FormatException(
        'Line $lineNumber: FORMAT must be ASCII or HEX.',
      ),
  };
}

String _escape(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
}

String _unescape(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final char = value[index];
    if (char != r'\' || index + 1 >= value.length) {
      buffer.write(char);
      continue;
    }

    final escaped = value[++index];
    switch (escaped) {
      case 'n':
        buffer.write('\n');
      case 'r':
        buffer.write('\r');
      case 't':
        buffer.write('\t');
      case r'\':
        buffer.write(r'\');
      default:
        buffer
          ..write(r'\')
          ..write(escaped);
    }
  }
  return buffer.toString();
}
