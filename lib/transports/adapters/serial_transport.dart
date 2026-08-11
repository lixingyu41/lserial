import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import 'serial_transport_stub.dart'
    if (dart.library.io) 'serial_transport_desktop.dart'
    if (dart.library.js_interop) 'serial_transport_web.dart'
    as impl;

Future<List<String>> listSerialPorts() => impl.listSerialPorts();

Future<String?> requestSerialPort() => impl.requestSerialPort();

TransportSession createSerialSession(ConnectionConfig config) {
  return impl.createSerialSession(config);
}
