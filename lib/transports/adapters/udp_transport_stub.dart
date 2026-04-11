import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createUdpSession(ConnectionConfig config) {
  return UnsupportedTransportSession(
    type: TransportType.udp,
    reason: 'UDP is not supported on this platform.',
  );
}
