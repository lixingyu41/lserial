enum TransportType { serial, bluetooth, tcpClient, tcpServer, udp }

enum TransportStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum SerialOpenFailure {
  busyOrPermission,
  unavailable,
  driverInitialization,
  timedOut,
  unknown,
}

class SerialOpenException implements Exception {
  const SerialOpenException({
    required this.portName,
    required this.failure,
    this.nativeCode,
    this.nativeMessage,
  });

  final String portName;
  final SerialOpenFailure failure;
  final int? nativeCode;
  final String? nativeMessage;

  @override
  String toString() {
    final details = <String>[
      if (nativeCode != null) 'code $nativeCode',
      if (nativeMessage != null && nativeMessage!.trim().isNotEmpty)
        nativeMessage!.trim(),
    ];
    final suffix = details.isEmpty ? '' : ' (${details.join(': ')})';
    return 'Failed to open serial port $portName: ${failure.name}$suffix';
  }
}

extension TransportTypeLabel on TransportType {
  String get label => switch (this) {
    TransportType.serial => 'Serial',
    TransportType.bluetooth => 'Bluetooth',
    TransportType.tcpClient => 'TCP Client',
    TransportType.tcpServer => 'TCP Server',
    TransportType.udp => 'UDP',
  };
}

extension TransportStatusLabel on TransportStatus {
  String get label => switch (this) {
    TransportStatus.disconnected => 'Disconnected',
    TransportStatus.connecting => 'Connecting',
    TransportStatus.connected => 'Connected',
    TransportStatus.disconnecting => 'Disconnecting',
    TransportStatus.error => 'Error',
  };
}

class TransportCapability {
  const TransportCapability({
    required this.type,
    required this.supported,
    required this.reason,
  });

  final TransportType type;
  final bool supported;
  final String reason;
}

abstract interface class TransportSession {
  TransportType get type;

  String get label;

  bool get isConnected;

  Stream<List<int>> get incoming;

  Future<void> connect();

  Future<void> send(List<int> bytes);

  Future<void> disconnect();
}

class UnsupportedTransportSession implements TransportSession {
  UnsupportedTransportSession({required this.type, required this.reason});

  @override
  final TransportType type;

  final String reason;

  @override
  String get label => type.label;

  @override
  bool get isConnected => false;

  @override
  Stream<List<int>> get incoming => const Stream<List<int>>.empty();

  @override
  Future<void> connect() => throw UnsupportedError(reason);

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(List<int> bytes) => throw UnsupportedError(reason);
}
