import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/domain/connection_config.dart';

void main() {
  test('SerialConfig defaults to idle gap plus CRLF packet delimiter', () {
    expect(
        const SerialConfig().packetIntervalMs, defaultSerialPacketIntervalMs);
    expect(
      const SerialConfig().packetInterval,
      const Duration(milliseconds: defaultSerialPacketIntervalMs),
    );
    expect(const SerialConfig().packetDelimiter, defaultSerialPacketDelimiter);
    expect(const SerialConfig().packetDelimiterBytes, <int>[0x0d, 0x0a]);
  });

  test('parseSerialPacketDelimiter supports line ending escapes', () {
    expect(parseSerialPacketDelimiter(r'\r\n'), <int>[0x0d, 0x0a]);
    expect(parseSerialPacketDelimiter('/R/N'), <int>[0x0d, 0x0a]);
    expect(parseSerialPacketDelimiter('CRLF'), <int>[0x0d, 0x0a]);
    expect(parseSerialPacketDelimiter(r'\x00'), <int>[0x00]);
  });
}
