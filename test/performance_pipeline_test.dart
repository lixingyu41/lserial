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

  test('ReceivePipeline groups chunks by packet interval', () async {
    final raw = ByteRingBuffer(1024);
    final batches = <List<DataFrame>>[];
    var sequence = 0;
    final pipeline = ReceivePipeline(
      rawBuffer: raw,
      packetInterval: const Duration(milliseconds: 20),
      flushInterval: const Duration(seconds: 1),
      nextSequence: () => ++sequence,
      onBatch: batches.add,
    );

    pipeline.addBytes(<int>[0x41], source: 'rx');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    pipeline.addBytes(<int>[0x42], source: 'rx');

    expect(batches, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(batches, hasLength(1));
    expect(batches.single, hasLength(1));
    expect(batches.single.single.bytes, Uint8List.fromList(<int>[0x41, 0x42]));
    expect(raw.length, 2);

    pipeline.dispose();
  });

  test('ReceivePipeline waits for idle gap before flushing packet', () async {
    final raw = ByteRingBuffer(1024);
    final batches = <List<DataFrame>>[];
    var sequence = 0;
    final pipeline = ReceivePipeline(
      rawBuffer: raw,
      packetInterval: const Duration(milliseconds: 20),
      flushInterval: const Duration(seconds: 1),
      nextSequence: () => ++sequence,
      onBatch: batches.add,
    );

    pipeline.addBytes(<int>[0], source: 'rx');
    for (var i = 1; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
      pipeline.addBytes(<int>[i], source: 'rx');
    }

    expect(batches, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(batches, hasLength(1));
    expect(batches.single.single.bytes,
        Uint8List.fromList(List<int>.generate(8, (index) => index)));
    expect(raw.length, 8);

    pipeline.dispose();
  });

  test('ReceivePipeline splits packets by delimiter', () async {
    final raw = ByteRingBuffer(1024);
    final batches = <List<DataFrame>>[];
    var sequence = 0;
    final pipeline = ReceivePipeline(
      rawBuffer: raw,
      packetDelimiter: const <int>[0x0d, 0x0a],
      flushInterval: const Duration(seconds: 1),
      nextSequence: () => ++sequence,
      onBatch: batches.add,
    );

    pipeline.addBytes(<int>[0x41, 0x0d], source: 'rx');
    expect(batches, isEmpty);

    pipeline.addBytes(<int>[0x0a, 0x42, 0x0d, 0x0a], source: 'rx');

    expect(batches, hasLength(1));
    expect(batches.single, hasLength(2));
    expect(
      batches.single.map((frame) => frame.bytes).toList(),
      <Uint8List>[
        Uint8List.fromList(<int>[0x41, 0x0d, 0x0a]),
        Uint8List.fromList(<int>[0x42, 0x0d, 0x0a]),
      ],
    );
    expect(raw.length, 6);

    pipeline.dispose();
  });
}
