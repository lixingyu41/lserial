import '../../domain/classic_bluetooth_device_info.dart';
import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createClassicBluetoothSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.bluetoothClassic,
    reason: 'Bluetooth Classic RFCOMM/SPP is available on Windows only.',
  );
}

Future<List<ClassicBluetoothDeviceInfo>> scanClassicBluetoothDevices({
  Duration timeout = const Duration(seconds: 6),
}) {
  throw UnsupportedError(
    'Bluetooth Classic RFCOMM/SPP is available on Windows only.',
  );
}

Future<ClassicBluetoothDeviceInfo> pairClassicBluetoothDevice(String address) {
  throw UnsupportedError(
    'Bluetooth Classic pairing is available on Windows only.',
  );
}

Future<void> unpairClassicBluetoothDevice(String address) {
  throw UnsupportedError(
    'Bluetooth Classic unpairing is available on Windows only.',
  );
}
