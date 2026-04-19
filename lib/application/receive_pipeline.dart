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
    Duration packetInterval = Duration.zero,
    List<int> packetDelimiter = const <int>[],
    this.maxPacketBytes = 64 * 1024,
  })  : _packetInterval = _normalizeDuration(packetInterval),
        _packetDelimiter = Uint8List.fromList(packetDelimiter);

  final ByteRingBuffer rawBuffer;
  final void Function(List<DataFrame> frames) onBatch;
  final int Function() nextSequence;
  final Duration flushInterval;
  final int maxBatchFrames;
  final int maxPacketBytes;

  final List<DataFrame> _pending = <DataFrame>[];
  final List<int> _packetBytes = <int>[];
  Timer? _timer;
  Timer? _packetTimer;
  DateTime? _packetTimestamp;
  String? _packetSource;
  Duration _packetInterval;
  Uint8List _packetDelimiter;
  bool _disposed = false;

  Duration get packetInterval => _packetInterval;

  set packetInterval(Duration value) {
    final normalized = _normalizeDuration(value);
    if (normalized == _packetInterval) {
      return;
    }
    flush();
    _packetInterval = normalized;
  }

  List<int> get packetDelimiter => List<int>.unmodifiable(_packetDelimiter);

  set packetDelimiter(List<int> value) {
    final copy = Uint8List.fromList(value);
    if (_listEquals(copy, _packetDelimiter)) {
      return;
    }
    flush();
    _packetDelimiter = copy;
  }

  void configurePacket({
    required Duration packetInterval,
    required List<int> packetDelimiter,
  }) {
    final normalized = _normalizeDuration(packetInterval);
    final delimiter = Uint8List.fromList(packetDelimiter);
    if (normalized == _packetInterval &&
        _listEquals(delimiter, _packetDelimiter)) {
      return;
    }
    flush();
    _packetInterval = normalized;
    _packetDelimiter = delimiter;
  }

  /// Hot path: copy incoming bytes once, retain raw bytes, and defer UI work.
  void addBytes(List<int> bytes, {required String source}) {
    if (_disposed || bytes.isEmpty) {
      return;
    }

    final copy = Uint8List.fromList(bytes);
    rawBuffer.write(copy);
    final now = DateTime.now();
    if (!_usesPacketBuffer) {
      _addPending(
        DataFrame(
          sequence: nextSequence(),
          timestamp: now,
          direction: FrameDirection.rx,
          bytes: copy,
          source: source,
        ),
      );
      return;
    }

    if (_packetBytes.isNotEmpty && _packetSource != source) {
      _flushPacket();
    }
    _packetTimestamp ??= now;
    _packetSource ??= source;
    _packetBytes.addAll(copy);
    final flushedDelimiterPackets = _flushDelimitedPackets();

    if (_packetBytes.length >= maxPacketBytes) {
      _flushPacket();
      _flushPending();
      return;
    }

    _startPacketTimer();
    if (flushedDelimiterPackets) {
      _flushPending();
    }
  }

  bool get _usesPacketBuffer =>
      _packetInterval != Duration.zero || _packetDelimiter.isNotEmpty;

  bool _flushDelimitedPackets() {
    if (_packetDelimiter.isEmpty || _packetBytes.isEmpty) {
      return false;
    }

    var flushed = false;
    while (true) {
      final delimiterIndex = _indexOfBytes(_packetBytes, _packetDelimiter);
      if (delimiterIndex < 0) {
        break;
      }

      final packetEnd = delimiterIndex + _packetDelimiter.length;
      final bytes = Uint8List.fromList(_packetBytes.sublist(0, packetEnd));
      _packetBytes.removeRange(0, packetEnd);
      _addPending(
        DataFrame(
          sequence: nextSequence(),
          timestamp: _packetTimestamp ?? DateTime.now(),
          direction: FrameDirection.rx,
          bytes: bytes,
          source: _packetSource ?? '',
        ),
      );
      _packetTimestamp = _packetBytes.isEmpty ? null : DateTime.now();
      flushed = true;
    }

    if (flushed) {
      _packetTimer?.cancel();
      _packetTimer = null;
      if (_packetBytes.isEmpty) {
        _packetTimestamp = null;
        _packetSource = null;
      }
    }
    return flushed;
  }

  int _indexOfBytes(List<int> haystack, List<int> needle) {
    if (needle.isEmpty || haystack.length < needle.length) {
      return -1;
    }
    final lastStart = haystack.length - needle.length;
    for (var start = 0; start <= lastStart; start++) {
      var matched = true;
      for (var offset = 0; offset < needle.length; offset++) {
        if (haystack[start + offset] != needle[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return start;
      }
    }
    return -1;
  }

  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  void _startPacketTimer() {
    if (_packetInterval == Duration.zero || _packetBytes.isEmpty) {
      return;
    }
    _packetTimer?.cancel();
    _packetTimer = Timer(_packetInterval, () {
      _flushPacket();
      _flushPending();
    });
  }

  void addFrame(DataFrame frame) {
    if (_disposed) {
      return;
    }
    _flushPacket();
    _addPending(frame);
  }

  void _addPending(DataFrame frame) {
    _pending.add(frame);
    if (_pending.length >= maxBatchFrames) {
      _flushPending();
    } else {
      _timer ??= Timer(flushInterval, _flushPending);
    }
  }

  void flush() {
    _flushPacket();
    _flushPending();
  }

  void _flushPacket() {
    _packetTimer?.cancel();
    _packetTimer = null;
    if (_packetBytes.isEmpty) {
      return;
    }
    final bytes = Uint8List.fromList(_packetBytes);
    final timestamp = _packetTimestamp ?? DateTime.now();
    final source = _packetSource ?? '';
    _packetBytes.clear();
    _packetTimestamp = null;
    _packetSource = null;
    _addPending(
      DataFrame(
        sequence: nextSequence(),
        timestamp: timestamp,
        direction: FrameDirection.rx,
        bytes: bytes,
        source: source,
      ),
    );
  }

  void _flushPending() {
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
    _packetTimer?.cancel();
    _packetTimer = null;
    _pending.clear();
    _packetBytes.clear();
  }

  static Duration _normalizeDuration(Duration value) {
    return value.isNegative ? Duration.zero : value;
  }
}
