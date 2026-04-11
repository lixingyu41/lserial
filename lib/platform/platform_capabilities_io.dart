import '../domain/transport.dart';

Future<List<TransportCapability>> loadPlatformCapabilities() async {
  return const <TransportCapability>[
    TransportCapability(
      type: TransportType.serial,
      supported: true,
      reason: 'Native serial via flutter_libserialport.',
    ),
    TransportCapability(
      type: TransportType.bluetooth,
      supported: false,
      reason:
          'Bluetooth adapter placeholder; choose BLE/SPP plugin per target hardware.',
    ),
    TransportCapability(
      type: TransportType.tcpClient,
      supported: true,
      reason: 'Native sockets via dart:io.',
    ),
    TransportCapability(
      type: TransportType.tcpServer,
      supported: true,
      reason: 'Native sockets via dart:io.',
    ),
    TransportCapability(
      type: TransportType.udp,
      supported: true,
      reason: 'Native UDP sockets via dart:io.',
    ),
  ];
}
