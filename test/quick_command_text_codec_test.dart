import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/core/encoding/data_format.dart';
import 'package:lserial/domain/quick_command.dart';
import 'package:lserial/storage/quick_command_text_codec.dart';

void main() {
  test('quick command TXT round trip preserves format name and content', () {
    const commands = <QuickCommand>[
      QuickCommand(
        id: 7,
        name: 'Reset\tmodule',
        content: 'AT+RST\r\nnext\\value',
        format: PayloadFormat.ascii,
      ),
      QuickCommand(
        id: 9,
        name: 'Wake',
        content: 'AA 55 01',
        format: PayloadFormat.hex,
      ),
    ];

    final decoded = decodeQuickCommandsText(
      encodeQuickCommandsText(commands),
    );

    expect(decoded, hasLength(2));
    expect(decoded[0].name, commands[0].name);
    expect(decoded[0].content, commands[0].content);
    expect(decoded[0].format, PayloadFormat.ascii);
    expect(decoded[1].name, 'Wake');
    expect(decoded[1].content, 'AA 55 01');
    expect(decoded[1].format, PayloadFormat.hex);
  });

  test('quick command TXT accepts comments and reports invalid line number',
      () {
    final decoded = decodeQuickCommandsText(
      '# editable list\nASCII\tAT\tAT\nHEX\tWake\tAA 55\n',
    );
    expect(decoded.map((command) => command.name), <String>['AT', 'Wake']);

    expect(
      () => decodeQuickCommandsText('# header\nASCII missing tabs'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Line 2'),
        ),
      ),
    );
  });
}
