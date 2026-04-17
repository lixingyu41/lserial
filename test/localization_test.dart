import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/localization.dart';

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
            'Static Web apps cannot open raw TCP sockets in Chrome.'),
      ),
      'Chrome 里的纯静态 Web 应用不能打开原始 TCP Socket。',
    );
  });
}
