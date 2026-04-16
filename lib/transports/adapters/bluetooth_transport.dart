import '../../domain/connection_config.dart';
import '../../domain/bluetooth_device_info.dart';
import '../../domain/transport.dart';
import 'bluetooth_transport_universal.dart' as impl;

TransportSession createBluetoothSession(ConnectionConfig config) {
  return impl.createBluetoothSession(config);
}

Future<List<BluetoothDeviceInfo>> scanBluetoothDevices({
  String? serviceUuid,
  Duration timeout = const Duration(seconds: 8),
}) {
  return impl.scanBluetoothDevices(
    serviceUuid: serviceUuid,
    timeout: timeout,
  );
}

Stream<List<BluetoothDeviceInfo>> scanBluetoothDeviceStream({
  String? serviceUuid,
}) {
  return impl.scanBluetoothDeviceStream(serviceUuid: serviceUuid);
}
