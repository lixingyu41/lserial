import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

Future<List<String>> listSerialPorts() {
  return Isolate.run<List<String>>(() => SerialPort.availablePorts);
}

Future<String?> requestSerialPort() async => null;

TransportSession createSerialSession(ConnectionConfig config) {
  return DesktopSerialTransportSession(config);
}

const int serialMaxReadChunkBytes = 64 * 1024;
const int serialMaxWriteChunkBytes = 1024;
const int serialMaxConsecutiveZeroWrites = 1000;
const Duration serialWriteRetryDelay = Duration(milliseconds: 2);
const int _windowsOperationAbortedErrorCode = 995;

typedef SerialWriteChunk = int Function(Uint8List bytes);

int serialReadLengthForAvailable(
  int available, {
  int maxChunkBytes = serialMaxReadChunkBytes,
}) {
  if (available <= 0) {
    return available;
  }
  return available > maxChunkBytes ? maxChunkBytes : available;
}

Future<int> writeSerialBytesFully(
  Uint8List bytes,
  SerialWriteChunk writeChunk, {
  int maxChunkBytes = serialMaxWriteChunkBytes,
  int maxConsecutiveZeroWrites = serialMaxConsecutiveZeroWrites,
  Duration retryDelay = serialWriteRetryDelay,
}) async {
  if (maxChunkBytes <= 0) {
    throw ArgumentError.value(maxChunkBytes, 'maxChunkBytes');
  }
  if (maxConsecutiveZeroWrites < 0) {
    throw ArgumentError.value(
      maxConsecutiveZeroWrites,
      'maxConsecutiveZeroWrites',
    );
  }

  var offset = 0;
  var consecutiveZeroWrites = 0;
  while (offset < bytes.length) {
    final remaining = bytes.length - offset;
    final chunkLength = remaining > maxChunkBytes ? maxChunkBytes : remaining;
    final chunk = Uint8List.sublistView(bytes, offset, offset + chunkLength);
    final written = writeChunk(chunk);
    if (written < 0) {
      throw StateError(
        'Serial write failed: $offset of ${bytes.length} bytes.',
      );
    }
    if (written == 0) {
      consecutiveZeroWrites++;
      if (consecutiveZeroWrites > maxConsecutiveZeroWrites) {
        throw StateError(
          'Serial write stalled: $offset of ${bytes.length} bytes after '
          '$maxConsecutiveZeroWrites zero-byte retries.',
        );
      }
      await Future<void>.delayed(retryDelay);
      continue;
    }
    if (written > chunk.length) {
      throw StateError(
        'Serial write overflow: $written of ${chunk.length} bytes.',
      );
    }
    offset += written;
    consecutiveZeroWrites = 0;
  }
  return offset;
}

bool serialReadShouldRetry(Object? error) {
  if (error == null) {
    return false;
  }
  if (error is SerialPortError &&
      error.errorCode == _windowsOperationAbortedErrorCode) {
    return true;
  }
  final message = error.toString().toLowerCase();
  return message.contains('errno=995') ||
      message.contains('errno = 995') ||
      message.contains('operation aborted') ||
      message.contains('已中止 i/o 操作');
}

class DesktopSerialTransportSession
    implements TransportSession, SerialReconfigurableTransportSession {
  DesktopSerialTransportSession(this.config);

  final ConnectionConfig config;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final Map<int, Completer<void>> _pendingRequests = <int, Completer<void>>{};

  ReceivePort? _workerEvents;
  StreamSubscription<dynamic>? _workerEventSubscription;
  Isolate? _worker;
  SendPort? _workerCommands;
  Completer<void>? _connectCompleter;
  int _nextRequestId = 0;
  bool _connected = false;

  @override
  TransportType get type => TransportType.serial;

  @override
  String get label => config.serial.portName;

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    final serial = config.serial;
    if (serial.portName.isEmpty) {
      throw StateError('No serial port selected.');
    }

    final events = ReceivePort();
    final completer = Completer<void>();
    _workerEvents = events;
    _connectCompleter = completer;
    _workerEventSubscription = events.listen(_handleWorkerEvent);

    try {
      _worker = await Isolate.spawn<List<Object?>>(_serialWorkerMain, <Object?>[
        events.sendPort,
        _serialSettings(serial),
      ], debugName: 'LSerial-${serial.portName}');
      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw SerialOpenException(
          portName: serial.portName,
          failure: SerialOpenFailure.timedOut,
        ),
      );
    } on Object {
      await _releaseWorker();
      rethrow;
    } finally {
      _connectCompleter = null;
    }
  }

  @override
  Future<void> send(List<int> bytes) async {
    if (!_connected) {
      throw StateError('Serial port is not open.');
    }
    await _sendRequest('write', <String, Object?>{
      'bytes': Uint8List.fromList(bytes),
    });
  }

  @override
  Future<void> reconfigureSerial({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required String parity,
  }) async {
    if (!_connected) {
      throw StateError('Serial port is not open.');
    }
    await _sendRequest('configure', <String, Object?>{
      'baudRate': baudRate,
      'dataBits': dataBits,
      'stopBits': stopBits,
      'parity': parity,
    });
  }

  @override
  Future<void> disconnect() async {
    final commands = _workerCommands;
    if (commands != null) {
      try {
        await _sendRequest('disconnect').timeout(const Duration(seconds: 2));
      } on Object {
        // The worker is terminated below if the driver does not close cleanly.
      }
    }
    _connected = false;
    await _releaseWorker();
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  void _handleWorkerEvent(dynamic event) {
    if (event is! Map<Object?, Object?>) {
      return;
    }
    switch (event['type']) {
      case 'commands':
        _workerCommands = event['port'] as SendPort?;
      case 'connected':
        _connected = true;
        final completer = _connectCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      case 'connectError':
        final completer = _connectCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.completeError(_openExceptionFromEvent(event));
        }
      case 'data':
        final bytes = event['bytes'];
        if (!_incoming.isClosed && bytes is Uint8List && bytes.isNotEmpty) {
          _incoming.add(bytes);
        }
      case 'streamError':
        if (!_incoming.isClosed) {
          _incoming.addError(StateError('${event['message']}'));
        }
      case 'streamDone':
        _connected = false;
        if (!_incoming.isClosed) {
          unawaited(_incoming.close());
        }
      case 'response':
        final id = event['id'];
        if (id is! int) {
          return;
        }
        final completer = _pendingRequests.remove(id);
        if (completer == null || completer.isCompleted) {
          return;
        }
        if (event['ok'] == true) {
          completer.complete();
        } else {
          completer.completeError(StateError('${event['message']}'));
        }
    }
  }

  Future<void> _sendRequest(
    String type, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    final commands = _workerCommands;
    if (commands == null) {
      throw StateError('Serial port worker is not available.');
    }
    final id = ++_nextRequestId;
    final completer = Completer<void>();
    _pendingRequests[id] = completer;
    commands.send(<String, Object?>{'type': type, 'id': id, ...fields});
    return completer.future;
  }

  Future<void> _releaseWorker() async {
    _connected = false;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _workerCommands = null;
    await _workerEventSubscription?.cancel();
    _workerEventSubscription = null;
    _workerEvents?.close();
    _workerEvents = null;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Serial port worker stopped.'));
      }
    }
    _pendingRequests.clear();
  }
}

Map<String, Object?> _serialSettings(SerialConfig serial) {
  return <String, Object?>{
    'portName': serial.portName,
    'baudRate': serial.baudRate,
    'dataBits': serial.dataBits,
    'stopBits': serial.stopBits,
    'parity': serial.parity.name,
  };
}

SerialOpenException _openExceptionFromEvent(Map<Object?, Object?> event) {
  final portName = '${event['portName']}';
  final nativeCode = event['nativeCode'] as int?;
  final nativeMessage = event['nativeMessage'] as String?;
  final stage = event['stage'] as String? ?? 'open';
  return SerialOpenException(
    portName: portName,
    failure: _classifyOpenFailure(stage, nativeCode, nativeMessage),
    nativeCode: nativeCode,
    nativeMessage: nativeCode == 0 ? null : nativeMessage,
  );
}

SerialOpenFailure _classifyOpenFailure(
  String stage,
  int? nativeCode,
  String? nativeMessage,
) {
  if (stage == 'configure' || nativeCode == 0) {
    return SerialOpenFailure.driverInitialization;
  }
  if (nativeCode == 5 ||
      nativeCode == 13 ||
      nativeCode == 16 ||
      nativeCode == 32 ||
      nativeCode == 33) {
    return SerialOpenFailure.busyOrPermission;
  }
  if (nativeCode == 2 ||
      nativeCode == 3 ||
      nativeCode == 19 ||
      nativeCode == 21 ||
      nativeCode == 1167) {
    return SerialOpenFailure.unavailable;
  }
  final lower = nativeMessage?.toLowerCase() ?? '';
  if (lower.contains('access') ||
      lower.contains('denied') ||
      lower.contains('busy') ||
      lower.contains('占用') ||
      lower.contains('拒绝访问')) {
    return SerialOpenFailure.busyOrPermission;
  }
  if (lower.contains('not found') ||
      lower.contains('disconnected') ||
      lower.contains('不存在') ||
      lower.contains('断开')) {
    return SerialOpenFailure.unavailable;
  }
  return SerialOpenFailure.unknown;
}

@pragma('vm:entry-point')
Future<void> _serialWorkerMain(List<Object?> startup) async {
  final mainPort = startup[0] as SendPort;
  final settings = startup[1] as Map<Object?, Object?>;
  final commands = ReceivePort();
  final portName = '${settings['portName']}';
  SerialPort? port;
  Timer? readTimer;
  StreamSubscription<dynamic>? commandSubscription;
  final done = Completer<void>();
  var closing = false;
  var connected = false;
  var portOpened = false;
  var unexpectedDisconnect = false;
  int? disconnectRequestId;

  mainPort.send(<String, Object?>{
    'type': 'commands',
    'port': commands.sendPort,
  });

  try {
    port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      mainPort.send(_connectErrorEvent(portName, 'open', error));
      return;
    }
    portOpened = true;

    try {
      _applySerialSettings(port, settings);
    } on Object {
      final error = SerialPort.lastError;
      mainPort.send(_connectErrorEvent(portName, 'configure', error));
      return;
    }

    final activePort = port;

    void finishUnexpectedly(Object error) {
      if (closing) {
        return;
      }
      closing = true;
      unexpectedDisconnect = true;
      mainPort.send(<String, Object?>{
        'type': 'streamError',
        'message': error.toString(),
      });
      if (!done.isCompleted) {
        done.complete();
      }
    }

    Future<void> handleCommand(dynamic rawCommand) async {
      if (rawCommand is! Map<Object?, Object?> || closing) {
        return;
      }
      final type = rawCommand['type'];
      final id = rawCommand['id'] as int?;
      if (id == null) {
        return;
      }
      try {
        if (type == 'write') {
          final bytes = rawCommand['bytes'] as Uint8List;
          await writeSerialBytesFully(bytes, activePort.write);
          activePort.drain();
          mainPort.send(_responseEvent(id, true));
        } else if (type == 'configure') {
          _applySerialSettings(activePort, rawCommand);
          mainPort.send(_responseEvent(id, true));
        } else if (type == 'disconnect') {
          closing = true;
          disconnectRequestId = id;
          if (!done.isCompleted) {
            done.complete();
          }
        }
      } on Object catch (error) {
        mainPort.send(_responseEvent(id, false, error.toString()));
        if (type != 'write' && type != 'configure') {
          finishUnexpectedly(error);
        }
      }
    }

    var commandTail = Future<void>.value();
    commandSubscription = commands.listen(
      (dynamic rawCommand) {
        commandTail = commandTail.then((_) => handleCommand(rawCommand));
      },
      onError: finishUnexpectedly,
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
    );

    readTimer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      if (closing) {
        return;
      }
      try {
        final available = activePort.bytesAvailable;
        if (available < 0) {
          final error =
              SerialPort.lastError ?? StateError('Serial device disconnected.');
          if (serialReadShouldRetry(error)) {
            return;
          }
          finishUnexpectedly(error);
          return;
        }
        final readLength = serialReadLengthForAvailable(available);
        if (readLength == 0) {
          return;
        }
        final bytes = activePort.read(readLength);
        if (bytes.isNotEmpty) {
          mainPort.send(<String, Object?>{'type': 'data', 'bytes': bytes});
        }
      } on ArgumentError catch (error) {
        if (error.toString().contains('length must be in the range')) {
          return;
        }
        if (serialReadShouldRetry(error)) {
          return;
        }
        finishUnexpectedly(error);
      } on Object catch (error) {
        if (serialReadShouldRetry(error)) {
          return;
        }
        finishUnexpectedly(error);
      }
    });
    connected = true;
    mainPort.send(const <String, Object?>{'type': 'connected'});
    await done.future;
  } on Object catch (error) {
    if (connected) {
      unexpectedDisconnect = true;
      if (!closing) {
        mainPort.send(<String, Object?>{
          'type': 'streamError',
          'message': error.toString(),
        });
      }
    } else {
      mainPort.send(<String, Object?>{
        'type': 'connectError',
        'portName': portName,
        'stage': 'open',
        'nativeMessage': error.toString(),
      });
    }
  } finally {
    closing = true;
    readTimer?.cancel();
    await commandSubscription?.cancel();
    commands.close();
    try {
      if (portOpened) {
        port?.close();
        portOpened = false;
      }
    } on Object {
      // The worker is exiting; dispose the native port even if close fails.
    }
    try {
      port?.dispose();
    } on Object {
      // No further native operations are attempted after disposal fails.
    }
    final completedDisconnectRequestId = disconnectRequestId;
    if (completedDisconnectRequestId != null) {
      mainPort.send(_responseEvent(completedDisconnectRequestId, true));
    }
    if (unexpectedDisconnect) {
      mainPort.send(const <String, Object?>{'type': 'streamDone'});
    }
  }
}

void _applySerialSettings(SerialPort port, Map<Object?, Object?> settings) {
  final portConfig = SerialPortConfig()
    ..baudRate = settings['baudRate'] as int
    ..bits = settings['dataBits'] as int
    ..stopBits = settings['stopBits'] as int
    ..parity = switch (settings['parity']) {
      'odd' => SerialPortParity.odd,
      'even' => SerialPortParity.even,
      _ => SerialPortParity.none,
    };
  portConfig.setFlowControl(SerialPortFlowControl.none);
  // SerialPort owns an assigned config and releases it with the port.
  port.config = portConfig;
}

Map<String, Object?> _connectErrorEvent(
  String portName,
  String stage,
  SerialPortError? error,
) {
  return <String, Object?>{
    'type': 'connectError',
    'portName': portName,
    'stage': stage,
    'nativeCode': error?.errorCode,
    'nativeMessage': error?.message,
  };
}

Map<String, Object?> _responseEvent(int id, bool ok, [String? message]) {
  return <String, Object?>{
    'type': 'response',
    'id': id,
    'ok': ok,
    if (message != null) 'message': message,
  };
}
