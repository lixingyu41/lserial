import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

@JS('navigator')
external JSObject get _navigator;

TransportSession createBluetoothSession(ConnectionConfig config) {
  final hasBluetooth = _navigator.has('bluetooth');
  return UnsupportedTransportSession(
    type: TransportType.bluetooth,
    reason: hasBluetooth
        ? 'Web Bluetooth capability detected; BLE GATT implementation is the next adapter step.'
        : 'Web Bluetooth is not available in this browser.',
  );
}
