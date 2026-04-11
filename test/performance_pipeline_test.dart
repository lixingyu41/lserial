import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/receive_pipeline.dart';
import 'package:lserial/core/buffer/byte_ring_buffer.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/storage/log_buffer.dart';

void main() {
  test('ByteRingBuffer keeps recent bytes and tracks dropped bytes', () {
    final buffer = ByteRingBuffer(4);

    buffer.write(<int>[1, 2, 3]);
    buffer.write(<int>[4, 5, 6]);

    expect(buffer.snapshot(), Uint8List.fromList(<int>[3, 4, 5, 6]));
    expect(buffer.droppedBytes, 2);
  });

  test('LogBuffer trims display frames without blocking new frames', () {
    final buffer = LogBuffer(maxFrames: 3, maxBytes: 1024);

    buffer.addAll(
      List<DataFrame>.generate(
        5,
        (index) => DataFrame(
          sequence: index + 1,
          timestamp: DateTime(2026),
          direction: FrameDirection.rx,
          bytes: <int>[index],
          source: 'test',
        ),
      ),
    );

    final snapshot = buffer.snapshot(paused: false);
    expect(snapshot.frames.map((frame) => frame.sequence), <int>[3, 4, 5]);
    expect(snapshot.droppedFrames, 2);
  });

  test('ReceivePipeline batches high-frequency chunks before UI commit',
      () async {
    final raw = ByteRingBuffer(1024);
    final batches = <List<DataFrame>>[];
    var sequence = 0;
    final pipeline = ReceivePipeline(
      rawBuffer: raw,
      flushInterval: const Duration(milliseconds: 20),
      nextSequence: () => ++sequence,
      onBatch: batches.add,
    );

    for (var i = 0; i < 10; i++) {
      pipeline.addBytes(<int>[i], source: 'rx');
    }

    expect(batches, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(batches, hasLength(1));
    expect(batches.single, hasLength(10));
    expect(raw.length, 10);

    pipeline.dispose();
  });
}
