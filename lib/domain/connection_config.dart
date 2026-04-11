import 'transport.dart';

enum SerialParity {
  none,
  odd,
  even,
}

extension SerialParityLabel on SerialParity {
  String get label => switch (this) {
        SerialParity.none => 'None',
        SerialParity.odd => 'Odd',
        SerialParity.even => 'Even',
      };
}

class SerialConfig {
  const SerialConfig({
    this.portName = '',
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = SerialParity.none,
  });

  final String portName;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final SerialParity parity;

  SerialConfig copyWith({
    String? portName,
    int? baudRate,
    int? dataBits,
    int? stopBits,
    SerialParity? parity,
  }) {
    return SerialConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      stopBits: stopBits ?? this.stopBits,
      parity: parity ?? this.parity,
    );
  }
}

class TcpClientConfig {
  const TcpClientConfig({
    this.host = '127.0.0.1',
    this.port = 9000,
  });

  final String host;
  final int port;

  TcpClientConfig copyWith({String? host, int? port}) {
    return TcpClientConfig(
      host: host ?? this.host,
      port: port ?? this.port,
    );
  }
}

class TcpServerConfig {
  const TcpServerConfig({
    this.bindAddress = '0.0.0.0',
    this.port = 9000,
  });

  final String bindAddress;
  final int port;

  TcpServerConfig copyWith({String? bindAddress, int? port}) {
    return TcpServerConfig(
      bindAddress: bindAddress ?? this.bindAddress,
      port: port ?? this.port,
    );
  }
}

class UdpConfig {
  const UdpConfig({
    this.bindAddress = '0.0.0.0',
    this.localPort = 9001,
    this.remoteHost = '127.0.0.1',
    this.remotePort = 9001,
  });

  final String bindAddress;
  final int localPort;
  final String remoteHost;
  final int remotePort;

  UdpConfig copyWith({
    String? bindAddress,
    int? localPort,
    String? remoteHost,
    int? remotePort,
  }) {
    return UdpConfig(
      bindAddress: bindAddress ?? this.bindAddress,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
    );
  }
}

class BluetoothConfig {
  const BluetoothConfig({
    this.deviceId = '',
    this.serviceUuid = '',
    this.characteristicUuid = '',
  });

  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;

  BluetoothConfig copyWith({
    String? deviceId,
    String? serviceUuid,
    String? characteristicUuid,
  }) {
    return BluetoothConfig(
      deviceId: deviceId ?? this.deviceId,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      characteristicUuid: characteristicUuid ?? this.characteristicUuid,
    );
  }
}

class ConnectionConfig {
  const ConnectionConfig({
    this.type = TransportType.serial,
    this.serial = const SerialConfig(),
    this.tcpClient = const TcpClientConfig(),
    this.tcpServer = const TcpServerConfig(),
    this.udp = const UdpConfig(),
    this.bluetooth = const BluetoothConfig(),
  });

  final TransportType type;
  final SerialConfig serial;
  final TcpClientConfig tcpClient;
  final TcpServerConfig tcpServer;
  final UdpConfig udp;
  final BluetoothConfig bluetooth;

  ConnectionConfig copyWith({
    TransportType? type,
    SerialConfig? serial,
    TcpClientConfig? tcpClient,
    TcpServerConfig? tcpServer,
    UdpConfig? udp,
    BluetoothConfig? bluetooth,
  }) {
    return ConnectionConfig(
      type: type ?? this.type,
      serial: serial ?? this.serial,
      tcpClient: tcpClient ?? this.tcpClient,
      tcpServer: tcpServer ?? this.tcpServer,
      udp: udp ?? this.udp,
      bluetooth: bluetooth ?? this.bluetooth,
    );
  }

  String get summary => switch (type) {
        TransportType.serial => serial.portName.isEmpty
            ? 'Serial: no port selected'
            : 'Serial ${serial.portName} @ ${serial.baudRate}',
        TransportType.bluetooth => 'Bluetooth ${bluetooth.deviceId}',
        TransportType.tcpClient => 'TCP ${tcpClient.host}:${tcpClient.port}',
        TransportType.tcpServer =>
          'TCP Server ${tcpServer.bindAddress}:${tcpServer.port}',
        TransportType.udp =>
          'UDP ${udp.bindAddress}:${udp.localPort} -> ${udp.remoteHost}:${udp.remotePort}',
      };
}
