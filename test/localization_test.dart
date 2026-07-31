import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/localization.dart';
import 'package:lserial/domain/transport.dart';

void main() {
  test('Chinese localization translates common transport errors', () {
    const strings = AppStrings.zh;

    expect(
      strings.errorMessage(StateError('TCP client is not connected.')),
      'TCP 客户端未连接。',
    );
    expect(
      strings.errorMessage(StateError('BLE service not found: ffe0')),
      '未找到 BLE 服务：ffe0',
    );
    expect(
      strings.errorMessage(
        StateError(
          'No BLE UART writable characteristic found. This device does not expose a serial-like BLE channel.',
        ),
      ),
      '未找到可写 BLE UART 特征。该设备没有暴露类似串口的 BLE 通道。',
    );
    expect(
      strings.errorMessage(
        UnsupportedError(
          'Static Web apps cannot open raw TCP sockets in Chrome.',
        ),
      ),
      'Chrome 中的 Web 页面不能直接打开原始 TCP Socket。',
    );
    expect(
      strings.unsupportedTransportOption(
        TransportType.tcpClient,
        strings.platformReason(
          'Browsers do not expose raw TCP sockets to static web apps.',
        ),
      ),
      'TCP 客户端（Web 不支持）',
    );
    expect(
      strings.transportDisabled(
        TransportType.tcpClient,
        strings.platformReason(
          'Browsers do not expose raw TCP sockets to static web apps.',
        ),
      ),
      'TCP 客户端 Web 不支持：浏览器不开放原始 TCP Socket 给 Web 页面。',
    );
    expect(
      strings.errorMessage(
        const SerialOpenException(
          portName: 'COM17',
          failure: SerialOpenFailure.busyOrPermission,
          nativeCode: 5,
        ),
      ),
      contains('COM17：串口正被其他程序占用'),
    );
    expect(
      strings.errorMessage(
        const SerialOpenException(
          portName: 'COM17',
          failure: SerialOpenFailure.driverInitialization,
        ),
      ),
      contains('设备驱动无法初始化串口参数'),
    );
  });
}
