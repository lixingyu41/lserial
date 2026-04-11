import 'dart:async';
import 'dart:typed_data';

import '../core/buffer/byte_ring_buffer.dart';
import '../domain/data_frame.dart';

class ReceivePipeline {
  ReceivePipeline({
    required this.rawBuffer,
    required this.onBatch,
    required this.nextSequence,
    this.flushInterval = const Duration(milliseconds: 33),
    this.maxBatchFrames = 256,
  });

  final ByteRingBuffer rawBuffer;
  final void Function(List<DataFrame> frames) onBatch;
  final int Function() nextSequence;
  final Duration flushInterval;
  final int maxBatchFrames;

  final List<DataFrame> _pending = <DataFrame>[];
  Timer? _timer;
  bool _disposed = false;

  /// Hot path: copy incoming bytes once, retain raw bytes, and defer UI work.
  void addBytes(List<int> bytes, {required String source}) {
    if (_disposed || bytes.isEmpty) {
      return;
    }

    final copy = Uint8List.fromList(bytes);
    rawBuffer.write(copy);
    _pending.add(
      DataFrame(
        sequence: nextSequence(),
        timestamp: DateTime.now(),
        direction: FrameDirection.rx,
        bytes: copy,
        source: source,
      ),
    );

    if (_pending.length >= maxBatchFrames) {
      flush();
    } else {
      _timer ??= Timer(flushInterval, flush);
    }
  }

  void addFrame(DataFrame frame) {
    if (_disposed) {
      return;
    }
    _pending.add(frame);
    if (_pending.length >= maxBatchFrames) {
      flush();
    } else {
      _timer ??= Timer(flushInterval, flush);
    }
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) {
      return;
    }
    final batch = List<DataFrame>.unmodifiable(_pending);
    _pending.clear();
    onBatch(batch);
  }

  void clearRaw() {
    rawBuffer.clear();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
