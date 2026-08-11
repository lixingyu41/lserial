import '../../domain/classic_bluetooth_device_info.dart';
import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import 'classic_bluetooth_transport_stub.dart'
    if (dart.library.io) 'classic_bluetooth_transport_io.dart'
    as impl;

TransportSession createClassicBluetoothSession(ConnectionConfig config) {
  return impl.createClassicBluetoothSession(config);
}

Future<List<ClassicBluetoothDeviceInfo>> scanClassicBluetoothDevices({
  Duration timeout = const Duration(seconds: 6),
}) {
  return impl.scanClassicBluetoothDevices(timeout: timeout);
}

Future<ClassicBluetoothDeviceInfo> pairClassicBluetoothDevice(String address) {
  return impl.pairClassicBluetoothDevice(address);
}

Future<void> unpairClassicBluetoothDevice(String address) {
  return impl.unpairClassicBluetoothDevice(address);
}
