import '../core/encoding/data_format.dart';

class SendHistoryEntry {
  const SendHistoryEntry({
    required this.text,
    required this.format,
    required this.timestamp,
  });

  final String text;
  final PayloadFormat format;
  final DateTime timestamp;
}
