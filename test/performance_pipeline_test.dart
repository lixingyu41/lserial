import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/receive_pipeline.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/core/buffer/byte_ring_buffer.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/connection_config.dart';
import 'package:lserial/domain/data_frame.dart';
import 'package:lserial/domain/transport.dart';
import 'package:lserial/storage/log_buffer.dart';
import 'package:lserial/transports/transport_registry.dart';

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

  test('LogBuffer keeps retained source labels in sync with trimmed frames',
      () {
    final buffer = LogBuffer(maxFrames: 2, maxBytes: 1024);

    buffer.addAll(<DataFrame>[
      DataFrame(
        sequence: 1,
        timestamp: DateTime(2026),
        direction: FrameDirection.rx,
        bytes: <int>[0x41],
        source: 'COM1',
      ),
      DataFrame(
        sequence: 2,
        timestamp: DateTime(2026),
        direction: FrameDirection.rx,
        bytes: <int>[0x42],
        source: 'COM2',
      ),
      DataFrame(
        sequence: 3,
        timestamp: DateTime(2026),
        direction: FrameDirection.rx,
        bytes: <int>[0x43],
        source: 'COM3',
      ),
    ]);

    expect(buffer.retainedSourceLabels, isNot(contains('COM1')));
    expect(buffer.retainedSourceLabels, containsAll(<String>['COM2', 'COM3']));
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

  test('ReceivePipeline flushes delimiter tail by idle packet interval',
      () async {
    final raw = ByteRingBuffer(1024);
    final batches = <List<DataFrame>>[];
    var sequence = 0;
    final pipeline = ReceivePipeline(
      rawBuffer: raw,
      packetInterval: const Duration(milliseconds: 20),
      packetDelimiter: const <int>[0x0d, 0x0a],
      flushInterval: const Duration(seconds: 1),
      nextSequence: () => ++sequence,
      onBatch: batches.add,
    );

    pipeline.addBytes(<int>[0x41, 0x0d, 0x0a, 0x42], source: 'rx');

    expect(batches, hasLength(1));
    expect(
      batches.single.single.bytes,
      Uint8List.fromList(<int>[0x41, 0x0d, 0x0a]),
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(batches, hasLength(2));
    expect(
      batches.last.single.bytes,
      Uint8List.fromList(<int>[0x42]),
    );

    pipeline.dispose();
  });

  test('SessionController receive path updates snapshots and stats only',
      () async {
    final transport = _FakeTransportSession();
    final controller = SessionController(
      registry: _FakeTransportRegistry(transport),
    );
    addTearDown(controller.dispose);
    controller.capabilities = const <TransportCapability>[
      TransportCapability(
        type: TransportType.serial,
        supported: true,
        reason: '',
      ),
    ];
    controller.updateConfig(
      const ConnectionConfig(
        type: TransportType.serial,
        serial: SerialConfig(portName: 'COM1', packetDelimiter: ''),
      ),
    );

    await controller.connect();

    var controllerNotifications = 0;
    var snapshotNotifications = 0;
    var statsNotifications = 0;
    controller.addListener(() => controllerNotifications++);
    controller.displaySnapshot.addListener(() => snapshotNotifications++);
    controller.statsListenable.addListener(() => statsNotifications++);

    transport.addIncoming(<int>[0x41]);
    transport.addIncoming(<int>[0x42]);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(controller.displaySnapshot.value.frames.last.bytes,
        Uint8List.fromList(<int>[0x41, 0x42]));
    expect(snapshotNotifications, greaterThan(0));
    expect(statsNotifications, greaterThan(0));
    expect(controllerNotifications, 0);
  });

  test('SessionController sends raw terminal control bytes', () async {
    final transport = _FakeTransportSession();
    final controller = SessionController(
      registry: _FakeTransportRegistry(transport),
    );
    addTearDown(controller.dispose);
    controller.capabilities = const <TransportCapability>[
      TransportCapability(
        type: TransportType.serial,
        supported: true,
        reason: '',
      ),
    ];
    controller.updateConfig(
      const ConnectionConfig(
        type: TransportType.serial,
        serial: SerialConfig(portName: 'COM1', packetDelimiter: ''),
      ),
    );

    await controller.connect();
    controller.setSendFormat(PayloadFormat.hex);

    await controller.sendRawBytes(<int>[0x03]);

    expect(transport.sentBytes.single, <int>[0x03]);
    expect(controller.sendHistory, isEmpty);
    expect(controller.displaySnapshot.value.frames.last.bytes,
        Uint8List.fromList(<int>[0x03]));
  });
}

class _FakeTransportRegistry extends TransportRegistry {
  const _FakeTransportRegistry(this.session);

  final _FakeTransportSession session;

  @override
  Future<TransportSession> create(ConnectionConfig config) async => session;

  @override
  Future<List<String>> serialPorts() async => const <String>['COM1'];
}

class _FakeTransportSession implements TransportSession {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentBytes = <List<int>>[];
  var _connected = false;

  @override
  TransportType get type => TransportType.serial;

  @override
  String get label => 'COM1';

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _incoming.close();
  }

  @override
  Future<void> send(List<int> bytes) async {
    sentBytes.add(List<int>.of(bytes));
  }

  void addIncoming(List<int> bytes) {
    _incoming.add(bytes);
  }
}
