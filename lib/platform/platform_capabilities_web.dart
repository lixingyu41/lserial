import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../domain/transport.dart';

@JS('navigator')
external JSObject get _navigator;

Future<List<TransportCapability>> loadPlatformCapabilities() async {
  final hasSerial = _navigator.has('serial');
  final hasBluetooth = _navigator.has('bluetooth');
  return <TransportCapability>[
    TransportCapability(
      type: TransportType.serial,
      supported: hasSerial,
      reason: hasSerial
          ? 'Chrome Web Serial is available. Requires user gesture and HTTPS/localhost.'
          : 'Web Serial is not available in this browser.',
    ),
    TransportCapability(
      type: TransportType.bluetooth,
      supported: hasBluetooth,
      reason: hasBluetooth
          ? 'Chrome Web Bluetooth is available for BLE GATT.'
          : 'Web Bluetooth is not available in this browser.',
    ),
    const TransportCapability(
      type: TransportType.bluetoothClassic,
      supported: false,
      reason: 'Bluetooth Classic RFCOMM/SPP is unavailable in browsers.',
    ),
    const TransportCapability(
      type: TransportType.tcpClient,
      supported: false,
      reason: 'Browsers do not expose raw TCP sockets to static web apps.',
    ),
    const TransportCapability(
      type: TransportType.tcpServer,
      supported: false,
      reason: 'Browsers cannot listen as raw TCP servers without a backend.',
    ),
    const TransportCapability(
      type: TransportType.udp,
      supported: false,
      reason: 'Browsers do not expose raw UDP sockets to static web apps.',
    ),
  ];
}
