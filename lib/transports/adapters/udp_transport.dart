import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import 'udp_transport_stub.dart'
    if (dart.library.io) 'udp_transport_io.dart'
    if (dart.library.js_interop) 'udp_transport_web.dart' as impl;

TransportSession createUdpSession(ConnectionConfig config) {
  return impl.createUdpSession(config);
}
