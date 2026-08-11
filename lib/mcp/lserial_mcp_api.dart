import 'dart:async';
import 'dart:convert';

import '../application/session_controller.dart';
import '../application/workspace_controller.dart';
import '../core/encoding/data_format.dart';
import '../domain/connection_config.dart';
import '../domain/classic_bluetooth_device_info.dart';
import '../domain/data_frame.dart';
import '../domain/quick_command.dart';
import '../domain/send_request.dart';
import '../domain/transport.dart';

const mcpAiSource = 'AI[1]';

class LSerialMcpOperationException implements Exception {
  const LSerialMcpOperationException(this.message, this.details);

  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => message;
}

class LSerialMcpApi {
  LSerialMcpApi(this.workspace);

  final WorkspaceController workspace;
  Future<void> _mutationTail = Future<void>.value();

  Map<String, Object?> state() => <String, Object?>{
    'active_session_id': sessionId(workspace.activeSession),
    'session_count': workspace.sessions.length,
    'connected_session_count': workspace.connectedSessionCount,
    'sessions': workspace.sessions.map(sessionState).toList(),
  };

  List<Map<String, Object?>> listSessions() =>
      workspace.sessions.map(sessionState).toList();

  Future<Map<String, Object?>> createSession() => _mutate(() async {
    final session = await workspace.createAutomationSession();
    _audit(session, '创建连接页');
    return sessionState(session);
  });

  Future<Map<String, Object?>> deleteSession(String? id) => _mutate(() async {
    final session = requireSession(id);
    final deletedId = sessionId(session);
    if (session.isConnected) {
      throw StateError('Disconnect the session before deleting it.');
    }
    _audit(session, '删除连接页');
    if (!workspace.removeAutomationSession(session)) {
      throw StateError('The last session cannot be deleted.');
    }
    _audit(workspace.activeSession, '已删除连接页：$deletedId');
    return <String, Object?>{'deleted': true, 'session_id': deletedId};
  });

  Future<Map<String, Object?>> activateSession(String? id) => _mutate(() async {
    final session = requireSession(id);
    workspace.activateAutomationSession(session);
    _audit(session, '切换为当前连接页');
    return sessionState(session);
  });

  Future<Map<String, Object?>> scanSerialPorts(String? id) => _mutate(() async {
    final session = requireSession(id);
    _audit(session, '扫描串口');
    await session.refreshSerialPorts();
    return <String, Object?>{
      'session_id': sessionId(session),
      'ports': session.serialPorts,
      'selected_port': session.config.serial.portName,
    };
  });

  Future<Map<String, Object?>> scanBluetooth(
    String? id, {
    int timeoutMs = 5000,
  }) => _mutate(() async {
    final session = requireSession(id);
    if (session.isConnected) {
      throw StateError('Disconnect the session before scanning Bluetooth.');
    }
    final timeout = timeoutMs.clamp(500, 30000);
    _audit(session, '扫描蓝牙 ${timeout}ms');
    if (session.isScanningBluetooth) {
      await session.stopBluetoothScan();
    }
    await session.scanBluetoothDevices();
    await Future<void>.delayed(Duration(milliseconds: timeout));
    await session.stopBluetoothScan();
    return <String, Object?>{
      'session_id': sessionId(session),
      'devices': session.bluetoothDevices
          .map(
            (device) => <String, Object?>{
              'id': device.id,
              'name': device.name,
              'rssi': device.rssi,
            },
          )
          .toList(),
    };
  });

  Future<Map<String, Object?>> scanClassicBluetooth(String? id) =>
      _mutate(() async {
        final session = requireSession(id);
        if (session.isConnected) {
          throw StateError(
            'Disconnect the session before scanning Bluetooth Classic.',
          );
        }
        _audit(session, '扫描经典蓝牙');
        final scanned = await session.scanClassicBluetoothDevices();
        if (!scanned) {
          throw _classicBluetoothFailure(session);
        }
        return <String, Object?>{
          'session_id': sessionId(session),
          'devices': session.classicBluetoothDevices
              .map(_classicBluetoothDeviceState)
              .toList(),
        };
      });

  Future<Map<String, Object?>> pairClassicBluetooth(
    String? id,
    String address,
  ) => _mutate(() async {
    final session = requireSession(id);
    final normalizedAddress = _normalizeBluetoothAddress(address);
    _audit(session, '请求配对经典蓝牙：$normalizedAddress');
    final paired = await session.pairClassicBluetoothDevice(normalizedAddress);
    if (!paired) {
      throw _classicBluetoothFailure(session);
    }
    final device = session.classicBluetoothDevices.firstWhere(
      (item) => item.address == normalizedAddress,
    );
    return <String, Object?>{
      'session_id': sessionId(session),
      'device': _classicBluetoothDeviceState(device),
    };
  });

  Future<Map<String, Object?>> unpairClassicBluetooth(
    String? id,
    String address,
  ) => _mutate(() async {
    final session = requireSession(id);
    final normalizedAddress = _normalizeBluetoothAddress(address);
    _audit(session, '请求解除经典蓝牙配对：$normalizedAddress');
    final unpaired = await session.unpairClassicBluetoothDevice(
      normalizedAddress,
    );
    if (!unpaired) {
      throw _classicBluetoothFailure(session);
    }
    return <String, Object?>{
      'session_id': sessionId(session),
      'address': normalizedAddress,
      'paired': false,
    };
  });

  Map<String, Object?> readClassicBluetoothDiagnostics(
    String? id, {
    int afterId = 0,
    int limit = 100,
  }) {
    final session = requireSession(id);
    final safeLimit = limit.clamp(1, 200);
    final diagnostics = session.classicBluetoothDiagnostics
        .where((item) => item.id > afterId)
        .take(safeLimit)
        .toList(growable: false);
    return <String, Object?>{
      'session_id': sessionId(session),
      'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
      'next_id': diagnostics.isEmpty ? afterId : diagnostics.last.id,
      'retained_count': session.classicBluetoothDiagnostics.length,
    };
  }

  Future<Map<String, Object?>> clearClassicBluetoothDiagnostics(String? id) =>
      _mutate(() async {
        final session = requireSession(id);
        session.clearClassicBluetoothDiagnostics();
        _audit(session, '清空经典蓝牙诊断记录');
        return <String, Object?>{
          'session_id': sessionId(session),
          'cleared': true,
        };
      });

  Future<Map<String, Object?>> configure(
    String? id,
    Map<String, dynamic> values,
  ) => _mutate(() async {
    final session = requireSession(id);
    if (session.isConnected) {
      throw StateError(
        'Disconnect the session before changing its configuration.',
      );
    }
    final type = _transportType(values['type']) ?? session.config.type;
    if (!session.isTypeSupported(type)) {
      throw UnsupportedError(session.unsupportedReason(type));
    }
    final current = session.config;
    final serial = current.serial.copyWith(
      portName: _string(values, 'port_name') ?? current.serial.portName,
      baudRate: _int(values, 'baud_rate') ?? current.serial.baudRate,
      dataBits: _int(values, 'data_bits') ?? current.serial.dataBits,
      stopBits: _int(values, 'stop_bits') ?? current.serial.stopBits,
      parity: _parity(values['parity']) ?? current.serial.parity,
      packetIntervalMs:
          _int(values, 'packet_interval_ms') ?? current.serial.packetIntervalMs,
      packetDelimiter:
          _string(values, 'packet_delimiter') ?? current.serial.packetDelimiter,
      forwardingEnabled:
          _bool(values, 'forwarding_enabled') ??
          current.serial.forwardingEnabled,
      forwardPortName:
          _string(values, 'forward_port_name') ??
          current.serial.forwardPortName,
      forwardBaudRate:
          _int(values, 'forward_baud_rate') ?? current.serial.forwardBaudRate,
    );
    final bluetooth = current.bluetooth.copyWith(
      deviceId: _string(values, 'device_id') ?? current.bluetooth.deviceId,
      deviceName:
          _string(values, 'device_name') ?? current.bluetooth.deviceName,
      serviceUuid:
          _string(values, 'service_uuid') ?? current.bluetooth.serviceUuid,
      characteristicUuid:
          _string(values, 'characteristic_uuid') ??
          current.bluetooth.characteristicUuid,
      writeCharacteristicUuid:
          _string(values, 'write_characteristic_uuid') ??
          current.bluetooth.writeCharacteristicUuid,
      notifyCharacteristicUuid:
          _string(values, 'notify_characteristic_uuid') ??
          current.bluetooth.notifyCharacteristicUuid,
      writeWithoutResponse:
          _bool(values, 'write_without_response') ??
          current.bluetooth.writeWithoutResponse,
    );
    final classicBluetooth = current.bluetoothClassic.copyWith(
      address:
          _string(values, 'bluetooth_address') ??
          _string(values, 'address') ??
          current.bluetoothClassic.address,
      deviceName:
          _string(values, 'classic_device_name') ??
          (type == TransportType.bluetoothClassic
              ? _string(values, 'device_name')
              : null) ??
          current.bluetoothClassic.deviceName,
      rfcommChannel:
          _int(values, 'rfcomm_channel') ??
          current.bluetoothClassic.rfcommChannel,
    );
    final next = current.copyWith(
      type: type,
      serial: serial,
      bluetooth: bluetooth,
      bluetoothClassic: classicBluetooth,
      tcpClient: current.tcpClient.copyWith(
        host: _string(values, 'host') ?? current.tcpClient.host,
        port: _int(values, 'port') ?? current.tcpClient.port,
      ),
      tcpServer: current.tcpServer.copyWith(
        bindAddress:
            _string(values, 'bind_address') ?? current.tcpServer.bindAddress,
        port: _int(values, 'port') ?? current.tcpServer.port,
      ),
      udp: current.udp.copyWith(
        bindAddress: _string(values, 'bind_address') ?? current.udp.bindAddress,
        localPort: _int(values, 'local_port') ?? current.udp.localPort,
        remoteHost: _string(values, 'remote_host') ?? current.udp.remoteHost,
        remotePort: _int(values, 'remote_port') ?? current.udp.remotePort,
      ),
    );
    _validate(next);
    session.updateConfig(next);
    _audit(session, '更新连接配置：${next.summary}');
    return sessionState(session);
  });

  Future<Map<String, Object?>> connect(String? id) => _mutate(() async {
    final session = requireSession(id);
    _audit(session, '请求连接：${session.config.summary}');
    await session.connect();
    if (!session.isConnected) {
      if (session.config.type == TransportType.bluetoothClassic) {
        throw _classicBluetoothFailure(session);
      }
      throw StateError(session.statusMessage);
    }
    return sessionState(session);
  });

  Future<Map<String, Object?>> disconnect(String? id) => _mutate(() async {
    final session = requireSession(id);
    _audit(session, '请求断开连接');
    await session.disconnect();
    return sessionState(session);
  });

  Future<Map<String, Object?>> send(
    String? id, {
    required String data,
    String format = 'ascii',
    String lineEnding = 'none',
  }) => _mutate(() async {
    final session = requireSession(id);
    if (!session.isConnected) {
      throw StateError('The session is not connected.');
    }
    final ending = _lineEnding(lineEnding);
    final bytes = switch (format.toLowerCase()) {
      'ascii' => SendRequest(
        text: data,
        format: PayloadFormat.ascii,
        lineEnding: ending,
      ).bytes,
      'hex' => SendRequest(
        text: data,
        format: PayloadFormat.hex,
        lineEnding: ending,
      ).bytes,
      'base64' => <int>[...base64Decode(data), ...ending.bytes],
      _ => throw const FormatException('format must be ascii, hex, or base64.'),
    };
    await session.sendRawBytesFrom(bytes, source: mcpAiSource);
    return <String, Object?>{
      'session_id': sessionId(session),
      'sent_bytes': bytes.length,
      'source': mcpAiSource,
    };
  });

  Map<String, Object?> readLog(
    String? id, {
    int afterSequence = 0,
    String direction = 'all',
    int maxFrames = 100,
    int maxBytes = 65536,
  }) {
    final session = requireSession(id);
    final frameLimit = maxFrames.clamp(1, 500);
    final byteLimit = maxBytes.clamp(1, 262144);
    final normalizedDirection = direction.toLowerCase();
    final matching = session.logBuffer
        .snapshot(paused: false)
        .frames
        .where((frame) => frame.sequence > afterSequence)
        .where(
          (frame) =>
              normalizedDirection == 'all' ||
              frame.direction.name == normalizedDirection,
        )
        .toList();
    final selected = <DataFrame>[];
    var selectedBytes = 0;
    for (final frame in matching) {
      if (selected.length >= frameLimit ||
          (selected.isNotEmpty &&
              selectedBytes + frame.byteLength > byteLimit)) {
        break;
      }
      selected.add(frame);
      selectedBytes += frame.byteLength;
    }
    return <String, Object?>{
      'session_id': sessionId(session),
      'frames': selected.map(_frameState).toList(),
      'next_sequence': selected.isEmpty
          ? afterSequence
          : selected.last.sequence,
      'has_more': selected.length < matching.length,
      'returned_bytes': selectedBytes,
    };
  }

  Map<String, Object?> statistics(String? id) {
    final session = requireSession(id);
    final snapshot = session.logBuffer.snapshot(paused: false);
    return <String, Object?>{
      'session_id': sessionId(session),
      'status': session.status.name,
      'session_duration_ms': session.sessionDuration.inMilliseconds,
      'rx_frames': session.rxFrameCount,
      'tx_frames': session.txFrameCount,
      'rx_bytes': session.rxByteCount,
      'tx_bytes': session.txByteCount,
      'rx_bytes_per_second': session.currentRxBytesPerSecond,
      'tx_bytes_per_second': session.currentTxBytesPerSecond,
      'average_rx_bytes_per_second': session.averageRxBytesPerSecond,
      'average_tx_bytes_per_second': session.averageTxBytesPerSecond,
      'retained_frames': snapshot.frames.length,
      'retained_bytes': session.logBuffer.retainedBytes,
      'dropped_frames': snapshot.droppedFrames,
      'dropped_bytes': snapshot.droppedBytes,
      'raw_receive_bytes': session.rawBuffer.length,
      'raw_receive_dropped_bytes': session.rawBuffer.droppedBytes,
    };
  }

  Map<String, Object?> readRawReceive(String? id, {int maxBytes = 65536}) {
    final session = requireSession(id);
    final limit = maxBytes.clamp(1, 262144);
    final retained = session.rawBuffer.snapshot();
    final bytes = retained.length <= limit
        ? retained
        : retained.sublist(retained.length - limit);
    return <String, Object?>{
      'session_id': sessionId(session),
      'returned_bytes': bytes.length,
      'retained_bytes': retained.length,
      'dropped_bytes': session.rawBuffer.droppedBytes,
      'truncated': bytes.length < retained.length,
      'hex': bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' '),
      'text': utf8.decode(bytes, allowMalformed: true),
      'base64': base64Encode(bytes),
    };
  }

  Future<Map<String, Object?>> clearLog(String? id) => _mutate(() async {
    final session = requireSession(id);
    session.clearLog();
    _audit(session, '清空日志');
    return <String, Object?>{'cleared': true, 'session_id': sessionId(session)};
  });

  Future<Map<String, Object?>> setConsoleOptions(
    String? id,
    Map<String, dynamic> values,
  ) => _mutate(() async {
    final session = requireSession(id);
    final viewMode = _consoleViewMode(values['view_mode']);
    final sendFormat = _payloadFormat(values['send_format']);
    final lineEnding = values['line_ending'] is String
        ? _lineEnding(values['line_ending'] as String)
        : null;
    if (viewMode != null) {
      workspace.setSourceViewMode(session.sourceLabel, viewMode);
      session.setViewMode(viewMode);
    }
    if (sendFormat != null) {
      session.setSendFormat(sendFormat);
    }
    if (lineEnding != null) {
      session.setLineEnding(lineEnding);
    }
    final autoScroll = _bool(values, 'auto_scroll');
    if (autoScroll != null) {
      workspace.setAutoScroll(autoScroll);
      session.setAutoScroll(autoScroll);
    }
    final pauseDisplay = _bool(values, 'pause_display');
    if (pauseDisplay != null) {
      workspace.setPauseDisplay(pauseDisplay);
      session.setPauseDisplay(pauseDisplay);
    }
    _audit(session, '更新显示与发送选项');
    return <String, Object?>{
      'options': _optionsState(
        session,
        viewMode: workspace.viewModeForSource(session.sourceLabel),
      ),
    };
  });

  Map<String, Object?> listQuickCommands(String? id) {
    final session = requireSession(id);
    return <String, Object?>{
      'session_id': sessionId(session),
      'commands': session.quickCommands.map(_quickCommandState).toList(),
    };
  }

  Future<Map<String, Object?>> createQuickCommand(
    String? id, {
    required String name,
    required String content,
    required String format,
  }) => _mutate(() async {
    final session = requireSession(id);
    if (name.trim().isEmpty || content.isEmpty) {
      throw const FormatException('name and content must not be empty.');
    }
    session.addQuickCommand(
      name: name,
      content: content,
      format: _payloadFormat(format) ?? PayloadFormat.ascii,
    );
    _audit(session, '新建快捷指令：$name');
    return listQuickCommands(id);
  });

  Future<Map<String, Object?>> updateQuickCommand(
    String? id, {
    required int commandId,
    required String name,
    required String content,
    required String format,
  }) => _mutate(() async {
    final session = requireSession(id);
    if (name.trim().isEmpty || content.isEmpty) {
      throw const FormatException('name and content must not be empty.');
    }
    if (!session.quickCommands.any((command) => command.id == commandId)) {
      throw StateError('Unknown command_id: $commandId');
    }
    session.updateQuickCommand(
      id: commandId,
      name: name,
      content: content,
      format: _payloadFormat(format) ?? PayloadFormat.ascii,
    );
    _audit(session, '更新快捷指令：$commandId');
    return listQuickCommands(id);
  });

  Future<Map<String, Object?>> deleteQuickCommand(String? id, int commandId) =>
      _mutate(() async {
        final session = requireSession(id);
        if (!session.quickCommands.any((command) => command.id == commandId)) {
          throw StateError('Unknown command_id: $commandId');
        }
        session.removeQuickCommand(commandId);
        _audit(session, '删除快捷指令：$commandId');
        return listQuickCommands(id);
      });

  Future<Map<String, Object?>> executeQuickCommand(String? id, int commandId) =>
      _mutate(() async {
        final session = requireSession(id);
        if (!session.isConnected) {
          throw StateError('The session is not connected.');
        }
        final matches = session.quickCommands.where(
          (command) => command.id == commandId,
        );
        if (matches.isEmpty) {
          throw StateError('Unknown command_id: $commandId');
        }
        final command = matches.first;
        final bytes = SendRequest(
          text: command.content,
          format: command.format,
          lineEnding: session.lineEnding,
        ).bytes;
        await session.sendRawBytesFrom(bytes, source: mcpAiSource);
        return <String, Object?>{
          'session_id': sessionId(session),
          'command': _quickCommandState(command),
          'sent_bytes': bytes.length,
          'source': mcpAiSource,
        };
      });

  Future<Map<String, Object?>> startAutoSend(
    String? id, {
    required String data,
    required String format,
    required String lineEnding,
    required int intervalMs,
  }) => _mutate(() async {
    final session = requireSession(id);
    if (!session.isConnected) {
      throw StateError('The session is not connected.');
    }
    if (intervalMs < 20 || intervalMs > 86400000) {
      throw RangeError('interval_ms must be between 20 and 86400000.');
    }
    session.startAutoSendFrom(
      text: data,
      format: _payloadFormat(format) ?? PayloadFormat.ascii,
      ending: _lineEnding(lineEnding),
      interval: Duration(milliseconds: intervalMs),
      source: mcpAiSource,
    );
    _audit(session, '启动定时发送：${intervalMs}ms');
    return <String, Object?>{
      'session_id': sessionId(session),
      'auto_sending': session.isAutoSending,
      'interval_ms': intervalMs,
    };
  });

  Future<Map<String, Object?>> stopAutoSend(String? id) => _mutate(() async {
    final session = requireSession(id);
    session.stopAutoSend();
    _audit(session, '停止定时发送');
    return <String, Object?>{
      'session_id': sessionId(session),
      'auto_sending': session.isAutoSending,
    };
  });

  Map<String, Object?> sessionState(SessionController session) =>
      <String, Object?>{
        'session_id': sessionId(session),
        'active': identical(session, workspace.activeSession),
        'source_label': session.sourceLabel,
        'status': session.status.name,
        'status_message': session.statusMessage,
        'supported_transports': <String, Object?>{
          for (final capability in session.capabilities)
            capability.type.name: <String, Object?>{
              'supported': capability.supported,
              'reason': capability.reason,
            },
        },
        'config': _configState(session.config),
        'options': _optionsState(
          session,
          viewMode: workspace.viewModeForSource(session.sourceLabel),
        ),
        'auto_sending': session.isAutoSending,
        'classic_bluetooth_diagnostics': <String, Object?>{
          'retained_count': session.classicBluetoothDiagnostics.length,
          'latest': session.classicBluetoothDiagnostics.isEmpty
              ? null
              : session.classicBluetoothDiagnostics.last.toJson(),
        },
      };

  SessionController requireSession(String? id) {
    if (id == null || id.trim().isEmpty || id == 'active') {
      return workspace.activeSession;
    }
    for (final session in workspace.sessions) {
      if (sessionId(session) == id) {
        return session;
      }
    }
    throw StateError('Unknown session_id: $id');
  }

  String sessionId(SessionController session) =>
      'session_${session.serialAliasNumber}';

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then<void>(
      (_) async {
        try {
          completer.complete(await operation());
        } on Object catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (Object _, StackTrace __) async {
        try {
          completer.complete(await operation());
        } on Object catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  void _audit(SessionController session, String action) {
    session.appendSystemMessage('MCP：$action');
  }

  LSerialMcpOperationException _classicBluetoothFailure(
    SessionController session,
  ) {
    final latest = session.classicBluetoothDiagnostics.isEmpty
        ? null
        : session.classicBluetoothDiagnostics.last;
    return LSerialMcpOperationException(
      session.statusMessage,
      <String, Object?>{
        'session_id': sessionId(session),
        if (latest != null) 'bluetooth_diagnostic': latest.toJson(),
      },
    );
  }
}

Map<String, Object?> _frameState(DataFrame frame) => <String, Object?>{
  'sequence': frame.sequence,
  'timestamp': frame.timestamp.toIso8601String(),
  'direction': frame.direction.name,
  'source': frame.direction == FrameDirection.system ? 'SYS' : frame.source,
  'length': frame.byteLength,
  'hex': frame.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' '),
  'text': utf8.decode(frame.bytes, allowMalformed: true),
  'base64': base64Encode(frame.bytes),
};

Map<String, Object?> _optionsState(
  SessionController session, {
  ConsoleViewMode? viewMode,
}) => <String, Object?>{
  'view_mode': (viewMode ?? session.viewMode).name,
  'send_format': session.sendFormat.name,
  'line_ending': session.lineEnding.name,
  'auto_scroll': session.autoScroll,
  'pause_display': session.pauseDisplay,
};

Map<String, Object?> _quickCommandState(QuickCommand command) =>
    <String, Object?>{
      'command_id': command.id,
      'name': command.name,
      'content': command.content,
      'format': command.format.name,
    };

Map<String, Object?> _configState(ConnectionConfig config) => <String, Object?>{
  'type': config.type.name,
  'serial': <String, Object?>{
    'port_name': config.serial.portName,
    'baud_rate': config.serial.baudRate,
    'data_bits': config.serial.dataBits,
    'stop_bits': config.serial.stopBits,
    'parity': config.serial.parity.name,
    'packet_interval_ms': config.serial.packetIntervalMs,
    'packet_delimiter': config.serial.packetDelimiter,
    'forwarding_enabled': config.serial.forwardingEnabled,
    'forward_port_name': config.serial.forwardPortName,
    'forward_baud_rate': config.serial.forwardBaudRate,
  },
  'bluetooth': <String, Object?>{
    'device_id': config.bluetooth.deviceId,
    'device_name': config.bluetooth.deviceName,
    'service_uuid': config.bluetooth.serviceUuid,
    'write_characteristic_uuid': config.bluetooth.writeCharacteristicUuid,
    'notify_characteristic_uuid': config.bluetooth.notifyCharacteristicUuid,
    'write_without_response': config.bluetooth.writeWithoutResponse,
  },
  'bluetooth_classic': <String, Object?>{
    'address': config.bluetoothClassic.address,
    'device_name': config.bluetoothClassic.deviceName,
    'rfcomm_channel': config.bluetoothClassic.rfcommChannel,
  },
  'tcp_client': <String, Object?>{
    'host': config.tcpClient.host,
    'port': config.tcpClient.port,
  },
  'tcp_server': <String, Object?>{
    'bind_address': config.tcpServer.bindAddress,
    'port': config.tcpServer.port,
  },
  'udp': <String, Object?>{
    'bind_address': config.udp.bindAddress,
    'local_port': config.udp.localPort,
    'remote_host': config.udp.remoteHost,
    'remote_port': config.udp.remotePort,
  },
};

TransportType? _transportType(Object? value) => switch (value) {
  'serial' => TransportType.serial,
  'bluetooth' || 'ble' => TransportType.bluetooth,
  'bluetoothClassic' ||
  'bluetooth_classic' ||
  'classic' ||
  'spp' => TransportType.bluetoothClassic,
  'tcpClient' || 'tcp_client' => TransportType.tcpClient,
  'tcpServer' || 'tcp_server' => TransportType.tcpServer,
  'udp' => TransportType.udp,
  null => null,
  _ => throw FormatException('Unknown connection type: $value'),
};

SerialParity? _parity(Object? value) => switch (value) {
  'none' => SerialParity.none,
  'odd' => SerialParity.odd,
  'even' => SerialParity.even,
  null => null,
  _ => throw const FormatException('parity must be none, odd, or even.'),
};

LineEnding _lineEnding(String value) => switch (value.toLowerCase()) {
  'none' => LineEnding.none,
  'cr' => LineEnding.cr,
  'lf' => LineEnding.lf,
  'crlf' => LineEnding.crlf,
  _ => throw const FormatException(
    'line_ending must be none, cr, lf, or crlf.',
  ),
};

PayloadFormat? _payloadFormat(Object? value) => switch (value) {
  'ascii' => PayloadFormat.ascii,
  'hex' => PayloadFormat.hex,
  null => null,
  _ => throw const FormatException('format must be ascii or hex.'),
};

ConsoleViewMode? _consoleViewMode(Object? value) => switch (value) {
  'ascii' => ConsoleViewMode.ascii,
  'hex' => ConsoleViewMode.hex,
  null => null,
  _ => throw const FormatException('view_mode must be ascii or hex.'),
};

String? _string(Map<String, dynamic> values, String key) {
  final value = values[key];
  return value is String ? value : null;
}

int? _int(Map<String, dynamic> values, String key) {
  final value = values[key];
  return value is num ? value.toInt() : null;
}

bool? _bool(Map<String, dynamic> values, String key) {
  final value = values[key];
  return value is bool ? value : null;
}

void _validate(ConnectionConfig config) {
  if (config.serial.baudRate <= 0 || config.serial.forwardBaudRate <= 0) {
    throw RangeError('Serial baud rates must be greater than zero.');
  }
  if (!const <int>{5, 6, 7, 8}.contains(config.serial.dataBits)) {
    throw RangeError('data_bits must be 5, 6, 7, or 8.');
  }
  if (!const <int>{1, 2}.contains(config.serial.stopBits)) {
    throw RangeError('stop_bits must be 1 or 2.');
  }
  if (config.serial.packetIntervalMs < 0 ||
      config.serial.packetIntervalMs > 60000) {
    throw RangeError('packet_interval_ms must be between 0 and 60000.');
  }
  final ports = <int>[
    config.tcpClient.port,
    config.tcpServer.port,
    config.udp.localPort,
    config.udp.remotePort,
  ];
  if (ports.any((port) => port < 1 || port > 65535)) {
    throw RangeError('Network ports must be between 1 and 65535.');
  }
  if (config.type == TransportType.bluetoothClassic) {
    final compact = config.bluetoothClassic.address.replaceAll(
      RegExp(r'[^0-9A-Fa-f]'),
      '',
    );
    if (compact.length != 12) {
      throw const FormatException(
        'bluetooth_address must contain 12 hexadecimal digits.',
      );
    }
  }
}

Map<String, Object?> _classicBluetoothDeviceState(
  ClassicBluetoothDeviceInfo device,
) => <String, Object?>{
  'address': device.address,
  'name': device.name,
  'paired': device.paired,
  'connected': device.connected,
  'remembered': device.remembered,
};

String _normalizeBluetoothAddress(String value) {
  final compact = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  if (compact.length != 12) {
    throw const FormatException(
      'Bluetooth address must contain 12 hexadecimal digits.',
    );
  }
  return <String>[
    for (var index = 0; index < compact.length; index += 2)
      compact.substring(index, index + 2),
  ].join(':');
}
