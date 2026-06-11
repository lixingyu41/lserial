import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import 'serial_port_options.dart';

@JS('navigator')
external JSObject get _navigator;

JSObject? _selectedPort;

Future<List<String>> listSerialPorts() async {
  if (!_navigator.has('serial')) {
    return const <String>[];
  }
  return _selectedPort == null
      ? const <String>[webSerialPickPortOption]
      : const <String>[webSerialSelectedPortOption, webSerialPickPortOption];
}

Future<String?> requestSerialPort() async {
  final serial = _navigator['serial'] as JSObject?;
  if (serial == null) {
    throw UnsupportedError('Web Serial is not available in this browser.');
  }
  _selectedPort =
      await serial.callMethod<JSPromise<JSObject>>('requestPort'.toJS).toDart;
  return webSerialSelectedPortOption;
}

TransportSession createSerialSession(ConnectionConfig config) {
  return WebSerialTransportSession(config);
}

class WebSerialTransportSession implements TransportSession {
  WebSerialTransportSession(this.config);

  final ConnectionConfig config;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  JSObject? _port;
  JSObject? _reader;
  Future<void>? _readTask;
  bool _connected = false;
  bool _closing = false;

  @override
  TransportType get type => TransportType.serial;

  @override
  String get label => 'Web Serial';

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> connect() async {
    final port = _selectedPort;
    if (port == null) {
      throw StateError('Select a Web Serial port first.');
    }

    final options = <String, Object>{
      'baudRate': config.serial.baudRate,
      'dataBits': config.serial.dataBits,
      'stopBits': config.serial.stopBits,
      'parity': switch (config.serial.parity) {
        SerialParity.none => 'none',
        SerialParity.odd => 'odd',
        SerialParity.even => 'even',
      },
    }.jsify() as JSObject;

    await port.callMethod<JSPromise<JSAny?>>('open'.toJS, options).toDart;
    _port = port;
    _connected = true;
    _closing = false;
    _readTask = _readLoop(port);
    unawaited(_readTask);
  }

  Future<void> _readLoop(JSObject port) async {
    try {
      while (!_closing) {
        final readable = port['readable'] as JSObject?;
        if (readable == null) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        final reader = readable.callMethod<JSObject>('getReader'.toJS);
        _reader = reader;
        try {
          while (!_closing) {
            final result = await reader
                .callMethod<JSPromise<JSObject>>('read'.toJS)
                .toDart;
            final done = (result['done'] as JSBoolean?)?.toDart ?? false;
            if (done) {
              break;
            }
            final value = result['value'];
            if (value != null) {
              final bytes = (value as JSUint8Array).toDart;
              if (bytes.isNotEmpty) {
                _incoming.add(Uint8List.fromList(bytes));
              }
            }
          }
        } finally {
          if (_reader == reader) {
            _reader = null;
          }
          try {
            reader.callMethod<JSAny?>('releaseLock'.toJS);
          } on Object {
            // The reader may already be released by the browser after cancel.
          }
        }
      }
    } catch (error, stackTrace) {
      if (!_closing && !_incoming.isClosed) {
        _incoming.addError(error, stackTrace);
      }
    }
  }

  @override
  Future<void> send(List<int> bytes) async {
    final port = _port;
    if (port == null || !_connected) {
      throw StateError('Web Serial port is not open.');
    }
    final writable = port['writable'] as JSObject?;
    if (writable == null) {
      throw StateError('Web Serial writable stream is not available.');
    }
    final writer = writable.callMethod<JSObject>('getWriter'.toJS);
    try {
      await writer
          .callMethod<JSPromise<JSAny?>>(
            'write'.toJS,
            Uint8List.fromList(bytes).toJS,
          )
          .toDart;
    } finally {
      writer.callMethod<JSAny?>('releaseLock'.toJS);
    }
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
    _connected = false;
    final reader = _reader;
    if (reader != null) {
      try {
        await reader
            .callMethod<JSPromise<JSAny?>>('cancel'.toJS)
            .toDart
            .timeout(const Duration(seconds: 2));
      } on Object {
        // Continue closing the port even if cancel rejects or times out.
      }
    }
    try {
      await _readTask?.timeout(const Duration(seconds: 2));
    } on Object {
      // Do not leave the UI stuck in disconnecting if the browser read loop hangs.
    } finally {
      _readTask = null;
      _reader = null;
    }
    final port = _port;
    _port = null;
    if (port != null) {
      try {
        await port
            .callMethod<JSPromise<JSAny?>>('close'.toJS)
            .toDart
            .timeout(const Duration(seconds: 2));
      } on Object {
        // The session is considered closed locally; a new session will reopen
        // the selected Web Serial port when the browser has released it.
      }
    }
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
