import '../../domain/connection_config.dart';
import '../../domain/transport.dart';
import 'bluetooth_transport_stub.dart'
    if (dart.library.js_interop) 'bluetooth_transport_web.dart' as impl;

TransportSession createBluetoothSession(ConnectionConfig config) {
  return impl.createBluetoothSession(config);
}
