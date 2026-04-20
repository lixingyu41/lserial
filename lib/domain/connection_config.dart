import 'dart:convert';

import 'transport.dart';

const defaultSerialPacketDelimiter = r'\r\n';

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
    this.packetIntervalMs = 0,
    this.packetDelimiter = defaultSerialPacketDelimiter,
  });

  final String portName;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final SerialParity parity;
  final int packetIntervalMs;
  final String packetDelimiter;

  Duration get packetInterval {
    final milliseconds = packetIntervalMs < 0 ? 0 : packetIntervalMs;
    return Duration(milliseconds: milliseconds);
  }

  List<int> get packetDelimiterBytes =>
      parseSerialPacketDelimiter(packetDelimiter);

  SerialConfig copyWith({
    String? portName,
    int? baudRate,
    int? dataBits,
    int? stopBits,
    SerialParity? parity,
    int? packetIntervalMs,
    String? packetDelimiter,
  }) {
    return SerialConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      stopBits: stopBits ?? this.stopBits,
      parity: parity ?? this.parity,
      packetIntervalMs: packetIntervalMs ?? this.packetIntervalMs,
      packetDelimiter: packetDelimiter ?? this.packetDelimiter,
    );
  }
}

List<int> parseSerialPacketDelimiter(String value) {
  if (value.isEmpty) {
    return const <int>[];
  }

  final shortcut = _delimiterShortcut(value.trim());
  if (shortcut != null) {
    return shortcut;
  }

  final bytes = <int>[];
  var index = 0;
  while (index < value.length) {
    final marker = value.codeUnitAt(index);
    if ((marker == _backslash || marker == _slash) &&
        index + 1 < value.length) {
      final next = value.codeUnitAt(index + 1);
      final lower = _lowerAscii(next);
      if (lower == _r) {
        bytes.add(0x0d);
        index += 2;
        continue;
      }
      if (lower == _n) {
        bytes.add(0x0a);
        index += 2;
        continue;
      }
      if (lower == _t) {
        bytes.add(0x09);
        index += 2;
        continue;
      }
      if (next == _zero) {
        bytes.add(0x00);
        index += 2;
        continue;
      }
      if (lower == _x && index + 3 < value.length) {
        final hex = value.substring(index + 2, index + 4);
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed != null) {
          bytes.add(parsed);
          index += 4;
          continue;
        }
      }
    }

    final codeUnit = value.codeUnitAt(index);
    final nextIndex = _isLeadSurrogate(codeUnit) && index + 1 < value.length
        ? index + 2
        : index + 1;
    bytes.addAll(utf8.encode(value.substring(index, nextIndex)));
    index = nextIndex;
  }

  return bytes;
}

List<int>? _delimiterShortcut(String value) {
  final normalized = value.toUpperCase().replaceAll(RegExp(r'[\s_\-+]'), '');
  return switch (normalized) {
    'CR' => const <int>[0x0d],
    'LF' => const <int>[0x0a],
    'CRLF' => const <int>[0x0d, 0x0a],
    _ => null,
  };
}

bool _isLeadSurrogate(int codeUnit) {
  return codeUnit >= 0xd800 && codeUnit <= 0xdbff;
}

int _lowerAscii(int codeUnit) {
  return codeUnit >= 0x41 && codeUnit <= 0x5a ? codeUnit + 0x20 : codeUnit;
}

const _backslash = 0x5c;
const _slash = 0x2f;
const _n = 0x6e;
const _r = 0x72;
const _t = 0x74;
const _x = 0x78;
const _zero = 0x30;

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
    this.deviceName = '',
    this.serviceUuid = '',
    this.characteristicUuid = '',
    this.writeCharacteristicUuid = '',
    this.notifyCharacteristicUuid = '',
    this.writeWithoutResponse = false,
  });

  final String deviceId;
  final String deviceName;
  final String serviceUuid;
  final String characteristicUuid;
  final String writeCharacteristicUuid;
  final String notifyCharacteristicUuid;
  final bool writeWithoutResponse;

  String get effectiveWriteCharacteristicUuid => writeCharacteristicUuid.isEmpty
      ? characteristicUuid
      : writeCharacteristicUuid;

  String get effectiveNotifyCharacteristicUuid =>
      notifyCharacteristicUuid.isEmpty
          ? effectiveWriteCharacteristicUuid
          : notifyCharacteristicUuid;

  BluetoothConfig copyWith({
    String? deviceId,
    String? deviceName,
    String? serviceUuid,
    String? characteristicUuid,
    String? writeCharacteristicUuid,
    String? notifyCharacteristicUuid,
    bool? writeWithoutResponse,
  }) {
    return BluetoothConfig(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      characteristicUuid: characteristicUuid ?? this.characteristicUuid,
      writeCharacteristicUuid:
          writeCharacteristicUuid ?? this.writeCharacteristicUuid,
      notifyCharacteristicUuid:
          notifyCharacteristicUuid ?? this.notifyCharacteristicUuid,
      writeWithoutResponse: writeWithoutResponse ?? this.writeWithoutResponse,
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
        TransportType.bluetooth => bluetooth.deviceName.isEmpty
            ? 'BLE ${bluetooth.deviceId}'
            : 'BLE ${bluetooth.deviceName}',
        TransportType.tcpClient => 'TCP ${tcpClient.host}:${tcpClient.port}',
        TransportType.tcpServer =>
          'TCP Server ${tcpServer.bindAddress}:${tcpServer.port}',
        TransportType.udp =>
          'UDP ${udp.bindAddress}:${udp.localPort} -> ${udp.remoteHost}:${udp.remotePort}',
      };
}
