import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createBluetoothSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.bluetooth,
    reason:
        'Bluetooth adapter is reserved for BLE/SPP integration; not enabled in this MVP.',
  );
}
