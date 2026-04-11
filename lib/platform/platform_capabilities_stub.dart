import '../domain/transport.dart';

Future<List<TransportCapability>> loadPlatformCapabilities() async {
  return TransportType.values
      .map(
        (type) => TransportCapability(
          type: type,
          supported: false,
          reason: 'Unsupported platform.',
        ),
      )
      .toList();
}
