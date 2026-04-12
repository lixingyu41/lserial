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

  int get totalFrames => _totalFrames;

  int get totalBytes => _totalBytes;

  int get droppedFrames => _droppedFrames;

  int get droppedBytes => _droppedBytes;

  int get retainedFrames => _frames.length;

  int get retainedBytes => _bytes;

  void addAll(Iterable<DataFrame> frames) {
    var changed = false;
    for (final frame in frames) {
      _frames.add(frame);
      _bytes += frame.byteLength;
      _totalFrames++;
      _totalBytes += frame.byteLength;
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
}
