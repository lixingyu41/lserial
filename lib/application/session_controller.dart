import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/buffer/byte_ring_buffer.dart';
import '../core/encoding/data_format.dart';
import '../domain/bluetooth_device_info.dart';
import '../domain/connection_config.dart';
import '../domain/data_frame.dart';
import '../domain/quick_command.dart';
import '../domain/send_history_entry.dart';
import '../domain/send_request.dart';
import '../domain/transport.dart';
import '../platform/platform_capabilities.dart';
import '../protocol/frame_formatter.dart';
import '../storage/log_buffer.dart';
import '../storage/log_exporter.dart';
import '../transports/adapters/serial_port_options.dart';
import '../transports/transport_registry.dart';
import 'receive_pipeline.dart';

enum SessionStat {
  rxCount,
  txCount,
  rxCurrentRate,
  txCurrentRate,
  rxRate,
  txRate,
  sessionDuration,
  displayCache,
  droppedData,
  rawCache,
}

enum SendShortcutMode {
  enter,
  ctrlEnter,
}

extension SendShortcutModeLabel on SendShortcutMode {
  String get label => switch (this) {
        SendShortcutMode.enter => '回车发送',
        SendShortcutMode.ctrlEnter => 'Ctrl+回车发送',
      };
}

extension SessionStatLabel on SessionStat {
  String get label => switch (this) {
        SessionStat.rxCount => '接收',
        SessionStat.txCount => '发送',
        SessionStat.rxCurrentRate => '收速',
        SessionStat.txCurrentRate => '发速',
        SessionStat.rxRate => '均收',
        SessionStat.txRate => '均发',
        SessionStat.sessionDuration => '会话时长',
        SessionStat.displayCache => '显示缓存',
        SessionStat.droppedData => '丢弃',
        SessionStat.rawCache => '原始缓存',
      };
}

class SessionController extends ChangeNotifier {
  SessionController({
    TransportRegistry? registry,
    int maxDisplayFrames = 10000,
    int maxCacheBytes = 16 * 1024 * 1024,
  })  : registry = registry ?? const TransportRegistry(),
        rawBuffer = ByteRingBuffer(maxCacheBytes),
        logBuffer =
            LogBuffer(maxFrames: maxDisplayFrames, maxBytes: maxCacheBytes) {
    _pipeline = ReceivePipeline(
      rawBuffer: rawBuffer,
      onBatch: _commitFrames,
      nextSequence: _nextSequence,
    );
    displaySnapshot.value = logBuffer.snapshot(paused: false);
  }

  final TransportRegistry registry;
  final ByteRingBuffer rawBuffer;
  final LogBuffer logBuffer;
  final FrameFormatter formatter = const FrameFormatter();
  final ValueNotifier<LogSnapshot> displaySnapshot =
      ValueNotifier<LogSnapshot>(LogSnapshot.empty());

  late final ReceivePipeline _pipeline;
  StreamSubscription<List<int>>? _incomingSubscription;
  TransportSession? _session;
  Timer? _autoSendTimer;
  Timer? _statsTimer;
  int _sequence = 0;
  int _nextCommandId = 4;
  bool _manualDisconnect = false;
  DateTime? _rxStartedAt;
  DateTime? _txStartedAt;
  DateTime? _sessionStartedAt;
  DateTime? _lastRateAt;
  int _lastRateRxBytes = 0;
  int _lastRateTxBytes = 0;

  ConnectionConfig config = const ConnectionConfig();
  TransportStatus status = TransportStatus.disconnected;
  String statusMessage = 'Ready';
  List<TransportCapability> capabilities = const <TransportCapability>[];
  List<String> serialPorts = const <String>[];
  List<BluetoothDeviceInfo> bluetoothDevices = const <BluetoothDeviceInfo>[];
  ConsoleViewMode viewMode = ConsoleViewMode.ascii;
  PayloadFormat sendFormat = PayloadFormat.ascii;
  LineEnding lineEnding = LineEnding.none;
  bool showTimestamp = true;
  bool showDirection = true;
  bool autoScroll = true;
  bool pauseDisplay = false;
  bool isScanningBluetooth = false;
  SendShortcutMode sendShortcutMode = SendShortcutMode.enter;
  double logFontSize = 12;
  int rxFrameCount = 0;
  int txFrameCount = 0;
  int rxByteCount = 0;
  int txByteCount = 0;
  double currentRxBytesPerSecond = 0;
  double currentTxBytesPerSecond = 0;
  final Set<SessionStat> visibleStats = <SessionStat>{
    SessionStat.rxCount,
    SessionStat.txCount,
    SessionStat.rxCurrentRate,
    SessionStat.txCurrentRate,
    SessionStat.rxRate,
    SessionStat.txRate,
    SessionStat.sessionDuration,
    SessionStat.displayCache,
    SessionStat.droppedData,
  };
  final List<QuickCommand> quickCommands = <QuickCommand>[
    const QuickCommand(
      id: 1,
      name: 'AT',
      content: 'AT',
      format: PayloadFormat.ascii,
    ),
    const QuickCommand(
      id: 2,
      name: 'Reset',
      content: 'AT+RST',
      format: PayloadFormat.ascii,
    ),
    const QuickCommand(
      id: 3,
      name: 'Ping',
      content: 'ping',
      format: PayloadFormat.ascii,
    ),
  ];
  final List<SendHistoryEntry> sendHistory = <SendHistoryEntry>[];

  bool get isConnected => status == TransportStatus.connected;

  bool get isAutoSending => _autoSendTimer != null;

  Duration get sessionDuration {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(startedAt);
  }

  String get windowTitle => switch (config.type) {
        TransportType.serial =>
          'LSerial-${_titleValue(config.serial.portName, 'Serial')}-${config.serial.baudRate}',
        TransportType.bluetooth =>
          'LSerial-BLE-${_titleValue(config.bluetooth.deviceName.isEmpty ? config.bluetooth.deviceId : config.bluetooth.deviceName, 'Device')}',
        TransportType.tcpClient =>
          'LSerial-TCP-${_titleValue(config.tcpClient.host, 'Client')}',
        TransportType.tcpServer =>
          'LSerial-TCP-Server-${_titleValue(config.tcpServer.bindAddress, 'Server')}:${config.tcpServer.port}',
        TransportType.udp =>
          'LSerial-UDP-${_titleValue(config.udp.remoteHost, 'Remote')}:${config.udp.remotePort}',
      };

  double get averageRxBytesPerSecond => _averageBytesPerSecond(
        rxByteCount.toDouble(),
        startedAt: _rxStartedAt,
      );

  double get averageTxBytesPerSecond => _averageBytesPerSecond(
        txByteCount.toDouble(),
        startedAt: _txStartedAt,
      );

  ConsoleFormatOptions get formatOptions => ConsoleFormatOptions(
        viewMode: viewMode,
        showTimestamp: showTimestamp,
        showDirection: showDirection,
      );

  Future<void> initialize() async {
    capabilities = await loadPlatformCapabilities();
    await refreshSerialPorts();
    notifyListeners();
  }

  Future<void> refreshSerialPorts() async {
    try {
      serialPorts = await registry.serialPorts();
      if (config.serial.portName.isEmpty && serialPorts.isNotEmpty) {
        final selectablePorts =
            serialPorts.where((port) => !isSerialPickerOption(port)).toList();
        if (selectablePorts.isEmpty) {
          notifyListeners();
          return;
        }
        config = config.copyWith(
          serial: config.serial.copyWith(portName: selectablePorts.first),
        );
      }
    } on Object catch (error) {
      serialPorts = const <String>[];
      _setStatusMessage('Serial scan failed: $error');
    }
  }

  Future<void> scanBluetoothDevices() async {
    if (isScanningBluetooth || isConnected) {
      return;
    }
    isScanningBluetooth = true;
    _setStatusMessage('Scanning BLE devices...');
    try {
      bluetoothDevices = await registry.bluetoothDevices(
        serviceUuid: config.bluetooth.serviceUuid.trim().isEmpty
            ? null
            : config.bluetooth.serviceUuid.trim(),
      );
      if (bluetoothDevices.isEmpty) {
        _setStatusMessage('No BLE devices found.');
      } else {
        final currentDevice = config.bluetooth.deviceId.trim();
        if (currentDevice.isEmpty && bluetoothDevices.length == 1) {
          selectBluetoothDevice(bluetoothDevices.first.id);
        }
        _setStatusMessage('Found ${bluetoothDevices.length} BLE device(s).');
      }
    } on Object catch (error) {
      bluetoothDevices = const <BluetoothDeviceInfo>[];
      _setStatusMessage('BLE scan failed: $error');
    } finally {
      isScanningBluetooth = false;
      notifyListeners();
    }
  }

  void selectBluetoothDevice(String deviceId) {
    final matched = bluetoothDevices.where((device) => device.id == deviceId);
    final device = matched.isEmpty ? null : matched.first;
    config = config.copyWith(
      bluetooth: config.bluetooth.copyWith(
        deviceId: deviceId,
        deviceName: device?.name ?? config.bluetooth.deviceName,
      ),
    );
    notifyListeners();
  }

  bool isTypeSupported(TransportType type) {
    final capability = _capabilityFor(type);
    return capability?.supported ?? false;
  }

  String unsupportedReason(TransportType type) {
    return _capabilityFor(type)?.reason ?? 'Unsupported platform.';
  }

  void updateConfig(ConnectionConfig next) {
    config = next;
    notifyListeners();
  }

  Future<void> selectSerialPort(String value) async {
    if (isSerialPickerOption(value)) {
      try {
        final selected = await registry.requestSerialPort();
        await refreshSerialPorts();
        if (selected != null) {
          config = config.copyWith(
            serial: config.serial.copyWith(portName: selected),
          );
          _setStatusMessage('已选择 Web Serial 串口');
        }
      } on Object catch (error) {
        _setStatusMessage('选择串口失败: $error');
      }
      return;
    }

    config = config.copyWith(
      serial: config.serial.copyWith(portName: value),
    );
    notifyListeners();
  }

  void setTransportType(TransportType type) {
    if (!isTypeSupported(type)) {
      _setStatusMessage('${type.label} disabled: ${unsupportedReason(type)}');
      return;
    }
    config = config.copyWith(type: type);
    notifyListeners();
  }

  bool isStatVisible(SessionStat stat) => visibleStats.contains(stat);

  void setStatVisible(SessionStat stat, bool visible) {
    if (visible) {
      visibleStats.add(stat);
    } else {
      visibleStats.remove(stat);
    }
    notifyListeners();
  }

  void setLogFontSize(double value) {
    final next = value.clamp(10, 22).toDouble();
    if (next == logFontSize) {
      return;
    }
    logFontSize = next;
    notifyListeners();
  }

  void increaseLogFontSize() => setLogFontSize(logFontSize + 1);

  void decreaseLogFontSize() => setLogFontSize(logFontSize - 1);

  void setSendShortcutMode(SendShortcutMode mode) {
    sendShortcutMode = mode;
    notifyListeners();
  }

  void toggleSendShortcutMode() {
    sendShortcutMode = sendShortcutMode == SendShortcutMode.enter
        ? SendShortcutMode.ctrlEnter
        : SendShortcutMode.enter;
    notifyListeners();
  }

  void addQuickCommand({
    required String name,
    required String content,
    required PayloadFormat format,
  }) {
    final safeName = name.trim();
    if (safeName.isEmpty || content.isEmpty) {
      _setStatusMessage('快捷指令名称和内容不能为空');
      return;
    }
    quickCommands.add(
      QuickCommand(
        id: _nextCommandId++,
        name: safeName,
        content: content,
        format: format,
      ),
    );
    notifyListeners();
  }

  void updateQuickCommand({
    required int id,
    required String name,
    required String content,
    required PayloadFormat format,
  }) {
    final safeName = name.trim();
    if (safeName.isEmpty || content.isEmpty) {
      _setStatusMessage('快捷指令名称和内容不能为空');
      return;
    }
    final index = quickCommands.indexWhere((command) => command.id == id);
    if (index < 0) {
      return;
    }
    quickCommands[index] = quickCommands[index].copyWith(
      name: safeName,
      content: content,
      format: format,
    );
    notifyListeners();
  }

  void removeQuickCommand(int id) {
    quickCommands.removeWhere((command) => command.id == id);
    notifyListeners();
  }

  Future<void> connect() async {
    if (isConnected || status == TransportStatus.connecting) {
      return;
    }
    if (!isTypeSupported(config.type)) {
      _setStatusMessage(
          '${config.type.label} disabled: ${unsupportedReason(config.type)}');
      return;
    }

    status = TransportStatus.connecting;
    statusMessage = 'Connecting ${config.summary}';
    notifyListeners();

    try {
      final session = await registry.create(config);
      await session.connect();
      _session = session;
      _manualDisconnect = false;
      _incomingSubscription = session.incoming.listen(
        (bytes) => _pipeline.addBytes(bytes, source: session.label),
        onError: (Object error, StackTrace stackTrace) {
          _appendSystem('Receive error: ${_formatError(error)}');
        },
        onDone: () {
          if (!_manualDisconnect) {
            status = TransportStatus.error;
            statusMessage = '异常断开';
            _stopStatsTicker();
            _appendSystem('Connection closed unexpectedly');
            notifyListeners();
          }
        },
        cancelOnError: false,
      );
      status = TransportStatus.connected;
      statusMessage = 'Connected ${session.label}';
      _sessionStartedAt = DateTime.now();
      _startStatsTicker();
      _appendSystem(statusMessage);
      notifyListeners();
    } on Object catch (error) {
      status = TransportStatus.error;
      statusMessage = 'Connect failed: ${_formatError(error)}';
      _appendSystem(statusMessage);
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (status == TransportStatus.disconnected ||
        status == TransportStatus.disconnecting) {
      return;
    }
    _manualDisconnect = true;
    status = TransportStatus.disconnecting;
    statusMessage = 'Disconnecting';
    stopAutoSend();
    notifyListeners();

    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _session?.disconnect();
    _session = null;
    _pipeline.flush();

    status = TransportStatus.disconnected;
    statusMessage = 'Disconnected';
    _stopStatsTicker();
    _appendSystem(statusMessage);
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    await _sendPayload(
      text: text,
      format: sendFormat,
      ending: lineEnding,
      rememberHistory: true,
    );
  }

  Future<void> sendQuickCommand(QuickCommand command) async {
    await _sendPayload(
      text: command.content,
      format: command.format,
      ending: lineEnding,
      rememberHistory: true,
    );
  }

  Future<void> sendHistoryEntry(SendHistoryEntry entry) async {
    await _sendPayload(
      text: entry.text,
      format: entry.format,
      ending: lineEnding,
      rememberHistory: true,
    );
  }

  Future<void> _sendPayload({
    required String text,
    required PayloadFormat format,
    required LineEnding ending,
    required bool rememberHistory,
  }) async {
    final request = SendRequest(
      text: text,
      format: format,
      lineEnding: ending,
    );
    if (request.bytes.isEmpty) {
      return;
    }
    final session = _session;
    if (session == null || !session.isConnected) {
      _appendSystem('Send skipped: no active connection');
      return;
    }

    try {
      await session.send(request.bytes);
      _commitFrames(<DataFrame>[
        DataFrame(
          sequence: _nextSequence(),
          timestamp: DateTime.now(),
          direction: FrameDirection.tx,
          bytes: request.bytes,
          source: session.label,
        ),
      ]);
      if (rememberHistory) {
        _rememberHistory(text, format);
      }
    } on Object catch (error) {
      _appendSystem('Send failed: ${_formatError(error)}');
    }
  }

  void startAutoSend(String text, Duration interval) {
    stopAutoSend();
    final safeInterval = interval < const Duration(milliseconds: 20)
        ? const Duration(milliseconds: 20)
        : interval;
    _autoSendTimer =
        Timer.periodic(safeInterval, (_) => unawaited(sendText(text)));
    _setStatusMessage('Auto send every ${safeInterval.inMilliseconds} ms');
  }

  void stopAutoSend() {
    _autoSendTimer?.cancel();
    _autoSendTimer = null;
    notifyListeners();
  }

  void setViewMode(ConsoleViewMode mode) {
    viewMode = mode;
    _publishSnapshot();
    notifyListeners();
  }

  void setSendFormat(PayloadFormat format) {
    sendFormat = format;
    notifyListeners();
  }

  void setLineEnding(LineEnding ending) {
    lineEnding = ending;
    notifyListeners();
  }

  void setTimestampVisible(bool value) {
    showTimestamp = value;
    _publishSnapshot();
    notifyListeners();
  }

  void setDirectionVisible(bool value) {
    showDirection = value;
    _publishSnapshot();
    notifyListeners();
  }

  void setAutoScroll(bool value) {
    autoScroll = value;
    notifyListeners();
  }

  void setPauseDisplay(bool value) {
    pauseDisplay = value;
    if (!pauseDisplay) {
      _publishSnapshot();
    } else {
      displaySnapshot.value = logBuffer.snapshot(paused: true);
    }
    notifyListeners();
  }

  void clearLog() {
    logBuffer.clear();
    rawBuffer.clear();
    _resetStats();
    _publishSnapshot();
    notifyListeners();
  }

  Future<void> exportLog() async {
    try {
      final text = logBuffer.exportText(formatter, formatOptions);
      final result = await exportLogText(text);
      _setStatusMessage(result);
    } on Object catch (error) {
      _setStatusMessage('Export failed: $error');
    }
  }

  void _commitFrames(List<DataFrame> frames) {
    var trafficChanged = false;
    for (final frame in frames) {
      switch (frame.direction) {
        case FrameDirection.rx:
          _rxStartedAt ??= frame.timestamp;
          rxFrameCount++;
          rxByteCount += frame.byteLength;
          trafficChanged = true;
        case FrameDirection.tx:
          _txStartedAt ??= frame.timestamp;
          txFrameCount++;
          txByteCount += frame.byteLength;
          trafficChanged = true;
        case FrameDirection.system:
          break;
      }
    }
    logBuffer.addAll(frames);
    if (!pauseDisplay) {
      _publishSnapshot();
    }
    if (trafficChanged) {
      _updateCurrentRates();
      notifyListeners();
    }
  }

  void _appendSystem(String text) {
    _commitFrames(<DataFrame>[
      DataFrame.text(
        sequence: _nextSequence(),
        direction: FrameDirection.system,
        text: text,
        source: 'system',
      ),
    ]);
  }

  void _publishSnapshot() {
    displaySnapshot.value = logBuffer.snapshot(paused: pauseDisplay);
  }

  int _nextSequence() => ++_sequence;

  void _rememberHistory(String text, PayloadFormat format) {
    if (text.trim().isEmpty) {
      return;
    }
    sendHistory.removeWhere(
      (item) => item.text == text && item.format == format,
    );
    sendHistory.insert(
      0,
      SendHistoryEntry(
        text: text,
        format: format,
        timestamp: DateTime.now(),
      ),
    );
    if (sendHistory.length > 20) {
      sendHistory.removeRange(20, sendHistory.length);
    }
    notifyListeners();
  }

  void _resetStats() {
    _rxStartedAt = null;
    _txStartedAt = null;
    _sessionStartedAt = isConnected ? DateTime.now() : null;
    _lastRateAt = null;
    _lastRateRxBytes = 0;
    _lastRateTxBytes = 0;
    rxFrameCount = 0;
    txFrameCount = 0;
    rxByteCount = 0;
    txByteCount = 0;
    currentRxBytesPerSecond = 0;
    currentTxBytesPerSecond = 0;
  }

  void _updateCurrentRates({bool force = false}) {
    final now = DateTime.now();
    final lastRateAt = _lastRateAt;
    if (lastRateAt == null) {
      _lastRateAt = now;
      _lastRateRxBytes = rxByteCount;
      _lastRateTxBytes = txByteCount;
      return;
    }
    final elapsedMs = now.difference(lastRateAt).inMilliseconds;
    if (!force && elapsedMs < 250) {
      return;
    }
    currentRxBytesPerSecond =
        (rxByteCount - _lastRateRxBytes) * 1000 / elapsedMs;
    currentTxBytesPerSecond =
        (txByteCount - _lastRateTxBytes) * 1000 / elapsedMs;
    _lastRateAt = now;
    _lastRateRxBytes = rxByteCount;
    _lastRateTxBytes = txByteCount;
  }

  void _startStatsTicker() {
    _statsTimer?.cancel();
    _lastRateAt = DateTime.now();
    _lastRateRxBytes = rxByteCount;
    _lastRateTxBytes = txByteCount;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCurrentRates(force: true);
      notifyListeners();
    });
  }

  void _stopStatsTicker() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastRateAt = null;
    _lastRateRxBytes = rxByteCount;
    _lastRateTxBytes = txByteCount;
    currentRxBytesPerSecond = 0;
    currentTxBytesPerSecond = 0;
  }

  double _averageBytesPerSecond(double bytes, {required DateTime? startedAt}) {
    if (startedAt == null) {
      return 0;
    }
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsedMs <= 0) {
      return 0;
    }
    return bytes * 1000 / elapsedMs;
  }

  String _titleValue(String value, String fallback) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || isSerialPickerOption(trimmed)) {
      return fallback;
    }
    return trimmed.replaceAll(RegExp(r'\s+'), '_');
  }

  void _setStatusMessage(String message) {
    statusMessage = message;
    notifyListeners();
  }

  String _formatError(Object error) {
    if (error is SocketException) {
      return _formatSocketException(error);
    }
    return error.toString();
  }

  String _formatSocketException(SocketException error) {
    final code = error.osError?.errorCode;
    final address = error.address?.address;
    final port = error.port;
    final parts = <String>['SocketException'];
    if (code != null) {
      parts.add('errno=$code');
      final meaning = _windowsSocketErrorMeaning(code);
      if (meaning != null) {
        parts.add(meaning);
      }
    }
    if (address != null && address.isNotEmpty) {
      parts.add('address=$address');
    }
    if (port != null) {
      parts.add('port=$port');
    }
    return parts.join(', ');
  }

  String? _windowsSocketErrorMeaning(int code) {
    return switch (code) {
      10048 => 'address already in use',
      10049 => 'cannot assign requested address',
      10054 => 'connection reset by peer',
      10060 => 'connection timed out',
      10061 => 'connection refused',
      10065 => 'no route to host',
      1225 => 'connection refused',
      _ => null,
    };
  }

  TransportCapability? _capabilityFor(TransportType type) {
    for (final capability in capabilities) {
      if (capability.type == type) {
        return capability;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _autoSendTimer?.cancel();
    _statsTimer?.cancel();
    _incomingSubscription?.cancel();
    _session?.disconnect();
    _pipeline.dispose();
    displaySnapshot.dispose();
    super.dispose();
  }
}
