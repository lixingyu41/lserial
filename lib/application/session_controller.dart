import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/buffer/byte_ring_buffer.dart';
import '../core/encoding/data_format.dart';
import '../domain/connection_config.dart';
import '../domain/data_frame.dart';
import '../domain/send_request.dart';
import '../domain/transport.dart';
import '../platform/platform_capabilities.dart';
import '../protocol/frame_formatter.dart';
import '../storage/log_buffer.dart';
import '../storage/log_exporter.dart';
import '../transports/transport_registry.dart';
import 'receive_pipeline.dart';

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
  int _sequence = 0;
  bool _manualDisconnect = false;

  ConnectionConfig config = const ConnectionConfig();
  TransportStatus status = TransportStatus.disconnected;
  String statusMessage = 'Ready';
  List<TransportCapability> capabilities = const <TransportCapability>[];
  List<String> serialPorts = const <String>[];
  ConsoleViewMode viewMode = ConsoleViewMode.ascii;
  PayloadFormat sendFormat = PayloadFormat.ascii;
  LineEnding lineEnding = LineEnding.none;
  bool showTimestamp = true;
  bool showDirection = true;
  bool autoScroll = true;
  bool pauseDisplay = false;
  final List<String> commandPresets = <String>[
    'AT',
    'AT+RST',
    'ping',
    'status'
  ];
  final List<String> sendHistory = <String>[];

  bool get isConnected => status == TransportStatus.connected;

  bool get isAutoSending => _autoSendTimer != null;

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
        config = config.copyWith(
          serial: config.serial.copyWith(portName: serialPorts.first),
        );
      }
    } on Object catch (error) {
      serialPorts = const <String>[];
      _setStatusMessage('Serial scan failed: $error');
    }
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

  void setTransportType(TransportType type) {
    if (!isTypeSupported(type)) {
      _setStatusMessage('${type.label} disabled: ${unsupportedReason(type)}');
      return;
    }
    config = config.copyWith(type: type);
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
          _appendSystem('Receive error: $error');
        },
        onDone: () {
          if (!_manualDisconnect) {
            status = TransportStatus.disconnected;
            statusMessage = 'Connection closed';
            _appendSystem('Connection closed by peer');
            notifyListeners();
          }
        },
        cancelOnError: false,
      );
      status = TransportStatus.connected;
      statusMessage = 'Connected ${session.label}';
      _appendSystem(statusMessage);
      notifyListeners();
    } on Object catch (error) {
      status = TransportStatus.error;
      statusMessage = 'Connect failed: $error';
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
    _appendSystem(statusMessage);
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    final request = SendRequest(
      text: text,
      format: sendFormat,
      lineEnding: lineEnding,
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
      _rememberHistory(text);
    } on Object catch (error) {
      _appendSystem('Send failed: $error');
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
    logBuffer.addAll(frames);
    if (!pauseDisplay) {
      _publishSnapshot();
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

  void _rememberHistory(String text) {
    if (text.trim().isEmpty) {
      return;
    }
    sendHistory.remove(text);
    sendHistory.insert(0, text);
    if (sendHistory.length > 20) {
      sendHistory.removeRange(20, sendHistory.length);
    }
    notifyListeners();
  }

  void _setStatusMessage(String message) {
    statusMessage = message;
    notifyListeners();
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
    _incomingSubscription?.cancel();
    _session?.disconnect();
    _pipeline.dispose();
    displaySnapshot.dispose();
    super.dispose();
  }
}
