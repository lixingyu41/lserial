import '../core/encoding/data_format.dart';

enum QuickCommandImportMode {
  replace,
  append,
}

class QuickCommand {
  const QuickCommand({
    required this.id,
    required this.name,
    required this.content,
    required this.format,
  });

  final int id;
  final String name;
  final String content;
  final PayloadFormat format;

  QuickCommand copyWith({
    int? id,
    String? name,
    String? content,
    PayloadFormat? format,
  }) {
    return QuickCommand(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      format: format ?? this.format,
    );
  }
}
