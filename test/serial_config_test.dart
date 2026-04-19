import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/domain/connection_config.dart';

void main() {
  test('SerialConfig defaults to driver chunk packet interval', () {
    expect(const SerialConfig().packetIntervalMs, 0);
    expect(const SerialConfig().packetInterval, Duration.zero);
  });

  test('parseSerialPacketDelimiter supports line ending escapes', () {
    expect(parseSerialPacketDelimiter(r'\r\n'), <int>[0x0d, 0x0a]);
    expect(parseSerialPacketDelimiter('/R/N'), <int>[0x0d, 0x0a]);
    expect(parseSerialPacketDelimiter('CRLF'), <int>[0x0d, 0x0a]);
    expect(parseSerialPacketDelimiter(r'\x00'), <int>[0x00]);
  });
}
