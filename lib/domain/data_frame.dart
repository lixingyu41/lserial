import 'dart:convert';
import 'dart:typed_data';

enum FrameDirection {
  rx,
  tx,
  system,
}

extension FrameDirectionLabel on FrameDirection {
  String get label => switch (this) {
        FrameDirection.rx => 'RX',
        FrameDirection.tx => 'TX',
        FrameDirection.system => 'SYS',
      };
}

class DataFrame {
  DataFrame({
    required this.sequence,
    required this.timestamp,
    required this.direction,
    required List<int> bytes,
    required this.source,
  }) : bytes = Uint8List.fromList(bytes);

  factory DataFrame.text({
    required int sequence,
    required FrameDirection direction,
    required String text,
    required String source,
  }) {
    return DataFrame(
      sequence: sequence,
      timestamp: DateTime.now(),
      direction: direction,
      bytes: utf8.encode(text),
      source: source,
    );
  }

  final int sequence;
  final DateTime timestamp;
  final FrameDirection direction;
  final Uint8List bytes;
  final String source;

  int get byteLength => bytes.length;
}
