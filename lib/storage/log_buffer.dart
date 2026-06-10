import 'dart:collection';

import '../domain/data_frame.dart';
import '../protocol/frame_formatter.dart';

class LogSnapshot {
  const LogSnapshot({
    required this.revision,
    required this.frames,
    required this.totalFrames,
    required this.totalBytes,
    required this.droppedFrames,
    required this.droppedBytes,
    required this.paused,
  });

  factory LogSnapshot.empty() {
    return const LogSnapshot(
      revision: 0,
      frames: <DataFrame>[],
      totalFrames: 0,
      totalBytes: 0,
      droppedFrames: 0,
      droppedBytes: 0,
      paused: false,
    );
  }

  final int revision;
  final List<DataFrame> frames;
  final int totalFrames;
  final int totalBytes;
  final int droppedFrames;
  final int droppedBytes;
  final bool paused;
}

/// Bounded in-memory frame log used by the virtualized console view.
class LogBuffer {
  LogBuffer({
    this.maxFrames = 10000,
    this.maxBytes = 16 * 1024 * 1024,
  });

  final int maxFrames;
  final int maxBytes;
  final ListQueue<DataFrame> _frames = ListQueue<DataFrame>();
  int _bytes = 0;
  int _revision = 0;
  int _totalFrames = 0;
  int _totalBytes = 0;
  int _droppedFrames = 0;
  int _droppedBytes = 0;
  int _droppedDataFrames = 0;
  int _droppedDataBytes = 0;
  int _retainedDataFrames = 0;
  int _retainedDataBytes = 0;
  final Map<String, int> _retainedSourceCounts = <String, int>{};

  int get totalFrames => _totalFrames;

  int get totalBytes => _totalBytes;

  int get droppedFrames => _droppedFrames;

  int get droppedBytes => _droppedBytes;

  int get retainedFrames => _frames.length;

  int get retainedBytes => _bytes;

  int get retainedDataFrames => _retainedDataFrames;

  int get retainedDataBytes => _retainedDataBytes;

  int get droppedDataFrames => _droppedDataFrames;

  int get droppedDataBytes => _droppedDataBytes;

  List<String> get retainedSourceLabels =>
      List<String>.unmodifiable(_retainedSourceCounts.keys);

  void addAll(Iterable<DataFrame> frames) {
    var changed = false;
    for (final frame in frames) {
      _frames.add(frame);
      _bytes += frame.byteLength;
      _totalFrames++;
      _totalBytes += frame.byteLength;
      if (frame.direction != FrameDirection.system) {
        _retainedDataFrames++;
        _retainedDataBytes += frame.byteLength;
      }
      _incrementSource(frame);
      changed = true;
    }
    if (!changed) {
      return;
    }

    // Display retention is bounded. Receive is not blocked by rendering.
    while (_frames.length > maxFrames || _bytes > maxBytes) {
      final removed = _frames.removeFirst();
      _bytes -= removed.byteLength;
      _droppedFrames++;
      _droppedBytes += removed.byteLength;
      if (removed.direction != FrameDirection.system) {
        _retainedDataFrames--;
        _retainedDataBytes -= removed.byteLength;
        _droppedDataFrames++;
        _droppedDataBytes += removed.byteLength;
      }
      _decrementSource(removed);
    }
    _revision++;
  }

  void clear() {
    _frames.clear();
    _bytes = 0;
    _totalFrames = 0;
    _totalBytes = 0;
    _droppedFrames = 0;
    _droppedBytes = 0;
    _droppedDataFrames = 0;
    _droppedDataBytes = 0;
    _retainedDataFrames = 0;
    _retainedDataBytes = 0;
    _retainedSourceCounts.clear();
    _revision++;
  }

  LogSnapshot snapshot({required bool paused}) {
    return LogSnapshot(
      revision: _revision,
      frames: List<DataFrame>.unmodifiable(_frames),
      totalFrames: _totalFrames,
      totalBytes: _totalBytes,
      droppedFrames: _droppedFrames,
      droppedBytes: _droppedBytes,
      paused: paused,
    );
  }

  String exportText(FrameFormatter formatter, ConsoleFormatOptions options) {
    final buffer = StringBuffer();
    for (final frame in _frames) {
      buffer.writeln(formatter.formatFrame(frame, options));
    }
    return buffer.toString();
  }

  void _incrementSource(DataFrame frame) {
    final source = _sourceToken(frame);
    _retainedSourceCounts[source] = (_retainedSourceCounts[source] ?? 0) + 1;
  }

  void _decrementSource(DataFrame frame) {
    final source = _sourceToken(frame);
    final count = _retainedSourceCounts[source];
    if (count == null) {
      return;
    }
    if (count <= 1) {
      _retainedSourceCounts.remove(source);
    } else {
      _retainedSourceCounts[source] = count - 1;
    }
  }

  String _sourceToken(DataFrame frame) {
    if (frame.direction == FrameDirection.system) {
      return 'SYS';
    }
    final source = frame.source.trim();
    return source.isEmpty ? frame.direction.label : source;
  }
}
