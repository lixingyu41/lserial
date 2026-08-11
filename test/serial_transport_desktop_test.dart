@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/transports/adapters/serial_transport_desktop.dart';

void main() {
  test('writeSerialBytesFully continues after a partial write', () {
    final payload = Uint8List.fromList(
      List<int>.generate(1024, (index) => index & 0xff),
    );
    final chunks = <List<int>>[];

    final written = writeSerialBytesFully(payload, (remaining) {
      chunks.add(List<int>.of(remaining));
      return chunks.length == 1 ? 720 : remaining.length;
    });

    expect(written, 1024);
    expect(chunks, hasLength(2));
    expect(chunks[0], payload);
    expect(chunks[1], payload.sublist(720));
  });

  test('writeSerialBytesFully rejects zero-progress writes', () {
    final payload = Uint8List.fromList(<int>[1, 2, 3]);

    expect(
      () => writeSerialBytesFully(payload, (_) => 0),
      throwsA(isA<StateError>()),
    );
  });

  test('serialReadLengthForAvailable caps invalid driver lengths', () {
    expect(serialReadLengthForAvailable(-1), -1);
    expect(serialReadLengthForAvailable(0), 0);
    expect(serialReadLengthForAvailable(31), 31);
    expect(serialReadLengthForAvailable(1 << 62), serialMaxReadChunkBytes);
  });
}
