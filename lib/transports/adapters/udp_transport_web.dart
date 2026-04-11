import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createUdpSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.udp,
    reason: 'Static Web apps cannot open raw UDP sockets in Chrome.',
  );
}
