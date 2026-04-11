import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createTcpClientSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.tcpClient,
    reason: 'Static Web apps cannot open raw TCP sockets in Chrome.',
  );
}

TransportSession createTcpServerSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.tcpServer,
    reason: 'Static Web apps cannot listen as raw TCP servers in Chrome.',
  );
}
