import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/domain/connection_config.dart';
import 'package:lserial/domain/transport.dart';
import 'package:lserial/transports/adapters/tcp_transport_io.dart';

void main() {
  test(
    'TCP server binds exclusively and releases its port on disconnect',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      final port = reservation.port;
      await reservation.close();
      final config = ConnectionConfig(
        type: TransportType.tcpServer,
        tcpServer: TcpServerConfig(bindAddress: '127.0.0.1', port: port),
      );
      final first = TcpServerTransportSession(config);
      final competing = TcpServerTransportSession(config);
      final reopened = TcpServerTransportSession(config);
      addTearDown(() async {
        await competing.disconnect();
        await reopened.disconnect();
        await first.disconnect();
      });

      await first.connect();
      expect(first.isConnected, isTrue);
      await expectLater(competing.connect(), throwsA(isA<SocketException>()));

      await first.disconnect();
      await reopened.connect();
      expect(reopened.isConnected, isTrue);
    },
  );
}
