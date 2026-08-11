import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/classic_bluetooth_diagnostic.dart';
import '../../domain/classic_bluetooth_device_info.dart';
import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

final _ClassicBluetoothPlatform _platform = _ClassicBluetoothPlatform();

TransportSession createClassicBluetoothSession(ConnectionConfig config) {
  if (!Platform.isWindows) {
    return UnsupportedTransportSession(
      type: TransportType.bluetoothClassic,
      reason: 'Bluetooth Classic RFCOMM/SPP is available on Windows only.',
    );
  }
  return ClassicBluetoothTransportSession(config.bluetoothClassic);
}

Future<List<ClassicBluetoothDeviceInfo>> scanClassicBluetoothDevices({
  Duration timeout = const Duration(seconds: 6),
}) async {
  _requireWindows();
  try {
    return await _platform.scan(timeout);
  } on PlatformException catch (error) {
    throw _classicBluetoothException(error, operation: 'scan');
  }
}

Future<ClassicBluetoothDeviceInfo> pairClassicBluetoothDevice(
  String address,
) async {
  _requireWindows();
  try {
    return await _platform.pair(address);
  } on PlatformException catch (error) {
    throw _classicBluetoothException(
      error,
      operation: 'pair',
      address: address,
    );
  }
}

Future<void> unpairClassicBluetoothDevice(String address) async {
  _requireWindows();
  try {
    await _platform.unpair(address);
  } on PlatformException catch (error) {
    throw _classicBluetoothException(
      error,
      operation: 'unpair',
      address: address,
    );
  }
}

void _requireWindows() {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Bluetooth Classic RFCOMM/SPP is available on Windows only.',
    );
  }
}

class ClassicBluetoothTransportSession implements TransportSession {
  ClassicBluetoothTransportSession(this.config)
    : _sessionId =
          'classic_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';

  static int _nextId = 1;

  final ClassicBluetoothConfig config;
  final String _sessionId;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  bool _connected = false;
  bool _disconnecting = false;

  @override
  TransportType get type => TransportType.bluetoothClassic;

  @override
  String get label {
    final name = config.deviceName.trim();
    return 'BT ${name.isEmpty ? config.address.trim() : name}';
  }

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    final address = config.address.trim();
    if (address.isEmpty) {
      throw StateError('Bluetooth Classic device is not selected.');
    }
    _platform.register(_sessionId, this);
    try {
      await _platform.connect(_sessionId, address, config.rfcommChannel);
      _connected = true;
    } on PlatformException catch (error) {
      _platform.unregister(_sessionId);
      throw _classicBluetoothException(
        error,
        operation: 'connect',
        address: address,
      );
    } on Object {
      _platform.unregister(_sessionId);
      rethrow;
    }
  }

  @override
  Future<void> send(List<int> bytes) async {
    if (!_connected) {
      throw StateError('Bluetooth Classic session is not connected.');
    }
    try {
      await _platform.send(_sessionId, bytes);
    } on PlatformException catch (error) {
      throw _classicBluetoothException(
        error,
        operation: 'send',
        address: config.address,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disconnecting) {
      return;
    }
    _disconnecting = true;
    try {
      if (_connected) {
        await _platform.disconnect(_sessionId);
      }
    } finally {
      _connected = false;
      _platform.unregister(_sessionId);
      if (!_incoming.isClosed) {
        await _incoming.close();
      }
      _disconnecting = false;
    }
  }

  void addIncoming(Uint8List bytes) {
    if (_connected && !_incoming.isClosed) {
      _incoming.add(bytes);
    }
  }

  void handleDisconnected(Map<Object?, Object?> arguments) {
    if (_disconnecting || !_connected) {
      return;
    }
    _connected = false;
    final message = arguments['message'] as String? ?? '';
    if (message.isNotEmpty && !_incoming.isClosed) {
      _incoming.addError(
        ClassicBluetoothOperationException(
          _diagnosticFromDetails(
            arguments,
            operation: 'receive',
            address: config.address,
            fallbackMessage: message,
          ),
        ),
      );
    }
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
    _platform.unregister(_sessionId);
  }
}

class _ClassicBluetoothPlatform {
  _ClassicBluetoothPlatform() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'lserial/classic_bluetooth',
  );
  final Map<String, ClassicBluetoothTransportSession> _sessions =
      <String, ClassicBluetoothTransportSession>{};

  void register(String id, ClassicBluetoothTransportSession session) {
    _sessions[id] = session;
  }

  void unregister(String id) {
    _sessions.remove(id);
  }

  Future<List<ClassicBluetoothDeviceInfo>> scan(Duration timeout) async {
    final values =
        await _channel.invokeListMethod<Object?>('scan', <String, Object?>{
          'timeout_ms': timeout.inMilliseconds,
        }) ??
        const <Object?>[];
    return values
        .whereType<Map<Object?, Object?>>()
        .map(_deviceFromMap)
        .toList(growable: false);
  }

  Future<ClassicBluetoothDeviceInfo> pair(String address) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'pair',
      <String, Object?>{'address': address},
    );
    if (value == null) {
      throw StateError('Bluetooth Classic pairing returned no device.');
    }
    return _deviceFromMap(value);
  }

  Future<void> unpair(String address) {
    return _channel.invokeMethod<void>('unpair', <String, Object?>{
      'address': address,
    });
  }

  Future<void> connect(String sessionId, String address, int rfcommChannel) {
    return _channel.invokeMethod<void>('connect', <String, Object?>{
      'session_id': sessionId,
      'address': address,
      'rfcomm_channel': rfcommChannel,
    });
  }

  Future<void> send(String sessionId, List<int> bytes) {
    return _channel.invokeMethod<void>('send', <String, Object?>{
      'session_id': sessionId,
      'data': Uint8List.fromList(bytes),
    });
  }

  Future<void> disconnect(String sessionId) {
    return _channel.invokeMethod<void>('disconnect', <String, Object?>{
      'session_id': sessionId,
    });
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map) {
      return;
    }
    final sessionId = arguments['session_id'] as String?;
    if (sessionId == null) {
      return;
    }
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    switch (call.method) {
      case 'data':
        final data = arguments['data'];
        if (data is Uint8List) {
          session.addIncoming(data);
        }
        return;
      case 'disconnected':
        session.handleDisconnected(arguments.cast<Object?, Object?>());
        return;
    }
  }

  ClassicBluetoothDeviceInfo _deviceFromMap(Map<Object?, Object?> value) {
    return ClassicBluetoothDeviceInfo(
      address: value['address'] as String? ?? '',
      name: value['name'] as String? ?? '',
      paired: value['paired'] as bool? ?? false,
      connected: value['connected'] as bool? ?? false,
      remembered: value['remembered'] as bool? ?? false,
    );
  }
}

ClassicBluetoothOperationException _classicBluetoothException(
  PlatformException error, {
  required String operation,
  String? address,
}) {
  final details = error.details;
  return ClassicBluetoothOperationException(
    _diagnosticFromDetails(
      details is Map ? details.cast<Object?, Object?>() : const {},
      operation: operation,
      address: address,
      fallbackMessage: error.message ?? error.code,
    ),
  );
}

ClassicBluetoothDiagnostic _diagnosticFromDetails(
  Map<Object?, Object?> details, {
  required String operation,
  String? address,
  required String fallbackMessage,
}) {
  final nativeCode = (details['native_code'] as num?)?.toInt();
  final resolvedOperation = details['operation'] as String? ?? operation;
  final stage = details['stage'] as String? ?? 'request';
  return ClassicBluetoothDiagnostic(
    id: 0,
    timestamp: DateTime.now(),
    operation: resolvedOperation,
    stage: stage,
    level: 'error',
    address: details['address'] as String? ?? address,
    nativeCodeType: details['native_code_type'] as String?,
    nativeCode: nativeCode,
    elapsedMs: (details['elapsed_ms'] as num?)?.toInt(),
    message: details['message'] as String? ?? fallbackMessage,
    suggestion:
        details['suggestion'] as String? ??
        _diagnosticSuggestion(resolvedOperation, stage, nativeCode),
  );
}

String? _diagnosticSuggestion(String operation, String stage, int? nativeCode) {
  if (nativeCode == 258 || nativeCode == 1460 || nativeCode == 10060) {
    return '设备未在系统超时内响应；确认设备处于可发现/配对模式并靠近电脑后重试。';
  }
  if (nativeCode == 1223) {
    return 'Windows 安全确认被取消；重新配对并完成系统确认。';
  }
  if (nativeCode == 1168 || stage == 'device_discovery') {
    return '系统没有找到该地址；重新扫描，并确认设备仍处于经典蓝牙可发现状态。';
  }
  if (nativeCode == 5) {
    return 'Windows 拒绝了操作；检查蓝牙服务状态和当前用户权限。';
  }
  if (nativeCode == 50) {
    return '设备或适配器不支持该操作；确认目标设备提供经典蓝牙 SPP 服务。';
  }
  if (nativeCode == 10061 || stage == 'service_connect') {
    return '设备拒绝 RFCOMM 连接；确认设备已配对且提供 SPP 串口服务。';
  }
  if (nativeCode == 10054 || nativeCode == 10057) {
    return 'RFCOMM 连接已断开；检查设备供电、距离和单连接占用情况。';
  }
  if (operation == 'pair' && stage == 'verification') {
    return 'Windows 配对调用已返回，但未确认认证状态；刷新扫描结果后重试。';
  }
  return null;
}
