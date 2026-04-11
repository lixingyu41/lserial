import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import 'tcp_transport_stub.dart'
    if (dart.library.io) 'tcp_transport_io.dart'
    if (dart.library.js_interop) 'tcp_transport_web.dart' as impl;

TransportSession createTcpClientSession(ConnectionConfig config) {
  return impl.createTcpClientSession(config);
}

TransportSession createTcpServerSession(ConnectionConfig config) {
  return impl.createTcpServerSession(config);
}
