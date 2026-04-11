import 'dart:typed_data';

/// Fixed-size byte ring for retaining recent raw traffic without growing memory.
class ByteRingBuffer {
  ByteRingBuffer(this.capacityBytes)
      : assert(capacityBytes > 0),
        _buffer = Uint8List(capacityBytes);

  final int capacityBytes;
  final Uint8List _buffer;
  int _start = 0;
  int _length = 0;
  int _droppedBytes = 0;

  int get length => _length;

  int get droppedBytes => _droppedBytes;

  void clear() {
    _start = 0;
    _length = 0;
    _droppedBytes = 0;
  }

  /// Writes bytes while dropping oldest bytes when the capacity is exceeded.
  void write(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }

    var source = bytes;
    if (source.length > capacityBytes) {
      _droppedBytes += source.length - capacityBytes;
      source = source.sublist(source.length - capacityBytes);
      _start = 0;
      _length = 0;
    }

    final overflow = _length + source.length - capacityBytes;
    if (overflow > 0) {
      _start = (_start + overflow) % capacityBytes;
      _length -= overflow;
      _droppedBytes += overflow;
    }

    var writeIndex = (_start + _length) % capacityBytes;
    for (final byte in source) {
      _buffer[writeIndex] = byte.toUnsigned(8);
      writeIndex = (writeIndex + 1) % capacityBytes;
    }
    _length += source.length;
  }

  Uint8List snapshot() {
    final out = Uint8List(_length);
    for (var i = 0; i < _length; i++) {
      out[i] = _buffer[(_start + i) % capacityBytes];
    }
    return out;
  }
}
