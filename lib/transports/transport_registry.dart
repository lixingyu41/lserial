import '../domain/connection_config.dart';
import '../domain/transport.dart';
import 'adapters/bluetooth_transport.dart';
import 'adapters/serial_transport.dart';
import 'adapters/tcp_transport.dart';
import 'adapters/udp_transport.dart';

class TransportRegistry {
  const TransportRegistry();

  Future<TransportSession> create(ConnectionConfig config) async {
    return switch (config.type) {
      TransportType.serial => createSerialSession(config),
      TransportType.bluetooth => createBluetoothSession(config),
      TransportType.tcpClient => createTcpClientSession(config),
      TransportType.tcpServer => createTcpServerSession(config),
      TransportType.udp => createUdpSession(config),
    };
  }

  Future<List<String>> serialPorts() => listSerialPorts();
}
