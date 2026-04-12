import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../../domain/connection_config.dart';
import '../../domain/transport.dart';

Future<List<String>> listSerialPorts() async {
  return SerialPort.availablePorts;
}

Future<String?> requestSerialPort() async => null;

TransportSession createSerialSession(ConnectionConfig config) {
  return DesktopSerialTransportSession(config);
}

class DesktopSerialTransportSession implements TransportSession {
  DesktopSerialTransportSession(this.config);

  final ConnectionConfig config;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;

  @override
  TransportType get type => TransportType.serial;

  @override
  String get label => config.serial.portName;

  @override
  bool get isConnected => _port?.isOpen ?? false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    final serial = config.serial;
    if (serial.portName.isEmpty) {
      throw StateError('No serial port selected.');
    }

    final port = SerialPort(serial.portName);
    if (!port.openReadWrite()) {
      port.dispose();
      throw StateError('Failed to open serial port ${serial.portName}.');
    }

    final portConfig = SerialPortConfig()
      ..baudRate = serial.baudRate
      ..bits = serial.dataBits
      ..stopBits = serial.stopBits
      ..parity = switch (serial.parity) {
        SerialParity.none => SerialPortParity.none,
        SerialParity.odd => SerialPortParity.odd,
        SerialParity.even => SerialPortParity.even,
      };
    portConfig.setFlowControl(SerialPortFlowControl.none);
    port.config = portConfig;

    final reader = SerialPortReader(port);
    _subscription = reader.stream.listen(
      _incoming.add,
      onError: _incoming.addError,
      onDone: () {
        if (!_incoming.isClosed) {
          _incoming.close();
        }
      },
      cancelOnError: false,
    );
    _port = port;
    _reader = reader;
  }

  @override
  Future<void> send(List<int> bytes) async {
    final port = _port;
    if (port == null || !port.isOpen) {
      throw StateError('Serial port is not open.');
    }
    port.write(Uint8List.fromList(bytes));
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _reader?.close();
    _reader = null;
    _port?.close();
    _port?.dispose();
    _port = null;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
