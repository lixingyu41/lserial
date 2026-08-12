import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/localization.dart';
import '../core/buffer/byte_ring_buffer.dart';
import '../core/encoding/data_format.dart';
import '../domain/bluetooth_device_info.dart';
import '../domain/classic_bluetooth_diagnostic.dart';
import '../domain/classic_bluetooth_device_info.dart';
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
import '../storage/workspace_preferences.dart';
import '../transports/adapters/serial_port_options.dart';
import '../transports/transport_registry.dart';
import 'receive_pipeline.dart';
import 'session_options.dart';

export 'session_options.dart';

const List<QuickCommand> _defaultQuickCommands = <QuickCommand>[
  QuickCommand(id: 1, name: 'AT', content: 'AT', format: PayloadFormat.ascii),
  QuickCommand(
    id: 2,
    name: 'Reset',
    content: 'AT+RST',
    format: PayloadFormat.ascii,
  ),
  QuickCommand(
    id: 3,
    name: 'Ping',
    content: 'ping',
    format: PayloadFormat.ascii,
  ),
];

class SessionController extends ChangeNotifier {
  SessionController({
    TransportRegistry? registry,
    int maxDisplayFrames = 10000,
    int maxCacheBytes = 16 * 1024 * 1024,
    this.serialAliasNumber = 1,
    this.language = AppLanguage.zh,
    Duration serialReconnectInterval = const Duration(seconds: 1),
    Future<List<QuickCommand>?> Function()? loadQuickCommands,
    Future<void> Function(List<QuickCommand> commands)? saveQuickCommands,
  }) : registry = registry ?? const TransportRegistry(),
       _serialReconnectInterval = serialReconnectInterval,
       _loadQuickCommands = loadQuickCommands ?? readQuickCommands,
       _saveQuickCommands = saveQuickCommands ?? writeQuickCommands,
       rawBuffer = ByteRingBuffer(maxCacheBytes),
       logBuffer = LogBuffer(
         maxFrames: maxDisplayFrames,
         maxBytes: maxCacheBytes,
       ) {
    statusMessage = strings.ready;
    _pipeline = ReceivePipeline(
      rawBuffer: rawBuffer,
      onBatch: _commitFrames,
      nextSequence: _nextSequence,
      onPacketPreview: _updatePacketPreview,
    );
    _publishSnapshot();
  }

  final TransportRegistry registry;
  final Future<List<QuickCommand>?> Function() _loadQuickCommands;
  final Future<void> Function(List<QuickCommand> commands) _saveQuickCommands;
  final Duration _serialReconnectInterval;
  final ByteRingBuffer rawBuffer;
  final LogBuffer logBuffer;
  final FrameFormatter formatter = const FrameFormatter();
  final int serialAliasNumber;
  AppLanguage language;
  final ValueNotifier<LogSnapshot> displaySnapshot = ValueNotifier<LogSnapshot>(
    LogSnapshot.empty(),
  );
  final ChangeNotifier _statsNotifier = ChangeNotifier();

  late final ReceivePipeline _pipeline;
  StreamSubscription<List<int>>? _incomingSubscription;
  StreamSubscription<List<int>>? _forwardIncomingSubscription;
  StreamSubscription<List<BluetoothDeviceInfo>>? _bluetoothScanSubscription;
  TransportSession? _session;
  TransportSession? _forwardSession;
  Future<void> _primaryWriteTail = Future<void>.value();
  Future<void> _forwardWriteTail = Future<void>.value();
  Timer? _autoSendTimer;
  Timer? _statsTimer;
  Timer? _serialReconnectTimer;
  bool _autoSendInFlight = false;
  bool _connectInFlight = false;
  bool _serialReconnectRequested = false;
  bool _disposed = false;
  bool _shutdownRequested = false;
  Future<void>? _shutdownFuture;
  int _sequence = 0;
  int _displayRevision = 0;
  DataFrame? _packetPreview;
  int _nextCommandId = 4;
  bool _manualDisconnect = false;
  DateTime? _rxStartedAt;
  DateTime? _txStartedAt;
  DateTime? _sessionStartedAt;
  DateTime? _lastRateAt;
  int _lastRateRxBytes = 0;
  int _lastRateTxBytes = 0;
  int _nextClassicBluetoothDiagnosticId = 1;

  ConnectionConfig config = const ConnectionConfig();
  TransportStatus status = TransportStatus.disconnected;
  String statusMessage = AppStrings.zh.ready;
  List<TransportCapability> capabilities = const <TransportCapability>[];
  List<String> serialPorts = const <String>[];
  List<BluetoothDeviceInfo> bluetoothDevices = const <BluetoothDeviceInfo>[];
  List<ClassicBluetoothDeviceInfo> classicBluetoothDevices =
      const <ClassicBluetoothDeviceInfo>[];
  final List<ClassicBluetoothDiagnostic> classicBluetoothDiagnostics =
      <ClassicBluetoothDiagnostic>[];
  ConsoleViewMode viewMode = ConsoleViewMode.ascii;
  PayloadFormat sendFormat = PayloadFormat.ascii;
  LineEnding lineEnding = LineEnding.lf;
  bool showTimestamp = true;
  bool showDirection = true;
  bool showLineEndingSymbols = false;
  bool autoScroll = true;
  bool pauseDisplay = false;
  bool isScanningBluetooth = false;
  bool isScanningClassicBluetooth = false;
  String? classicBluetoothBusyAddress;
  SendShortcutMode sendShortcutMode = SendShortcutMode.enter;
  String sendDraftText = '';
  String autoSendIntervalText = '1000';
  double logFontSize = 12;
  int rxFrameCount = 0;
  int txFrameCount = 0;
  int rxByteCount = 0;
  int txByteCount = 0;
  double currentRxBytesPerSecond = 0;
  double currentTxBytesPerSecond = 0;
  final Set<SessionStat> visibleStats = Set<SessionStat>.of(
    sessionStatDisplayOrder,
  );
  final List<QuickCommand> quickCommands = List<QuickCommand>.of(
    _defaultQuickCommands,
  );
  final List<SendHistoryEntry> sendHistory = <SendHistoryEntry>[];

  AppStrings get strings => AppStrings.of(language);

  bool get isConnected => status == TransportStatus.connected;

  bool get isAutoSending => _autoSendTimer != null;

  Listenable get statsListenable => _statsNotifier;

  String get sourceLabel => switch (config.type) {
    TransportType.serial =>
      config.serial.forwardingEnabled
          ? '${serialDisplayName}_${_titleValue(config.serial.forwardPortName, 'Serial')}'
          : serialDisplayName,
    TransportType.bluetooth => _titleValue(
      config.bluetooth.deviceName.isEmpty
          ? config.bluetooth.deviceId
          : config.bluetooth.deviceName,
      'BLE',
    ),
    TransportType.bluetoothClassic =>
      'BT ${_titleValue(config.bluetoothClassic.deviceName.isEmpty ? config.bluetoothClassic.address : config.bluetoothClassic.deviceName, 'Classic')}',
    TransportType.tcpClient =>
      'TCP ${_titleValue(config.tcpClient.host, 'Client')}:${config.tcpClient.port}',
    TransportType.tcpServer =>
      'TCP Server ${_titleValue(config.tcpServer.bindAddress, 'Server')}:${config.tcpServer.port}',
    TransportType.udp =>
      'UDP ${_titleValue(config.udp.bindAddress, 'Local')}:${config.udp.localPort}',
  };

  Duration get sessionDuration {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(startedAt);
  }

  String get windowTitle => switch (config.type) {
    TransportType.serial =>
      config.serial.forwardingEnabled
          ? 'LSerial-$serialDisplayName-${_titleValue(config.serial.forwardPortName, 'Serial')}-Bridge'
          : 'LSerial-$serialDisplayName-${config.serial.baudRate}',
    TransportType.bluetooth =>
      'LSerial-BLE-${_titleValue(config.bluetooth.deviceName.isEmpty ? config.bluetooth.deviceId : config.bluetooth.deviceName, 'Device')}',
    TransportType.bluetoothClassic =>
      'LSerial-BT-${_titleValue(config.bluetoothClassic.deviceName.isEmpty ? config.bluetoothClassic.address : config.bluetoothClassic.deviceName, 'Device')}',
    TransportType.tcpClient =>
      'LSerial-TCP-${_titleValue(config.tcpClient.host, 'Client')}',
    TransportType.tcpServer =>
      'LSerial-TCP-Server-${_titleValue(config.tcpServer.bindAddress, 'Server')}:${config.tcpServer.port}',
    TransportType.udp =>
      'LSerial-UDP-${_titleValue(config.udp.remoteHost, 'Remote')}:${config.udp.remotePort}',
  };

  String get serialDisplayName {
    if (isGenericSerialPortName(config.serial.portName)) {
      return 'Serial$serialAliasNumber';
    }
    return _titleValue(config.serial.portName, 'Serial$serialAliasNumber');
  }

  double get averageRxBytesPerSecond =>
      _averageBytesPerSecond(rxByteCount.toDouble(), startedAt: _rxStartedAt);

  double get averageTxBytesPerSecond =>
      _averageBytesPerSecond(txByteCount.toDouble(), startedAt: _txStartedAt);

  ConsoleFormatOptions get formatOptions => ConsoleFormatOptions(
    viewMode: viewMode,
    showTimestamp: showTimestamp,
    showDirection: showDirection,
    showLineEndingSymbols: showLineEndingSymbols,
  );

  void setLanguage(AppLanguage next) {
    if (language == next) {
      return;
    }
    final previousStrings = strings;
    final previousMessage = statusMessage;
    language = next;
    statusMessage = switch (status) {
      TransportStatus.connected => strings.connectedTo(sourceLabel),
      TransportStatus.connecting => strings.connectingTo(
        strings.connectionSummary(config, serialDisplayName),
      ),
      TransportStatus.disconnecting => strings.disconnectingStatus,
      TransportStatus.disconnected
          when previousMessage == previousStrings.ready =>
        strings.ready,
      TransportStatus.disconnected
          when previousMessage == previousStrings.disconnected =>
        strings.disconnected,
      TransportStatus.error
          when previousMessage == previousStrings.unexpectedDisconnect =>
        strings.unexpectedDisconnect,
      _ => previousMessage,
    };
    notifyListeners();
  }

  Future<void> initialize() async {
    await _loadSavedQuickCommands();
    capabilities = await loadPlatformCapabilities();
    await refreshSerialPorts();
    notifyListeners();
  }

  Future<void> refreshSerialPorts() async {
    try {
      serialPorts = await registry.serialPorts();
      if (config.serial.portName.isEmpty && serialPorts.isNotEmpty) {
        final selectablePorts = serialPorts
            .where((port) => !isSerialPickerOption(port))
            .toList();
        if (selectablePorts.isEmpty) {
          notifyListeners();
          return;
        }
        config = config.copyWith(
          serial: config.serial.copyWith(portName: selectablePorts.first),
        );
      }
      notifyListeners();
    } on Object catch (error) {
      serialPorts = const <String>[];
      _setStatusMessage(strings.serialScanFailed(error));
    }
  }

  Future<void> scanBluetoothDevices() async {
    if (isScanningBluetooth) {
      await stopBluetoothScan();
      return;
    }
    if (isConnected) {
      return;
    }
    isScanningBluetooth = true;
    _setStatusMessage(
      kIsWeb ? strings.openingWebBluetoothPicker : strings.scanningBleDevices,
    );
    try {
      await _bluetoothScanSubscription?.cancel();
      _bluetoothScanSubscription = registry
          .bluetoothDeviceStream(
            serviceUuid: config.bluetooth.serviceUuid.trim().isEmpty
                ? null
                : config.bluetooth.serviceUuid.trim(),
          )
          .listen(
            (devices) {
              bluetoothDevices = devices;
              _setStatusMessage(
                kIsWeb
                    ? strings.webBluetoothDeviceSelected
                    : strings.scanningBleDevicesCount(devices.length),
              );
            },
            onError: (Object error) {
              bluetoothDevices = const <BluetoothDeviceInfo>[];
              isScanningBluetooth = false;
              _bluetoothScanSubscription = null;
              _setStatusMessage(strings.bleScanFailed(error));
            },
            onDone: () {
              isScanningBluetooth = false;
              _bluetoothScanSubscription = null;
              if (bluetoothDevices.isEmpty) {
                _setStatusMessage(strings.noBleDevicesFound);
              } else {
                _setStatusMessage(
                  strings.foundBleDevices(bluetoothDevices.length),
                );
              }
            },
          );
    } on Object catch (error) {
      bluetoothDevices = const <BluetoothDeviceInfo>[];
      isScanningBluetooth = false;
      _setStatusMessage(strings.bleScanFailed(error));
      notifyListeners();
    }
  }

  Future<void> stopBluetoothScan() async {
    await _bluetoothScanSubscription?.cancel();
    _bluetoothScanSubscription = null;
    if (!isScanningBluetooth) {
      return;
    }
    isScanningBluetooth = false;
    _setStatusMessage(
      bluetoothDevices.isEmpty
          ? strings.bleScanStopped
          : strings.bleScanStoppedWithCount(bluetoothDevices.length),
    );
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
    final reason = _capabilityFor(type)?.reason;
    return reason == null
        ? strings.unsupportedPlatform
        : strings.platformReason(reason);
  }

  void updateConfig(ConnectionConfig next) {
    config = next;
    _syncReceivePacketOptions();
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
          _syncReceivePacketOptions();
          _setStatusMessage(strings.webSerialPortSelected);
        }
      } on Object catch (error) {
        _setStatusMessage(strings.serialPortSelectFailed(error));
      }
      return;
    }

    config = config.copyWith(serial: config.serial.copyWith(portName: value));
    _syncReceivePacketOptions();
    notifyListeners();
  }

  void setTransportType(TransportType type) {
    if (!isTypeSupported(type)) {
      _setStatusMessage(
        strings.transportDisabled(type, unsupportedReason(type)),
      );
      return;
    }
    config = config.copyWith(type: type);
    _syncReceivePacketOptions();
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

  void saveSendDraftText(String value) {
    sendDraftText = value;
  }

  void fillQuickCommand(QuickCommand command) {
    sendDraftText = command.content;
    sendFormat = command.format;
    notifyListeners();
  }

  void saveAutoSendIntervalText(String value) {
    autoSendIntervalText = value;
  }

  void addQuickCommand({
    required String name,
    required String content,
    required PayloadFormat format,
  }) {
    final safeName = name.trim();
    if (safeName.isEmpty || content.isEmpty) {
      _setStatusMessage(strings.quickCommandEmpty);
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
    _persistQuickCommands();
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
      _setStatusMessage(strings.quickCommandEmpty);
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
    _persistQuickCommands();
    notifyListeners();
  }

  void removeQuickCommand(int id) {
    final before = quickCommands.length;
    quickCommands.removeWhere((command) => command.id == id);
    if (quickCommands.length == before) {
      return;
    }
    _persistQuickCommands();
    notifyListeners();
  }

  void reorderQuickCommand(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= quickCommands.length) {
      return;
    }
    final command = quickCommands.removeAt(oldIndex);
    final targetIndex = newIndex.clamp(0, quickCommands.length);
    quickCommands.insert(targetIndex, command);
    _persistQuickCommands();
    notifyListeners();
  }

  void importQuickCommands(
    Iterable<QuickCommand> commands, {
    required QuickCommandImportMode mode,
  }) {
    if (mode == QuickCommandImportMode.replace) {
      quickCommands.clear();
      _nextCommandId = 1;
    }
    for (final command in commands) {
      quickCommands.add(command.copyWith(id: _nextCommandId++));
    }
    _persistQuickCommands();
    notifyListeners();
  }

  Future<void> connect() async {
    if (_shutdownRequested ||
        _connectInFlight ||
        isConnected ||
        status == TransportStatus.connecting) {
      return;
    }
    _manualDisconnect = false;
    _serialReconnectRequested = false;
    _serialReconnectTimer?.cancel();
    _serialReconnectTimer = null;
    _connectInFlight = true;
    try {
      await _connect();
    } finally {
      _connectInFlight = false;
    }
  }

  Future<void> _connect() async {
    if (!isTypeSupported(config.type)) {
      _setStatusMessage(
        strings.transportDisabled(config.type, unsupportedReason(config.type)),
      );
      return;
    }
    if (config.type == TransportType.bluetooth) {
      await stopBluetoothScan();
    }

    status = TransportStatus.connecting;
    statusMessage = strings.connectingTo(
      strings.connectionSummary(config, serialDisplayName),
    );
    if (config.type == TransportType.bluetoothClassic) {
      _recordClassicBluetoothStep(
        operation: 'connect',
        stage: 'request',
        level: 'info',
        address: config.bluetoothClassic.address,
        message: '开始建立经典蓝牙 SPP/RFCOMM 连接。',
      );
    }
    notifyListeners();

    try {
      _syncReceivePacketOptions();
      _validateSerialForwarding();
      final session = await registry.create(config);
      await session.connect();
      TransportSession? forwardSession;
      if (config.type == TransportType.serial &&
          config.serial.forwardingEnabled) {
        try {
          forwardSession = await registry.create(
            config.copyWith(serial: config.serial.forwardEndpoint),
          );
          await forwardSession.connect();
        } on Object {
          await session.disconnect();
          rethrow;
        }
      }
      if (_shutdownRequested) {
        await forwardSession?.disconnect();
        await session.disconnect();
        status = TransportStatus.disconnected;
        statusMessage = strings.disconnected;
        return;
      }
      _session = session;
      _forwardSession = forwardSession;
      _manualDisconnect = false;
      _serialReconnectRequested = false;
      _serialReconnectTimer?.cancel();
      _serialReconnectTimer = null;
      _incomingSubscription = session.incoming.listen(
        forwardSession == null
            ? (bytes) => _pipeline.addBytes(bytes, source: sourceLabel)
            : _forwardFromPrimary,
        onError: (Object error, StackTrace stackTrace) {
          _handleReceiveError(error);
        },
        onDone: _handleUnexpectedDisconnect,
        cancelOnError: false,
      );
      if (forwardSession != null) {
        _forwardIncomingSubscription = forwardSession.incoming.listen(
          _forwardFromPeer,
          onError: (Object error, StackTrace stackTrace) {
            _handleReceiveError(error);
          },
          onDone: _handleUnexpectedDisconnect,
          cancelOnError: false,
        );
      }
      status = TransportStatus.connected;
      statusMessage = strings.connectedTo(sourceLabel);
      if (config.type == TransportType.bluetoothClassic) {
        _recordClassicBluetoothStep(
          operation: 'connect',
          stage: 'completed',
          level: 'success',
          address: config.bluetoothClassic.address,
          message: 'SPP/RFCOMM 连接已建立。',
        );
      }
      _sessionStartedAt = DateTime.now();
      _startStatsTicker();
      _appendSystem(statusMessage);
      notifyListeners();
    } on Object catch (error) {
      final isClassicBluetooth = config.type == TransportType.bluetoothClassic;
      if (isClassicBluetooth) {
        _recordClassicBluetoothFailure(
          error,
          operation: 'connect',
          address: config.bluetoothClassic.address,
        );
      }
      status = TransportStatus.error;
      statusMessage = strings.connectFailed(_formatError(error));
      if (!isClassicBluetooth) {
        _appendSystem(statusMessage);
      }
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (status == TransportStatus.disconnected ||
        status == TransportStatus.disconnecting) {
      return;
    }
    _manualDisconnect = true;
    _serialReconnectRequested = false;
    _serialReconnectTimer?.cancel();
    _serialReconnectTimer = null;
    status = TransportStatus.disconnecting;
    statusMessage = strings.disconnectingStatus;
    stopAutoSend();
    notifyListeners();

    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _forwardIncomingSubscription?.cancel();
    _forwardIncomingSubscription = null;
    await _forwardSession?.disconnect();
    _forwardSession = null;
    await _session?.disconnect();
    _session = null;
    _primaryWriteTail = Future<void>.value();
    _forwardWriteTail = Future<void>.value();
    _pipeline.flush();

    status = TransportStatus.disconnected;
    statusMessage = strings.disconnected;
    _stopStatsTicker();
    _appendSystem(statusMessage);
    notifyListeners();
  }

  Future<bool> scanClassicBluetoothDevices() async {
    if (isConnected || isScanningClassicBluetooth) {
      return false;
    }
    isScanningClassicBluetooth = true;
    _setStatusMessage(strings.scanningClassicBluetooth);
    _recordClassicBluetoothStep(
      operation: 'scan',
      stage: 'request',
      level: 'info',
      message: '开始扫描附近及系统已记住的经典蓝牙设备。',
    );
    notifyListeners();
    try {
      classicBluetoothDevices = await registry.classicBluetoothDevices();
      _setStatusMessage(
        classicBluetoothDevices.isEmpty
            ? strings.noClassicBluetoothDevices
            : strings.foundClassicBluetoothDevices(
                classicBluetoothDevices.length,
              ),
      );
      _recordClassicBluetoothStep(
        operation: 'scan',
        stage: 'completed',
        level: 'success',
        message: '经典蓝牙扫描完成，发现 ${classicBluetoothDevices.length} 个设备。',
      );
      return true;
    } on Object catch (error) {
      classicBluetoothDevices = const <ClassicBluetoothDeviceInfo>[];
      _recordClassicBluetoothFailure(error, operation: 'scan');
      _setStatusMessage(strings.classicBluetoothScanFailed(error));
      return false;
    } finally {
      isScanningClassicBluetooth = false;
      notifyListeners();
    }
  }

  void selectClassicBluetoothDevice(String address) {
    final matched = classicBluetoothDevices.where(
      (device) => device.address == address,
    );
    final device = matched.isEmpty ? null : matched.first;
    config = config.copyWith(
      bluetoothClassic: config.bluetoothClassic.copyWith(
        address: address,
        deviceName: device?.name ?? config.bluetoothClassic.deviceName,
      ),
    );
    notifyListeners();
  }

  Future<bool> pairClassicBluetoothDevice(String address) async {
    if (isConnected || classicBluetoothBusyAddress != null) {
      return false;
    }
    classicBluetoothBusyAddress = address;
    _setStatusMessage(strings.pairingClassicBluetooth(address));
    _recordClassicBluetoothStep(
      operation: 'pair',
      stage: 'request',
      level: 'info',
      address: address,
      message: '开始查找设备并请求 Windows 完成经典蓝牙认证。',
    );
    notifyListeners();
    try {
      final device = await registry.pairClassicBluetoothDevice(address);
      final scannedDevice = classicBluetoothDevices
          .where((candidate) => candidate.address == device.address)
          .firstOrNull;
      final retainedName = scannedDevice?.name.trim().isNotEmpty == true
          ? scannedDevice!.name
          : config.bluetoothClassic.deviceName;
      final mergedDevice = device.name.trim().isEmpty
          ? ClassicBluetoothDeviceInfo(
              address: device.address,
              name: retainedName,
              paired: device.paired,
              connected: device.connected,
              remembered: device.remembered,
            )
          : device;
      _replaceClassicBluetoothDevice(mergedDevice);
      selectClassicBluetoothDevice(mergedDevice.address);
      _setStatusMessage(strings.classicBluetoothPaired(mergedDevice.name));
      _recordClassicBluetoothStep(
        operation: 'pair',
        stage: 'completed',
        level: 'success',
        address: mergedDevice.address,
        message: 'Windows 已确认设备配对状态。',
      );
      return true;
    } on Object catch (error) {
      _recordClassicBluetoothFailure(
        error,
        operation: 'pair',
        address: address,
      );
      _setStatusMessage(strings.classicBluetoothPairFailed(error));
      return false;
    } finally {
      classicBluetoothBusyAddress = null;
      notifyListeners();
    }
  }

  Future<bool> unpairClassicBluetoothDevice(String address) async {
    if (isConnected || classicBluetoothBusyAddress != null) {
      return false;
    }
    classicBluetoothBusyAddress = address;
    _setStatusMessage(strings.unpairingClassicBluetooth(address));
    _recordClassicBluetoothStep(
      operation: 'unpair',
      stage: 'request',
      level: 'info',
      address: address,
      message: '请求 Windows 删除经典蓝牙配对记录。',
    );
    notifyListeners();
    try {
      await registry.unpairClassicBluetoothDevice(address);
      classicBluetoothDevices = classicBluetoothDevices
          .map(
            (device) => device.address == address
                ? ClassicBluetoothDeviceInfo(
                    address: device.address,
                    name: device.name,
                    paired: false,
                    connected: false,
                    remembered: false,
                  )
                : device,
          )
          .toList(growable: false);
      _setStatusMessage(strings.classicBluetoothUnpaired);
      _recordClassicBluetoothStep(
        operation: 'unpair',
        stage: 'completed',
        level: 'success',
        address: address,
        message: '经典蓝牙配对记录已删除。',
      );
      return true;
    } on Object catch (error) {
      _recordClassicBluetoothFailure(
        error,
        operation: 'unpair',
        address: address,
      );
      _setStatusMessage(strings.classicBluetoothUnpairFailed(error));
      return false;
    } finally {
      classicBluetoothBusyAddress = null;
      notifyListeners();
    }
  }

  void _replaceClassicBluetoothDevice(ClassicBluetoothDeviceInfo next) {
    final devices =
        <ClassicBluetoothDeviceInfo>[
          for (final device in classicBluetoothDevices)
            if (device.address != next.address) device,
          next,
        ]..sort((a, b) {
          if (a.paired != b.paired) {
            return a.paired ? -1 : 1;
          }
          return a.name.compareTo(b.name);
        });
    classicBluetoothDevices = List.unmodifiable(devices);
  }

  void clearClassicBluetoothDiagnostics() {
    classicBluetoothDiagnostics.clear();
    notifyListeners();
  }

  void _recordClassicBluetoothFailure(
    Object error, {
    required String operation,
    String? address,
  }) {
    final diagnostic = error is ClassicBluetoothOperationException
        ? error.diagnostic
        : ClassicBluetoothDiagnostic(
            id: 0,
            timestamp: DateTime.now(),
            operation: operation,
            stage: 'request',
            level: 'error',
            address: address,
            message: _formatError(error),
          );
    _recordClassicBluetoothDiagnostic(diagnostic);
  }

  void _recordClassicBluetoothStep({
    required String operation,
    required String stage,
    required String level,
    required String message,
    String? address,
  }) {
    _recordClassicBluetoothDiagnostic(
      ClassicBluetoothDiagnostic(
        id: 0,
        timestamp: DateTime.now(),
        operation: operation,
        stage: stage,
        level: level,
        address: address,
        message: message,
      ),
    );
  }

  void _recordClassicBluetoothDiagnostic(
    ClassicBluetoothDiagnostic diagnostic,
  ) {
    final stored = diagnostic.copyWith(
      id: _nextClassicBluetoothDiagnosticId++,
      timestamp: DateTime.now(),
    );
    classicBluetoothDiagnostics.add(stored);
    if (classicBluetoothDiagnostics.length > 200) {
      classicBluetoothDiagnostics.removeRange(
        0,
        classicBluetoothDiagnostics.length - 200,
      );
    }
    _appendSystem(stored.toLogText());
  }

  Future<void> shutdown() {
    _shutdownRequested = true;
    return _shutdownFuture ??= _shutdown();
  }

  Future<void> _shutdown() async {
    _manualDisconnect = true;
    _serialReconnectRequested = false;
    _autoSendTimer?.cancel();
    _autoSendTimer = null;
    _serialReconnectTimer?.cancel();
    _serialReconnectTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    await _closeTransportSessions();
    status = TransportStatus.disconnected;
    statusMessage = strings.disconnected;
  }

  Future<void> sendText(String text) async {
    await _sendPayload(
      text: text,
      format: sendFormat,
      ending: lineEnding,
      rememberHistory: true,
    );
  }

  Future<void> sendAsciiText(String text) async {
    await _sendPayload(
      text: text,
      format: PayloadFormat.ascii,
      ending: lineEnding,
      rememberHistory: true,
    );
  }

  Future<void> sendRawBytes(List<int> bytes) async {
    await _sendBytes(bytes, rememberHistory: false);
  }

  Future<void> sendRawBytesFrom(
    List<int> bytes, {
    required String source,
  }) async {
    await _sendBytes(
      bytes,
      rememberHistory: false,
      sourceOverride: source,
      rethrowOnFailure: true,
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
      rememberHistory: false,
    );
  }

  Future<void> _sendPayload({
    required String text,
    required PayloadFormat format,
    required LineEnding ending,
    required bool rememberHistory,
  }) async {
    final request = SendRequest(text: text, format: format, lineEnding: ending);
    if (request.bytes.isEmpty) {
      return;
    }
    await _sendBytes(
      request.bytes,
      rememberHistory: rememberHistory,
      historyText: text,
      historyFormat: format,
    );
  }

  Future<void> _sendBytes(
    List<int> bytes, {
    required bool rememberHistory,
    String? historyText,
    PayloadFormat? historyFormat,
    String? sourceOverride,
    bool rethrowOnFailure = false,
  }) async {
    if (bytes.isEmpty) {
      return;
    }
    final session = _session;
    if (session == null || !session.isConnected) {
      _appendSystem(strings.sendSkippedNoConnection);
      if (rethrowOnFailure) {
        throw StateError('No connected transport session.');
      }
      return;
    }

    try {
      await _queueWrite(session, bytes, primary: true);
      _commitFrames(<DataFrame>[
        DataFrame(
          sequence: _nextSequence(),
          timestamp: DateTime.now(),
          direction: FrameDirection.tx,
          bytes: bytes,
          source: sourceOverride ?? sourceLabel,
        ),
      ]);
      if (rememberHistory && historyText != null && historyFormat != null) {
        _rememberHistory(historyText, historyFormat);
      }
    } on Object catch (error) {
      final isClassicBluetooth = config.type == TransportType.bluetoothClassic;
      if (isClassicBluetooth) {
        _recordClassicBluetoothFailure(
          error,
          operation: 'send',
          address: config.bluetoothClassic.address,
        );
      }
      if (!isClassicBluetooth) {
        _appendSystem(strings.sendFailed(_formatError(error)));
      }
      if (rethrowOnFailure) {
        rethrow;
      }
    }
  }

  void startAutoSend(String text, Duration interval) {
    stopAutoSend();
    final safeInterval = interval < const Duration(milliseconds: 20)
        ? const Duration(milliseconds: 20)
        : interval;
    _autoSendTimer = Timer.periodic(safeInterval, (_) => _sendAutoText(text));
    _setStatusMessage(strings.autoSendEvery(safeInterval.inMilliseconds));
  }

  void startAutoSendFrom({
    required String text,
    required PayloadFormat format,
    required LineEnding ending,
    required Duration interval,
    required String source,
  }) {
    final request = SendRequest(text: text, format: format, lineEnding: ending);
    stopAutoSend();
    if (request.bytes.isEmpty) {
      return;
    }
    final safeInterval = interval < const Duration(milliseconds: 20)
        ? const Duration(milliseconds: 20)
        : interval;
    _autoSendTimer = Timer.periodic(
      safeInterval,
      (_) => _sendAutoBytes(request.bytes, source),
    );
    _setStatusMessage(strings.autoSendEvery(safeInterval.inMilliseconds));
  }

  void _sendAutoText(String text) {
    if (_autoSendInFlight) {
      return;
    }
    _autoSendInFlight = true;
    unawaited(
      sendText(text).whenComplete(() {
        _autoSendInFlight = false;
      }),
    );
  }

  void _sendAutoBytes(List<int> bytes, String source) {
    if (_autoSendInFlight) {
      return;
    }
    _autoSendInFlight = true;
    unawaited(
      _sendBytes(
        bytes,
        rememberHistory: false,
        sourceOverride: source,
      ).whenComplete(() {
        _autoSendInFlight = false;
      }),
    );
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

  void toggleLineEnding() {
    const values = LineEnding.values;
    final index = values.indexOf(lineEnding);
    setLineEnding(values[(index + 1) % values.length]);
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

  void setLineEndingSymbolsVisible(bool value) {
    showLineEndingSymbols = value;
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
      displaySnapshot.value = _displaySnapshot(paused: true);
    }
    notifyListeners();
  }

  void clearLog() {
    logBuffer.clear();
    _pipeline.clear();
    _packetPreview = null;
    _resetStats();
    _publishSnapshot();
    _statsNotifier.notifyListeners();
    notifyListeners();
  }

  Future<void> exportLog() async {
    try {
      final text = logBuffer.exportText(formatter, formatOptions);
      final result = await exportLogText(text);
      _setStatusMessage(strings.exportResult(result));
    } on Object catch (error) {
      _setStatusMessage(strings.exportFailed(error));
    }
  }

  void appendSystemMessage(String text) {
    _appendSystem(text);
  }

  void _commitFrames(List<DataFrame> frames) {
    final preview = _packetPreview;
    if (preview != null &&
        frames.any((frame) => frame.sequence == preview.sequence)) {
      _packetPreview = null;
    }
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
      _statsNotifier.notifyListeners();
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
    _displayRevision++;
    displaySnapshot.value = _displaySnapshot(paused: pauseDisplay);
  }

  LogSnapshot snapshotForDisplay({required bool paused}) =>
      _displaySnapshot(paused: paused);

  LogSnapshot _displaySnapshot({required bool paused}) {
    final committed = logBuffer.snapshot(paused: paused);
    final preview = _packetPreview;
    final frames = preview == null
        ? committed.frames
        : List<DataFrame>.unmodifiable(<DataFrame>[
            ...committed.frames,
            preview,
          ]);
    return LogSnapshot(
      revision: _displayRevision,
      frames: frames,
      totalFrames: committed.totalFrames,
      totalBytes: committed.totalBytes,
      droppedFrames: committed.droppedFrames,
      droppedBytes: committed.droppedBytes,
      paused: paused,
    );
  }

  void _updatePacketPreview(DataFrame frame) {
    _packetPreview = frame;
    if (!pauseDisplay) {
      _publishSnapshot();
    }
  }

  int _nextSequence() => ++_sequence;

  Future<void> _loadSavedQuickCommands() async {
    final List<QuickCommand>? savedCommands;
    try {
      savedCommands = await _loadQuickCommands();
    } on Object {
      return;
    }
    if (savedCommands == null) {
      return;
    }
    quickCommands
      ..clear()
      ..addAll(savedCommands);
    _nextCommandId = _nextQuickCommandId();
  }

  int _nextQuickCommandId() {
    var next = 1;
    for (final command in quickCommands) {
      if (command.id >= next) {
        next = command.id + 1;
      }
    }
    return next;
  }

  void _persistQuickCommands() {
    unawaited(
      _saveQuickCommands(List<QuickCommand>.unmodifiable(quickCommands)),
    );
  }

  void _rememberHistory(String text, PayloadFormat format) {
    if (text.trim().isEmpty) {
      return;
    }
    sendHistory.removeWhere(
      (item) => item.text == text && item.format == format,
    );
    sendHistory.insert(
      0,
      SendHistoryEntry(text: text, format: format, timestamp: DateTime.now()),
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
      _statsNotifier.notifyListeners();
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
    _statsNotifier.notifyListeners();
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

  void _syncReceivePacketOptions() {
    _pipeline.configurePacket(
      packetInterval: config.type == TransportType.serial
          ? config.serial.packetInterval
          : Duration.zero,
      packetDelimiter: config.type == TransportType.serial
          ? config.serial.packetDelimiterBytes
          : const <int>[],
    );
  }

  void _validateSerialForwarding() {
    if (config.type != TransportType.serial ||
        !config.serial.forwardingEnabled) {
      return;
    }
    final primary = config.serial.portName.trim();
    final peer = config.serial.forwardPortName.trim();
    if (primary.isEmpty) {
      throw StateError('No serial port selected.');
    }
    if (peer.isEmpty) {
      throw StateError('No forwarding serial port selected.');
    }
    if (primary.toLowerCase() == peer.toLowerCase()) {
      throw StateError('Forwarding serial ports must be different.');
    }
  }

  void _forwardFromPrimary(List<int> bytes) {
    _pipeline.addBytes(
      bytes,
      source: '${config.serial.portName} → ${config.serial.forwardPortName}',
      direction: FrameDirection.tx,
    );
    final target = _forwardSession;
    if (target != null) {
      unawaited(_queueForwardedWrite(target, bytes, primary: false));
    }
  }

  void _forwardFromPeer(List<int> bytes) {
    _pipeline.addBytes(
      bytes,
      source: '${config.serial.forwardPortName} → ${config.serial.portName}',
      direction: FrameDirection.rx,
    );
    final target = _session;
    if (target != null) {
      unawaited(_queueForwardedWrite(target, bytes, primary: true));
    }
  }

  Future<void> _queueForwardedWrite(
    TransportSession target,
    List<int> bytes, {
    required bool primary,
  }) async {
    try {
      await _queueWrite(target, bytes, primary: primary);
    } on Object catch (error) {
      _appendSystem(strings.sendFailed(_formatError(error)));
    }
  }

  Future<void> _queueWrite(
    TransportSession target,
    List<int> bytes, {
    required bool primary,
  }) {
    final previous = primary ? _primaryWriteTail : _forwardWriteTail;
    final next = previous
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .then((_) => target.send(List<int>.of(bytes)));
    if (primary) {
      _primaryWriteTail = next;
    } else {
      _forwardWriteTail = next;
    }
    return next;
  }

  void _handleUnexpectedDisconnect() {
    if (_manualDisconnect || status == TransportStatus.error) {
      return;
    }
    _serialReconnectRequested = config.type == TransportType.serial;
    status = TransportStatus.error;
    statusMessage = strings.unexpectedDisconnect;
    _stopStatsTicker();
    _appendSystem(strings.unexpectedDisconnect);
    notifyListeners();
    unawaited(_closeAfterUnexpectedDisconnect());
  }

  void _handleReceiveError(Object error) {
    final isClassicBluetooth = config.type == TransportType.bluetoothClassic;
    if (isClassicBluetooth) {
      _recordClassicBluetoothFailure(
        error,
        operation: 'receive',
        address: config.bluetoothClassic.address,
      );
    }
    if (!isClassicBluetooth) {
      _appendSystem(strings.receiveError(_formatError(error)));
    }
    _handleUnexpectedDisconnect();
  }

  Future<void> _closeAfterUnexpectedDisconnect() async {
    try {
      await _closeTransportSessions();
    } on Object {
      // Reconnection creates fresh transport sessions even if cleanup failed.
    }
    _scheduleSerialReconnect();
  }

  void _scheduleSerialReconnect() {
    if (_disposed ||
        _manualDisconnect ||
        !_serialReconnectRequested ||
        config.type != TransportType.serial ||
        isConnected ||
        _serialReconnectTimer != null) {
      return;
    }
    _serialReconnectTimer = Timer(_serialReconnectInterval, () {
      _serialReconnectTimer = null;
      unawaited(_attemptSerialReconnect());
    });
  }

  Future<void> _attemptSerialReconnect() async {
    if (_disposed ||
        _manualDisconnect ||
        !_serialReconnectRequested ||
        config.type != TransportType.serial ||
        isConnected) {
      return;
    }
    if (_connectInFlight) {
      _scheduleSerialReconnect();
      return;
    }

    try {
      final ports = await registry.serialPorts();
      serialPorts = ports;
      notifyListeners();
      if (!_serialEndpointsAvailable(ports)) {
        _scheduleSerialReconnect();
        return;
      }
    } on Object {
      _scheduleSerialReconnect();
      return;
    }

    _connectInFlight = true;
    try {
      await _connect();
    } finally {
      _connectInFlight = false;
    }
    if (!isConnected) {
      _scheduleSerialReconnect();
    }
  }

  bool _serialEndpointsAvailable(List<String> ports) {
    bool contains(String portName) {
      final target = portName.trim().toLowerCase();
      return target.isNotEmpty &&
          ports.any((port) => port.trim().toLowerCase() == target);
    }

    final serial = config.serial;
    if (!contains(serial.portName)) {
      return false;
    }
    return !serial.forwardingEnabled || contains(serial.forwardPortName);
  }

  Future<void> _closeTransportSessions() async {
    final primarySubscription = _incomingSubscription;
    final forwardSubscription = _forwardIncomingSubscription;
    final primarySession = _session;
    final forwardSession = _forwardSession;
    _incomingSubscription = null;
    _forwardIncomingSubscription = null;
    _session = null;
    _forwardSession = null;
    await primarySubscription?.cancel();
    await forwardSubscription?.cancel();
    await forwardSession?.disconnect();
    await primarySession?.disconnect();
    _primaryWriteTail = Future<void>.value();
    _forwardWriteTail = Future<void>.value();
    _pipeline.flush();
  }

  String _formatError(Object error) {
    if (error is SocketException) {
      return _formatSocketException(error);
    }
    return strings.errorMessage(error);
  }

  String _formatSocketException(SocketException error) {
    final code = error.osError?.errorCode;
    final address = error.address?.address;
    final port = error.port;
    final parts = <String>[strings.socketExceptionLabel];
    if (code != null) {
      parts.add('${strings.socketErrnoLabel}=$code');
      final meaning = _windowsSocketErrorMeaning(code);
      if (meaning != null) {
        parts.add(meaning);
      }
    }
    if (address != null && address.isNotEmpty) {
      parts.add('${strings.socketAddressLabel}=$address');
    }
    if (port != null) {
      parts.add('${strings.socketPortLabel}=$port');
    }
    return parts.join(', ');
  }

  String? _windowsSocketErrorMeaning(int code) {
    return strings.windowsSocketErrorMeaning(code);
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
    _disposed = true;
    _shutdownRequested = true;
    _manualDisconnect = true;
    _serialReconnectRequested = false;
    _autoSendTimer?.cancel();
    _statsTimer?.cancel();
    _serialReconnectTimer?.cancel();
    _incomingSubscription?.cancel();
    _forwardIncomingSubscription?.cancel();
    _bluetoothScanSubscription?.cancel();
    _session?.disconnect();
    _forwardSession?.disconnect();
    _pipeline.dispose();
    displaySnapshot.dispose();
    _statsNotifier.dispose();
    super.dispose();
  }
}
