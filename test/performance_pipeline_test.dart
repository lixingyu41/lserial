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

  test(
    'LogBuffer keeps retained source labels in sync with trimmed frames',
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
      expect(
        buffer.retainedSourceLabels,
        containsAll(<String>['COM2', 'COM3']),
      );
    },
  );

  test(
    'ReceivePipeline batches high-frequency chunks before UI commit',
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
    },
  );

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
    expect(
      batches.single.single.bytes,
      Uint8List.fromList(List<int>.generate(8, (index) => index)),
    );
    expect(raw.length, 8);

    pipeline.dispose();
  });

  test('ReceivePipeline previews a packet before its idle gap', () async {
    final raw = ByteRingBuffer(1024);
    final batches = <List<DataFrame>>[];
    final previews = <DataFrame>[];
    var sequence = 0;
    final pipeline = ReceivePipeline(
      rawBuffer: raw,
      packetInterval: const Duration(milliseconds: 100),
      previewInterval: const Duration(milliseconds: 10),
      flushInterval: const Duration(seconds: 1),
      nextSequence: () => ++sequence,
      onBatch: batches.add,
      onPacketPreview: previews.add,
    );

    pipeline.addBytes(<int>[0x41], source: 'rx');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(batches, isEmpty);
    expect(previews.last.bytes, Uint8List.fromList(<int>[0x41]));
    final packetSequence = previews.last.sequence;

    pipeline.addBytes(<int>[0x42], source: 'rx');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(previews.last.bytes, Uint8List.fromList(<int>[0x41, 0x42]));

    await Future<void>.delayed(const Duration(milliseconds: 110));
    expect(batches, hasLength(1));
    expect(batches.single, hasLength(1));
    expect(batches.single.single.sequence, packetSequence);
    expect(batches.single.single.bytes, Uint8List.fromList(<int>[0x41, 0x42]));

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
    expect(batches.single.map((frame) => frame.bytes).toList(), <Uint8List>[
      Uint8List.fromList(<int>[0x41, 0x0d, 0x0a]),
      Uint8List.fromList(<int>[0x42, 0x0d, 0x0a]),
    ]);
    expect(raw.length, 6);

    pipeline.dispose();
  });

  test(
    'ReceivePipeline flushes delimiter tail by idle packet interval',
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
      expect(batches.last.single.bytes, Uint8List.fromList(<int>[0x42]));

      pipeline.dispose();
    },
  );

  test(
    'SessionController receive path updates snapshots and stats only',
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

      expect(
        controller.displaySnapshot.value.frames.last.bytes,
        Uint8List.fromList(<int>[0x41, 0x42]),
      );
      expect(snapshotNotifications, greaterThan(0));
      expect(statsNotifications, greaterThan(0));
      expect(controllerNotifications, 0);
    },
  );

  test(
    'SessionController replaces a live packet preview when it commits',
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
          serial: SerialConfig(
            portName: 'COM1',
            packetIntervalMs: 120,
            packetDelimiter: '',
          ),
        ),
      );

      await controller.connect();
      transport.addIncoming(<int>[0x41]);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      var displayedTraffic = controller.displaySnapshot.value.frames
          .where((frame) => frame.direction != FrameDirection.system)
          .toList();
      expect(displayedTraffic, hasLength(1));
      expect(displayedTraffic.single.bytes, Uint8List.fromList(<int>[0x41]));
      expect(
        controller.logBuffer
            .snapshot(paused: false)
            .frames
            .where((frame) => frame.direction != FrameDirection.system),
        isEmpty,
      );

      transport.addIncoming(<int>[0x42]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      displayedTraffic = controller.displaySnapshot.value.frames
          .where((frame) => frame.direction != FrameDirection.system)
          .toList();
      expect(displayedTraffic, hasLength(1));
      expect(
        displayedTraffic.single.bytes,
        Uint8List.fromList(<int>[0x41, 0x42]),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      displayedTraffic = controller.displaySnapshot.value.frames
          .where((frame) => frame.direction != FrameDirection.system)
          .toList();
      final committedTraffic = controller.logBuffer
          .snapshot(paused: false)
          .frames
          .where((frame) => frame.direction != FrameDirection.system)
          .toList();
      expect(displayedTraffic, hasLength(1));
      expect(committedTraffic, hasLength(1));
      expect(
        displayedTraffic.single.sequence,
        committedTraffic.single.sequence,
      );
    },
  );

  test('SessionController clear discards an unfinished packet', () async {
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
        serial: SerialConfig(
          portName: 'COM1',
          packetIntervalMs: 100,
          packetDelimiter: '',
        ),
      ),
    );

    await controller.connect();
    transport.addIncoming(<int>[0x41]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.clearLog();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.displaySnapshot.value.frames, isEmpty);
    expect(controller.logBuffer.snapshot(paused: false).frames, isEmpty);
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
    expect(
      controller.displaySnapshot.value.frames.last.bytes,
      Uint8List.fromList(<int>[0x03]),
    );
  });

  test('SessionController ignores rapid duplicate connect requests', () async {
    final transport = _FakeTransportSession(
      connectDelay: const Duration(milliseconds: 50),
    );
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

    await Future.wait<void>(<Future<void>>[
      controller.connect(),
      controller.connect(),
      controller.connect(),
    ]);

    expect(transport.connectCalls, 1);
    expect(controller.status, TransportStatus.connected);
  });

  test(
    'SessionController notifies when refreshed serial ports change',
    () async {
      final transport = _FakeTransportSession();
      final registry = _MutableSerialPortRegistry(transport);
      final controller = SessionController(registry: registry);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.refreshSerialPorts();
      final notificationsBeforeInsert = notifications;
      registry.ports.add('COM9');
      await controller.refreshSerialPorts();

      expect(controller.serialPorts, <String>['COM9']);
      expect(controller.config.serial.portName, 'COM9');
      expect(notifications, greaterThan(notificationsBeforeInsert));
    },
  );

  test('SessionController disconnects after a receive error', () async {
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
    transport.addIncomingError(StateError('device removed'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.status, TransportStatus.error);
    expect(transport.isConnected, isFalse);
  });

  test('SessionController auto send does not overlap slow sends', () async {
    final transport = _FakeTransportSession(
      sendDelay: const Duration(milliseconds: 60),
    );
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
    controller.startAutoSend('A', const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 130));
    controller.stopAutoSend();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(transport.sentBytes, isNotEmpty);
    expect(transport.maxConcurrentSends, 1);
  });

  test('SessionController forwards serial bytes in both directions', () async {
    final primary = _FakeTransportSession(label: 'COM1');
    final peer = _FakeTransportSession(label: 'COM2');
    final controller = SessionController(
      registry: _ForwardingTransportRegistry(<String, TransportSession>{
        'COM1': primary,
        'COM2': peer,
      }),
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
        serial: SerialConfig(
          portName: 'COM1',
          packetIntervalMs: 0,
          packetDelimiter: '',
          forwardingEnabled: true,
          forwardPortName: 'COM2',
        ),
      ),
    );

    await controller.connect();
    primary.addIncoming(<int>[0x41, 0x42]);
    peer.addIncoming(<int>[0x43]);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(peer.sentBytes, <List<int>>[
      <int>[0x41, 0x42],
    ]);
    expect(primary.sentBytes, <List<int>>[
      <int>[0x43],
    ]);
    final traffic = controller.displaySnapshot.value.frames
        .where((frame) => frame.direction != FrameDirection.system)
        .toList();
    expect(traffic.map((frame) => frame.source), <String>[
      'COM1 → COM2',
      'COM2 → COM1',
    ]);
    expect(traffic.map((frame) => frame.direction), <FrameDirection>[
      FrameDirection.tx,
      FrameDirection.rx,
    ]);
  });

  test(
    'SessionController rejects forwarding to the same serial port',
    () async {
      final primary = _FakeTransportSession(label: 'COM1');
      final controller = SessionController(
        registry: _ForwardingTransportRegistry(<String, TransportSession>{
          'COM1': primary,
        }),
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
          serial: SerialConfig(
            portName: 'COM1',
            forwardingEnabled: true,
            forwardPortName: 'com1',
          ),
        ),
      );

      await controller.connect();

      expect(controller.status, TransportStatus.error);
      expect(primary.isConnected, isFalse);
    },
  );

  test('Serial forwarding serializes writes to a slow destination', () async {
    final primary = _FakeTransportSession(label: 'COM1');
    final peer = _FakeTransportSession(
      label: 'COM2',
      sendDelay: const Duration(milliseconds: 30),
    );
    final controller = SessionController(
      registry: _ForwardingTransportRegistry(<String, TransportSession>{
        'COM1': primary,
        'COM2': peer,
      }),
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
        serial: SerialConfig(
          portName: 'COM1',
          packetIntervalMs: 0,
          packetDelimiter: '',
          forwardingEnabled: true,
          forwardPortName: 'COM2',
        ),
      ),
    );

    await controller.connect();
    primary.addIncoming(<int>[1]);
    primary.addIncoming(<int>[2]);
    primary.addIncoming(<int>[3]);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(peer.sentBytes, <List<int>>[
      <int>[1],
      <int>[2],
      <int>[3],
    ]);
    expect(peer.maxConcurrentSends, 1);
  });

  test(
    'Serial forwarding closes the other port after one side disconnects',
    () async {
      final primary = _FakeTransportSession(label: 'COM1');
      final peer = _FakeTransportSession(label: 'COM2');
      final controller = SessionController(
        registry: _ForwardingTransportRegistry(<String, TransportSession>{
          'COM1': primary,
          'COM2': peer,
        }),
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
          serial: SerialConfig(
            portName: 'COM1',
            forwardingEnabled: true,
            forwardPortName: 'COM2',
          ),
        ),
      );

      await controller.connect();
      await peer.closeIncoming();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.status, TransportStatus.error);
      expect(primary.isConnected, isFalse);
      expect(peer.isConnected, isFalse);
    },
  );
}

class _FakeTransportRegistry extends TransportRegistry {
  const _FakeTransportRegistry(this.session);

  final _FakeTransportSession session;

  @override
  Future<TransportSession> create(ConnectionConfig config) async => session;

  @override
  Future<List<String>> serialPorts() async => const <String>['COM1'];
}

class _ForwardingTransportRegistry extends TransportRegistry {
  const _ForwardingTransportRegistry(this.sessions);

  final Map<String, TransportSession> sessions;

  @override
  Future<TransportSession> create(ConnectionConfig config) async {
    final session = sessions[config.serial.portName];
    if (session == null) {
      throw StateError('Missing fake serial ${config.serial.portName}.');
    }
    return session;
  }

  @override
  Future<List<String>> serialPorts() async => sessions.keys.toList();
}

class _MutableSerialPortRegistry extends TransportRegistry {
  _MutableSerialPortRegistry(this.session);

  final _FakeTransportSession session;
  final List<String> ports = <String>[];

  @override
  Future<TransportSession> create(ConnectionConfig config) async => session;

  @override
  Future<List<String>> serialPorts() async => List<String>.of(ports);
}

class _FakeTransportSession implements TransportSession {
  _FakeTransportSession({
    this.label = 'COM1',
    this.connectDelay = Duration.zero,
    this.sendDelay = Duration.zero,
  });

  @override
  final String label;
  final Duration connectDelay;
  final Duration sendDelay;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentBytes = <List<int>>[];
  int maxConcurrentSends = 0;
  int _activeSends = 0;
  int connectCalls = 0;
  var _connected = false;

  @override
  TransportType get type => TransportType.serial;

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    if (connectDelay != Duration.zero) {
      await Future<void>.delayed(connectDelay);
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  @override
  Future<void> send(List<int> bytes) async {
    _activeSends++;
    if (_activeSends > maxConcurrentSends) {
      maxConcurrentSends = _activeSends;
    }
    try {
      if (sendDelay != Duration.zero) {
        await Future<void>.delayed(sendDelay);
      }
      sentBytes.add(List<int>.of(bytes));
    } finally {
      _activeSends--;
    }
  }

  void addIncoming(List<int> bytes) {
    _incoming.add(bytes);
  }

  void addIncomingError(Object error) {
    _incoming.addError(error);
  }

  Future<void> closeIncoming() => _incoming.close();
}
