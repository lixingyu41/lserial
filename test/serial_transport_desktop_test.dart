@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/transports/adapters/serial_transport_desktop.dart';

void main() {
  test('writeSerialBytesFully continues after a partial write', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(1024, (index) => index & 0xff),
    );
    final chunks = <List<int>>[];

    final written = await writeSerialBytesFully(payload, (remaining) {
      chunks.add(List<int>.of(remaining));
      return chunks.length == 1 ? 720 : remaining.length;
    });

    expect(written, 1024);
    expect(chunks, hasLength(2));
    expect(chunks[0], payload);
    expect(chunks[1], payload.sublist(720));
  });

  test(
    'writeSerialBytesFully splits large writes into bounded chunks',
    () async {
      final payload = Uint8List.fromList(
        List<int>.generate(4097, (index) => index & 0xff),
      );
      final chunkLengths = <int>[];

      final written = await writeSerialBytesFully(payload, (chunk) {
        chunkLengths.add(chunk.length);
        return chunk.length;
      });

      expect(written, payload.length);
      expect(chunkLengths, <int>[1024, 1024, 1024, 1024, 1]);
    },
  );

  test('writeSerialBytesFully retries zero-progress writes', () async {
    final payload = Uint8List.fromList(<int>[1, 2, 3]);
    var calls = 0;

    final written = await writeSerialBytesFully(payload, (chunk) {
      calls++;
      return calls <= 2 ? 0 : chunk.length;
    }, retryDelay: Duration.zero);

    expect(written, payload.length);
    expect(calls, 3);
  });

  test('writeSerialBytesFully reports offset after retry exhaustion', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(2048, (index) => index & 0xff),
    );
    var acceptedFirstChunk = false;

    final write = writeSerialBytesFully(
      payload,
      (chunk) {
        if (!acceptedFirstChunk) {
          acceptedFirstChunk = true;
          return chunk.length;
        }
        return 0;
      },
      maxConsecutiveZeroWrites: 2,
      retryDelay: Duration.zero,
    );

    await expectLater(
      write,
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('1024 of 2048 bytes after 2 zero-byte retries'),
        ),
      ),
    );
  });

  test('writeSerialBytesFully rejects zero-progress writes', () async {
    final payload = Uint8List.fromList(<int>[1, 2, 3]);

    await expectLater(
      writeSerialBytesFully(
        payload,
        (_) => 0,
        maxConsecutiveZeroWrites: 0,
        retryDelay: Duration.zero,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('serialReadLengthForAvailable caps invalid driver lengths', () {
    expect(serialReadLengthForAvailable(-1), -1);
    expect(serialReadLengthForAvailable(0), 0);
    expect(serialReadLengthForAvailable(31), 31);
    expect(serialReadLengthForAvailable(1 << 62), serialMaxReadChunkBytes);
  });

  test(
    'serialReadShouldRetry treats Windows read cancellation as transient',
    () {
      expect(
        serialReadShouldRetry(const SerialPortError('Operation aborted', 995)),
        isTrue,
      );
      expect(
        serialReadShouldRetry(
          Exception('SerialPortError: 已中止 I/O 操作, errno=995'),
        ),
        isTrue,
      );
      expect(
        serialReadShouldRetry(
          const SerialPortError('Device not connected', 1167),
        ),
        isFalse,
      );
    },
  );
}
