import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createTcpClientSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.tcpClient,
    reason: 'TCP Client is not supported on this platform.',
  );
}

TransportSession createTcpServerSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.tcpServer,
    reason: 'TCP Server is not supported on this platform.',
  );
}
