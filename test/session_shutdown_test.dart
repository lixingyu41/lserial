import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/application/session_controller.dart';
import 'package:lserial/domain/connection_config.dart';
import 'package:lserial/domain/transport.dart';
import 'package:lserial/transports/transport_registry.dart';

void main() {
  test('shutdown cancels a serial port while it is still opening', () async {
    final transport = _ControlledSession(waitForConnect: true);
    final registry = _ControlledRegistry(<_ControlledSession>[transport]);
    final controller = _controller(registry);
    addTearDown(controller.dispose);
    final opening = controller.connect();
    await transport.connectStarted.future;

    await controller.shutdown().timeout(const Duration(seconds: 1));
    await opening;

    expect(transport.disconnectCalls, 1);
    expect(transport.isConnected, isFalse);
    expect(controller.status, TransportStatus.disconnected);
    await controller.connect();
    expect(registry.createCalls, 1);
  });

  test(
    'shutdown cancels a serial forwarding port while it is opening',
    () async {
      final primary = _ControlledSession();
      final peer = _ControlledSession(waitForConnect: true);
      final registry = _ControlledRegistry(<_ControlledSession>[primary, peer]);
      final controller = _controller(registry, forwarding: true);
      addTearDown(controller.dispose);
      final opening = controller.connect();
      await peer.connectStarted.future;

      await controller.shutdown().timeout(const Duration(seconds: 1));
      await opening;

      expect(primary.disconnectCalls, 1);
      expect(peer.disconnectCalls, 1);
      expect(primary.isConnected, isFalse);
      expect(peer.isConnected, isFalse);
      expect(controller.status, TransportStatus.disconnected);
    },
  );

  test(
    'shutdown closes a session created after shutdown was requested',
    () async {
      final transport = _ControlledSession();
      final registry = _ControlledRegistry(<_ControlledSession>[transport])
        ..createGate = Completer<void>();
      final controller = _controller(registry);
      addTearDown(controller.dispose);
      final opening = controller.connect();
      await registry.createStarted.future;

      await controller.shutdown();
      registry.createGate!.complete();
      await opening;

      expect(transport.connectCalls, 0);
      expect(transport.disconnectCalls, 1);
      expect(controller.status, TransportStatus.disconnected);
    },
  );

  test(
    'shutdown shares cleanup for connected and already closed sessions',
    () async {
      final transport = _ControlledSession();
      final controller = _controller(
        _ControlledRegistry(<_ControlledSession>[transport]),
      );
      addTearDown(controller.dispose);
      await controller.connect();

      final first = controller.shutdown();
      expect(identical(first, controller.shutdown()), isTrue);
      await first;
      await controller.shutdown();

      expect(transport.disconnectCalls, 1);
      expect(controller.status, TransportStatus.disconnected);
    },
  );

  test('manual disconnect during open cannot restore a connection', () async {
    final transport = _ControlledSession(waitForConnect: true);
    final controller = _controller(
      _ControlledRegistry(<_ControlledSession>[transport]),
    );
    addTearDown(controller.dispose);
    final opening = controller.connect();
    await transport.connectStarted.future;

    await controller.disconnect();
    await opening;

    expect(transport.isConnected, isFalse);
    expect(controller.status, TransportStatus.disconnected);
  });

  test(
    'shutdown starts both port cleanups before either one finishes',
    () async {
      final primary = _ControlledSession();
      final peer = _ControlledSession()..disconnectGate = Completer<void>();
      final controller = _controller(
        _ControlledRegistry(<_ControlledSession>[primary, peer]),
        forwarding: true,
      );
      addTearDown(controller.dispose);
      await controller.connect();

      final closing = controller.shutdown();
      try {
        await primary.disconnectStarted.future.timeout(
          const Duration(seconds: 1),
        );
        expect(peer.disconnectStarted.isCompleted, isTrue);
      } finally {
        peer.disconnectGate!.complete();
        await closing;
      }
    },
  );
  for (final disposeDuringCleanup in <bool>[false, true]) {
    test(
      'failed connect cleanup preserves shutdown, disposed=$disposeDuringCleanup',
      () async {
        final transport = _ControlledSession(
          connectError: StateError('Open failed'),
        )..disconnectGate = Completer<void>();
        final controller = _controller(
          _ControlledRegistry(<_ControlledSession>[transport]),
        );
        if (!disposeDuringCleanup) {
          addTearDown(controller.dispose);
        }
        final opening = controller.connect();
        await transport.disconnectStarted.future;

        await controller.shutdown();
        if (disposeDuringCleanup) {
          controller.dispose();
        }
        transport.disconnectGate!.complete();
        await opening;

        expect(controller.status, TransportStatus.disconnected);
      },
    );
  }
  for (final disposeDuringScan in <bool>[false, true]) {
    test(
      'cancel reconnect during serial enumeration, disposed=$disposeDuringScan',
      () async {
        final transport = _ControlledSession();
        final registry = _ControlledRegistry(<_ControlledSession>[
          transport,
          _ControlledSession(),
        ])..portsGate = Completer<List<String>>();
        final controller = _controller(registry);
        if (!disposeDuringScan) {
          addTearDown(controller.dispose);
        }
        await controller.connect();
        await transport.closeIncoming();
        await registry.portsRequested.future.timeout(
          const Duration(seconds: 1),
        );

        await controller.disconnect();
        if (disposeDuringScan) {
          controller.dispose();
        }
        registry.portsGate!.complete(<String>['COM1']);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.status, TransportStatus.disconnected);
        expect(registry.createCalls, 1);
      },
    );
  }
}

SessionController _controller(
  _ControlledRegistry registry, {
  bool forwarding = false,
}) {
  return SessionController(registry: registry)
    ..capabilities = const <TransportCapability>[
      TransportCapability(
        type: TransportType.serial,
        supported: true,
        reason: '',
      ),
    ]
    ..config = ConnectionConfig(
      serial: SerialConfig(
        portName: 'COM1',
        forwardingEnabled: forwarding,
        forwardPortName: 'COM2',
      ),
    );
}

class _ControlledRegistry extends TransportRegistry {
  _ControlledRegistry(this.sessions);

  final List<_ControlledSession> sessions;
  final Completer<void> createStarted = Completer<void>();
  Completer<void>? createGate;
  final Completer<void> portsRequested = Completer<void>();
  Completer<List<String>>? portsGate;
  int createCalls = 0;

  @override
  Future<TransportSession> create(ConnectionConfig config) async {
    final session = sessions[createCalls++];
    if (!createStarted.isCompleted) {
      createStarted.complete();
    }
    await createGate?.future;
    return session;
  }

  @override
  Future<List<String>> serialPorts() async {
    if (!portsRequested.isCompleted) {
      portsRequested.complete();
    }
    return portsGate?.future ?? Future<List<String>>.value(<String>[]);
  }
}

class _ControlledSession implements TransportSession {
  _ControlledSession({this.waitForConnect = false, this.connectError});

  final bool waitForConnect;
  final Object? connectError;
  final Completer<void> connectStarted = Completer<void>();
  final Completer<void> disconnectStarted = Completer<void>();
  final Completer<void> _connectGate = Completer<void>();
  Completer<void>? disconnectGate;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  int connectCalls = 0;
  int disconnectCalls = 0;
  bool _connected = false;

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
    connectCalls++;
    connectStarted.complete();
    if (waitForConnect) {
      await _connectGate.future;
    }
    if (connectError != null) {
      throw connectError!;
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    if (!disconnectStarted.isCompleted) {
      disconnectStarted.complete();
    }
    _connected = false;
    if (waitForConnect && !_connectGate.isCompleted) {
      _connectGate.completeError(StateError('Open canceled'));
    }
    await disconnectGate?.future;
    await _incoming.close();
  }

  @override
  Future<void> send(List<int> bytes) async {}

  Future<void> closeIncoming() => _incoming.close();
}
