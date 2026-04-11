import 'dart:async';
import 'dart:io';

import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createUdpSession(ConnectionConfig config) {
  return UdpTransportSession(config);
}

class UdpTransportSession implements TransportSession {
  UdpTransportSession(this.config);

  final ConnectionConfig config;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;

  @override
  TransportType get type => TransportType.udp;

  @override
  String get label => '${config.udp.bindAddress}:${config.udp.localPort}';

  @override
  bool get isConnected => _socket != null;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    final bindAddress = config.udp.bindAddress.trim().isEmpty
        ? InternetAddress.anyIPv4
        : InternetAddress(config.udp.bindAddress.trim());
    final socket =
        await RawDatagramSocket.bind(bindAddress, config.udp.localPort);
    _socket = socket;
    _subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        _incoming.add(datagram!.data);
      }
    }, onError: _incoming.addError);
  }

  @override
  Future<void> send(List<int> bytes) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('UDP socket is not open.');
    }
    final remote = InternetAddress(config.udp.remoteHost);
    socket.send(bytes, remote, config.udp.remotePort);
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
