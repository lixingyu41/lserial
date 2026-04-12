import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

Future<List<String>> listSerialPorts() async => const <String>[];

Future<String?> requestSerialPort() async => null;

TransportSession createSerialSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.serial,
    reason: 'Serial is not supported on this platform.',
  );
}
