import 'dart:io';

import '../domain/transport.dart';

Future<List<TransportCapability>> loadPlatformCapabilities() async {
  return <TransportCapability>[
    const TransportCapability(
      type: TransportType.serial,
      supported: true,
      reason: 'Native serial via flutter_libserialport.',
    ),
    const TransportCapability(
      type: TransportType.bluetooth,
      supported: true,
      reason: 'BLE via universal_ble. Bluetooth Classic/SPP is not included.',
    ),
    TransportCapability(
      type: TransportType.bluetoothClassic,
      supported: Platform.isWindows,
      reason: Platform.isWindows
          ? 'Bluetooth Classic RFCOMM/SPP via native Windows APIs.'
          : 'Bluetooth Classic RFCOMM/SPP is currently Windows-only.',
    ),
    const TransportCapability(
      type: TransportType.tcpClient,
      supported: true,
      reason: 'Native sockets via dart:io.',
    ),
    const TransportCapability(
      type: TransportType.tcpServer,
      supported: true,
      reason: 'Native sockets via dart:io.',
    ),
    const TransportCapability(
      type: TransportType.udp,
      supported: true,
      reason: 'Native UDP sockets via dart:io.',
    ),
  ];
}
