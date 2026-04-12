import '../domain/connection_config.dart';
import '../domain/bluetooth_device_info.dart';
import '../domain/transport.dart';
import 'adapters/bluetooth_transport.dart' as bluetooth;
import 'adapters/serial_transport.dart' as serial;
import 'adapters/tcp_transport.dart';
import 'adapters/udp_transport.dart';

class TransportRegistry {
  const TransportRegistry();

  Future<TransportSession> create(ConnectionConfig config) async {
    return switch (config.type) {
      TransportType.serial => serial.createSerialSession(config),
      TransportType.bluetooth => bluetooth.createBluetoothSession(config),
      TransportType.tcpClient => createTcpClientSession(config),
      TransportType.tcpServer => createTcpServerSession(config),
      TransportType.udp => createUdpSession(config),
    };
  }

  Future<List<String>> serialPorts() => serial.listSerialPorts();

  Future<String?> requestSerialPort() => serial.requestSerialPort();

  Future<List<BluetoothDeviceInfo>> bluetoothDevices({
    String? serviceUuid,
    Duration timeout = const Duration(seconds: 8),
  }) {
    return bluetooth.scanBluetoothDevices(
      serviceUuid: serviceUuid,
      timeout: timeout,
    );
  }
}
