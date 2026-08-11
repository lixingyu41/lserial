import '../domain/transport.dart';
import 'platform_capabilities_stub.dart'
    if (dart.library.io) 'platform_capabilities_io.dart'
    if (dart.library.js_interop) 'platform_capabilities_web.dart'
    as impl;

Future<List<TransportCapability>> loadPlatformCapabilities() {
  return impl.loadPlatformCapabilities();
}
