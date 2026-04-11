import 'dart:async';
import 'dart:io';

import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

TransportSession createTcpClientSession(ConnectionConfig config) {
  return TcpClientTransportSession(config);
}

TransportSession createTcpServerSession(ConnectionConfig config) {
  return TcpServerTransportSession(config);
}

class TcpClientTransportSession implements TransportSession {
  TcpClientTransportSession(this.config);

  final ConnectionConfig config;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;

  @override
  TransportType get type => TransportType.tcpClient;

  @override
  String get label => '${config.tcpClient.host}:${config.tcpClient.port}';

  @override
  bool get isConnected => _socket != null;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    final socket =
        await Socket.connect(config.tcpClient.host, config.tcpClient.port);
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    _subscription = socket.listen(
      _incoming.add,
      onError: _incoming.addError,
      onDone: () {
        _socket = null;
        if (!_incoming.isClosed) {
          _incoming.close();
        }
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> send(List<int> bytes) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('TCP client is not connected.');
    }
    socket.add(bytes);
    await socket.flush();
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

class TcpServerTransportSession implements TransportSession {
  TcpServerTransportSession(this.config);

  final ConnectionConfig config;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<Socket> _clients = <Socket>[];
  final List<StreamSubscription<List<int>>> _clientSubscriptions =
      <StreamSubscription<List<int>>>[];
  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;

  @override
  TransportType get type => TransportType.tcpServer;

  @override
  String get label =>
      '${config.tcpServer.bindAddress}:${config.tcpServer.port}';

  @override
  bool get isConnected => _server != null;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    final bindAddress = config.tcpServer.bindAddress.trim().isEmpty
        ? InternetAddress.anyIPv4
        : InternetAddress(config.tcpServer.bindAddress.trim());
    final server = await ServerSocket.bind(bindAddress, config.tcpServer.port,
        shared: true);
    _server = server;
    _serverSubscription =
        server.listen(_acceptClient, onError: _incoming.addError);
  }

  void _acceptClient(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _clients.add(socket);
    final subscription = socket.listen(
      _incoming.add,
      onError: _incoming.addError,
      onDone: () => _removeClient(socket),
      cancelOnError: false,
    );
    _clientSubscriptions.add(subscription);
  }

  void _removeClient(Socket socket) {
    _clients.remove(socket);
    socket.destroy();
  }

  @override
  Future<void> send(List<int> bytes) async {
    if (_clients.isEmpty) {
      throw StateError('TCP server has no connected clients.');
    }
    for (final client in List<Socket>.from(_clients)) {
      client.add(bytes);
      await client.flush();
    }
  }

  @override
  Future<void> disconnect() async {
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close();
    _server = null;
    for (final subscription in _clientSubscriptions) {
      await subscription.cancel();
    }
    _clientSubscriptions.clear();
    for (final client in _clients) {
      client.destroy();
    }
    _clients.clear();
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
