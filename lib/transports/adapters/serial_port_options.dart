const String webSerialPickPortOption = '__web_serial_pick_port__';
const String webSerialSelectedPortOption = 'Web Serial 已选择串口';

bool isSerialPickerOption(String value) => value == webSerialPickPortOption;

bool isGenericSerialPortName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ||
      trimmed == webSerialPickPortOption ||
      trimmed == webSerialSelectedPortOption ||
      trimmed == 'Web Serial';
}

String serialPortOptionLabel(String value) {
  return switch (value) {
    webSerialPickPortOption => '选择 Web Serial 串口...',
    _ => value,
  };
}
